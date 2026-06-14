"""Bulk synchronization of catalog listings into Supabase.

This module is used only by GitHub Actions with the service-role key stored in
repository secrets. The key is never written to the generated web app.
"""

from __future__ import annotations

import hashlib
import json
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
DEFAULT_INCREMENTAL_BATCH_SIZE = 100
DEFAULT_MAX_DATABASE_BYTES = 470 * 1024 * 1024


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


def game_to_incremental_row(game: StoreGame) -> dict[str, object]:
    """Convert a listing to the compact canonical upsert payload.

    The listing object intentionally mirrors the JSON structure already stored
    in ``catalog_games.store_listings``. PostgreSQL can therefore compare JSONB
    values directly and skip writes for unchanged games.
    """
    listing = {
        "listing_id": game.listing_id,
        "store": game.store,
        "external_id": game.external_id,
        "namespace": game.namespace,
        "title": game.title,
        "store_url": game.store_url,
        "image_url": game.image_url,
        "offer_type": game.offer_type,
        "category_group": game.category_group,
        "edition_name": game.edition_name,
        "original_price": game.original_price,
        "discount_price": game.discount_price,
        "currency_code": game.currency_code,
        "currency_decimals": game.currency_decimals,
        "fmt_original_price": game.fmt_original_price,
        "fmt_discount_price": game.fmt_discount_price,
    }
    row = {
        "match_key": game.match_key,
        "canonical_id": game.canonical_id,
        "title": game.title,
        "canonical_title": game.canonical_title,
        "description": game.description or None,
        "developer": game.developer,
        "publisher": game.publisher,
        "image_url": game.image_url,
        "store_url": game.store_url,
        "release_date": _date_value(game.release_date),
        "release_year": game.release_year,
        "market_segment": game.market_segment,
        "category_group": game.category_group,
        "offer_type": game.offer_type,
        "platforms": game.platforms,
        "genres": game.genres,
        "categories": game.categories,
        "listing": listing,
    }
    # Useful in logs/tests and for future remote diffing. PostgreSQL currently
    # compares JSONB directly, so this hash does not need to be persisted.
    row["source_hash"] = hashlib.sha256(
        json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return row


@dataclass(slots=True)
class IncrementalSyncResult:
    total: int = 0
    inserted_games: int = 0
    updated_games: int = 0
    unchanged_games: int = 0

    def add(self, payload: object) -> None:
        data = payload if isinstance(payload, dict) else {}
        self.total += int(data.get("processed") or 0)
        self.inserted_games += int(data.get("inserted_games") or 0)
        self.updated_games += int(data.get("updated_games") or 0)
        self.unchanged_games += int(data.get("unchanged_games") or 0)

    def to_dict(self) -> dict[str, int]:
        return {
            "total": self.total,
            "inserted_games": self.inserted_games,
            "updated_games": self.updated_games,
            "unchanged_games": self.unchanged_games,
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
                        f"HTTP {response.status_code}: {response.text[:1000]}",
                        response=response,
                    )
                if 400 <= response.status_code < 500:
                    raise SupabaseCatalogError(
                        f"HTTP {response.status_code}: {response.text[:1000]}"
                    )
                response.raise_for_status()
                return response
            except SupabaseCatalogError:
                raise
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

    def ensure_storage_capacity(self, *, max_bytes: int | None = None) -> dict[str, object]:
        """Abort before a heavy sync when the database is near the free-plan limit."""
        configured = max_bytes or int(
            os.environ.get("CATALOG_MAX_DATABASE_BYTES", DEFAULT_MAX_DATABASE_BYTES)
        )
        result = self.rpc("catalog_storage_status", {"p_max_bytes": int(configured)})
        payload = result if isinstance(result, dict) else {}
        database_bytes = int(payload.get("database_bytes") or 0)
        allowed = bool(payload.get("allowed"))
        logger.info(
            "Supabase storage: %.1f MiB / %.1f MiB (catalogo %.1f MiB)",
            database_bytes / 1024 / 1024,
            int(configured) / 1024 / 1024,
            int(payload.get("catalog_bytes") or 0) / 1024 / 1024,
        )
        if not allowed:
            raise SupabaseCatalogError(
                "Sincronizzazione bloccata: il database ha superato la soglia "
                f"prudenziale di {int(configured) / 1024 / 1024:.0f} MiB"
            )
        return payload

    def upsert_games_incremental(
        self,
        games: Iterable[StoreGame],
        *,
        store: str,
        run_id: str,
        batch_size: int | None = None,
    ) -> IncrementalSyncResult:
        """Merge only new or changed canonical rows directly into catalog_games."""
        rows = [game_to_incremental_row(game) for game in games]
        size = batch_size or int(
            os.environ.get("CATALOG_INCREMENTAL_BATCH_SIZE", DEFAULT_INCREMENTAL_BATCH_SIZE)
        )
        size = max(100, min(size, 1_000))
        result = IncrementalSyncResult()

        for batch_number, batch in enumerate(_chunks(rows, size), start=1):
            payload = self.rpc(
                "upsert_catalog_games_incremental",
                {
                    "p_store": store,
                    "p_run_id": run_id,
                    "p_rows": batch,
                },
            )
            result.add(payload)
            logger.info(
                "Catalogo incrementale %s: %d/%d, nuovi=%d aggiornati=%d invariati=%d",
                store,
                min(batch_number * size, len(rows)),
                len(rows),
                result.inserted_games,
                result.updated_games,
                result.unchanged_games,
            )
        return result

    def finalize_incremental(
        self,
        store: str,
        run_id: str,
        *,
        listing_count: int,
        canonical_count: int,
        sync_result: IncrementalSyncResult,
        years: list[int],
        metadata: dict[str, object] | None = None,
    ) -> object:
        result = self.rpc(
            "finalize_incremental_catalog_sync",
            {
                "p_store": store,
                "p_run_id": run_id,
                "p_listing_count": int(listing_count),
                "p_canonical_count": int(canonical_count),
                "p_inserted_games": int(sync_result.inserted_games),
                "p_updated_games": int(sync_result.updated_games),
                "p_unchanged_games": int(sync_result.unchanged_games),
                "p_years": sorted(set(int(year) for year in years if year)),
                "p_metadata": metadata or {},
            },
        )
        logger.info("Sincronizzazione incrementale completata: %s", result)
        return result

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


    def rebuild_read_model(
        self,
        *,
        batch_size: int = 1_000,
        max_batches: int = 1_000,
    ) -> object:
        """Rebuild the canonical catalog read model in bounded RPC batches."""
        batch_size = max(100, min(int(batch_size), 2_500))
        run_id = str(uuid.uuid4())
        after_key: str | None = None

        self.rpc("begin_catalog_index_rebuild", {"p_run_id": run_id})
        logger.info("Ricostruzione indice catalogo avviata: run=%s", run_id)

        try:
            processed_total = 0
            for batch_number in range(1, max_batches + 1):
                result = self.rpc(
                    "rebuild_catalog_index_batch",
                    {
                        "p_run_id": run_id,
                        "p_after_match_key": after_key,
                        "p_limit": batch_size,
                    },
                )
                payload = result if isinstance(result, dict) else {}
                processed = int(payload.get("processed") or 0)
                processed_total += processed
                next_key = payload.get("next_key")
                done = bool(payload.get("done"))

                logger.info(
                    "Indice catalogo: batch %d, elaborati %d (%d totali)",
                    batch_number,
                    processed,
                    processed_total,
                )

                if done or processed == 0:
                    final = self.rpc(
                        "finalize_catalog_index_rebuild",
                        {"p_run_id": run_id},
                    )
                    logger.info("Indice catalogo completato: %s", final)
                    return final

                if not isinstance(next_key, str) or not next_key:
                    raise SupabaseCatalogError(
                        "Ricostruzione indice senza next_key valido"
                    )
                after_key = next_key

            raise SupabaseCatalogError(
                f"Ricostruzione indice non conclusa dopo {max_batches} batch"
            )
        except Exception as exc:
            try:
                self.rpc(
                    "fail_catalog_index_rebuild",
                    {
                        "p_run_id": run_id,
                        "p_error_message": str(exc),
                    },
                )
            except Exception:
                logger.exception("Impossibile registrare il fallimento indice catalogo")
            raise

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
