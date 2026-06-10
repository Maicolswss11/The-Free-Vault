"""Bulk synchronization of catalog listings into Supabase.

This module is used only by GitHub Actions with the service-role key stored in
repository secrets. The key is never written to the generated web app.
"""

from __future__ import annotations

import os
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Iterable, Iterator

import requests

from .catalog_models import StoreGame
from .logging_config import get_logger

logger = get_logger(__name__)

ENV_SUPABASE_URL = "SUPABASE_URL"
ENV_SUPABASE_SECRET_KEY = "SUPABASE_SECRET_KEY"
ENV_SUPABASE_SERVICE_ROLE_KEY = "SUPABASE_SERVICE_ROLE_KEY"  # legacy fallback
DEFAULT_BATCH_SIZE = 1_000


class SupabaseCatalogError(RuntimeError):
    """Catalog ingestion failed."""


def _chunks(items: list[dict[str, object]], size: int) -> Iterator[list[dict[str, object]]]:
    for start in range(0, len(items), size):
        yield items[start : start + size]


def _date_value(value: datetime | None) -> str | None:
    return value.date().isoformat() if value else None


def game_to_catalog_row(
    game: StoreGame,
    *,
    run_id: str,
    synced_at: datetime,
) -> dict[str, object]:
    """Convert a normalized store listing to the public search projection."""
    return {
        "listing_id": game.listing_id,
        "canonical_id": game.canonical_id,
        "match_key": game.match_key,
        "store": game.store,
        "external_id": game.external_id,
        "namespace": game.namespace,
        "title": game.title,
        "canonical_title": game.canonical_title,
        "description": game.description or None,
        "developer": game.developer,
        "publisher": game.publisher,
        "image_url": game.image_url,
        "store_url": game.store_url,
        "product_slug": game.product_slug,
        "offer_type": game.offer_type,
        "category_group": game.category_group,
        "edition_name": game.edition_name,
        "market_segment": game.market_segment,
        "release_date": _date_value(game.release_date),
        "release_year": game.release_year,
        "original_price": game.original_price,
        "discount_price": game.discount_price,
        "currency_code": game.currency_code,
        "currency_decimals": game.currency_decimals,
        "fmt_original_price": game.fmt_original_price,
        "fmt_discount_price": game.fmt_discount_price,
        "platforms": game.platforms,
        "genres": game.genres,
        "tags": game.tags,
        "categories": game.categories,
        "available": True,
        "sync_run_id": run_id,
        "last_synced_at": synced_at.isoformat(),
    }


@dataclass(slots=True)
class SupabaseCatalogSink:
    base_url: str
    service_role_key: str
    batch_size: int = DEFAULT_BATCH_SIZE
    session: requests.Session | None = None

    def __post_init__(self) -> None:
        self.base_url = self.base_url.rstrip("/")
        self.session = self.session or requests.Session()
        self.batch_size = max(100, min(int(self.batch_size), 2_000))

    @classmethod
    def from_env(cls) -> "SupabaseCatalogSink":
        url = os.environ.get(ENV_SUPABASE_URL, "").strip()
        key = (
            os.environ.get(ENV_SUPABASE_SECRET_KEY, "").strip()
            or os.environ.get(ENV_SUPABASE_SERVICE_ROLE_KEY, "").strip()
        )
        if not url or not key:
            raise SupabaseCatalogError(
                f"Mancano {ENV_SUPABASE_URL} e una chiave tra "
                f"{ENV_SUPABASE_SECRET_KEY}/{ENV_SUPABASE_SERVICE_ROLE_KEY}"
            )
        batch_size = int(os.environ.get("CATALOG_UPSERT_BATCH_SIZE", DEFAULT_BATCH_SIZE))
        return cls(url, key, batch_size=batch_size)

    @property
    def headers(self) -> dict[str, str]:
        return {
            "apikey": self.service_role_key,
            "Authorization": f"Bearer {self.service_role_key}",
            "Content-Type": "application/json",
        }

    def _request(
        self,
        method: str,
        url: str,
        *,
        json_payload: object,
        extra_headers: dict[str, str] | None = None,
        attempts: int = 5,
    ) -> requests.Response:
        headers = {**self.headers, **(extra_headers or {})}
        last_error: Exception | None = None
        for attempt in range(1, attempts + 1):
            try:
                response = self.session.request(
                    method,
                    url,
                    json=json_payload,
                    headers=headers,
                    timeout=(15, 120),
                )
                if response.status_code == 429 or response.status_code >= 500:
                    raise requests.HTTPError(
                        f"HTTP {response.status_code}: {response.text[:500]}",
                        response=response,
                    )
                response.raise_for_status()
                return response
            except requests.RequestException as exc:
                last_error = exc
                if attempt >= attempts:
                    break
                delay = min(20, 2 ** (attempt - 1))
                logger.warning(
                    "Supabase tentativo %d/%d fallito; nuovo tentativo tra %ds: %s",
                    attempt,
                    attempts,
                    delay,
                    exc,
                )
                time.sleep(delay)
        raise SupabaseCatalogError(f"Richiesta Supabase fallita: {last_error}") from last_error

    def rpc(self, function: str, payload: dict[str, object]) -> object:
        response = self._request(
            "POST",
            f"{self.base_url}/rest/v1/rpc/{function}",
            json_payload=payload,
        )
        if not response.content:
            return None
        return response.json()

    def begin(self, store: str) -> str:
        run_id = str(uuid.uuid4())
        self.rpc("begin_catalog_sync", {"p_store": store, "p_run_id": run_id})
        logger.info("Sincronizzazione Supabase avviata: store=%s run=%s", store, run_id)
        return run_id

    def upsert_games(
        self,
        games: Iterable[StoreGame],
        *,
        run_id: str,
        synced_at: datetime | None = None,
    ) -> int:
        synced_at = synced_at or datetime.now(timezone.utc)
        rows = [game_to_catalog_row(game, run_id=run_id, synced_at=synced_at) for game in games]
        total = len(rows)
        for batch_number, batch in enumerate(_chunks(rows, self.batch_size), start=1):
            self._request(
                "POST",
                f"{self.base_url}/rest/v1/catalog_items?on_conflict=listing_id",
                json_payload=batch,
                extra_headers={"Prefer": "resolution=merge-duplicates,return=minimal"},
            )
            completed = min(batch_number * self.batch_size, total)
            logger.info("Supabase catalogo: %d/%d listing caricate", completed, total)
        return total

    def cleanup_stale(
        self,
        store: str,
        run_id: str,
        *,
        batch_size: int = 5_000,
        max_batches: int = 1_000,
    ) -> int:
        """Delete stale rows in bounded RPC calls to avoid statement timeouts."""
        batch_size = max(100, min(int(batch_size), 10_000))
        deleted_total = 0

        for batch_number in range(1, max_batches + 1):
            result = self.rpc(
                "cleanup_catalog_sync",
                {
                    "p_store": store,
                    "p_run_id": run_id,
                    "p_limit": batch_size,
                },
            )
            deleted = int(result or 0)
            deleted_total += deleted

            if deleted:
                logger.info(
                    "Supabase cleanup %s: batch %d, eliminate %d righe (%d totali)",
                    store,
                    batch_number,
                    deleted,
                    deleted_total,
                )

            if deleted < batch_size:
                return deleted_total

        raise SupabaseCatalogError(
            f"Cleanup catalogo {store} non concluso dopo {max_batches} batch"
        )

    def finalize(
        self,
        store: str,
        run_id: str,
        *,
        listing_count: int,
        canonical_count: int,
        metadata: dict[str, object] | None = None,
    ) -> object:
        final_metadata = {
            **(metadata or {}),
            "listing_count": int(listing_count),
            "canonical_count": int(canonical_count),
        }
        result = self.rpc(
            "finalize_catalog_sync",
            {
                "p_store": store,
                "p_run_id": run_id,
                "p_metadata": final_metadata,
            },
        )
        logger.info("Sincronizzazione Supabase completata: %s", result)
        return result

    def fail(self, store: str, run_id: str | None, error: Exception) -> None:
        if not run_id:
            return
        try:
            self.rpc(
                "fail_catalog_sync",
                {
                    "p_store": store,
                    "p_run_id": run_id,
                    "p_error_message": str(error),
                },
            )
        except Exception:
            logger.exception("Impossibile registrare il fallimento della sync %s", store)
