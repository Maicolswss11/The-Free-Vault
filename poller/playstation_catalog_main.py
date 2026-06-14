"""Entry point della sincronizzazione del catalogo PlayStation."""

from __future__ import annotations

import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from . import constants as C
from .logging_config import configure_logging, get_logger
from .playstation_catalog_store import (
    merge_playstation_catalog,
    parse_playstation_page,
    write_playstation_catalog_json,
)
from .playstation_client import (
    PlayStationClientError,
    configured_category_ids,
    configured_locale,
    iter_category_pages,
)
from .supabase_catalog_sink import SupabaseCatalogSink

logger = get_logger(__name__)

DEFAULT_PLAYSTATION_CATALOG_PATH = C.PROJECT_ROOT / "docs" / "playstation-catalog.json"


def _enabled(name: str) -> bool:
    return os.environ.get(name, "").casefold() in {"1", "true", "yes", "on"}


def _locale_path(locale: str) -> str:
    return locale.strip().replace("_", "-").casefold()


def _collect_games(
    pages: Iterable[dict] | None,
    *,
    page_size: int,
    max_pages_per_category: int,
) -> tuple[list, bool, str, tuple[str, ...]]:
    locale = configured_locale()
    categories = configured_category_ids()
    live_fetch = pages is None
    payloads = pages if pages is not None else iter_category_pages(
        category_ids=categories,
        page_size=page_size,
        max_pages_per_category=max_pages_per_category,
        locale=locale,
    )
    include_add_ons = _enabled("PLAYSTATION_INCLUDE_ADD_ONS")
    parsed = []
    for payload in payloads:
        parsed.extend(
            parse_playstation_page(
                payload,
                locale_path=_locale_path(locale),
                include_add_ons=include_add_ons,
            )
        )
    return merge_playstation_catalog(parsed), live_fetch, locale, categories


def _validate_catalog(games: list, *, live_fetch: bool) -> None:
    if not games:
        raise PlayStationClientError(
            "Il catalogo PlayStation ricevuto è vuoto; dati precedenti preservati"
        )
    if live_fetch:
        minimum = max(1, int(os.environ.get("PLAYSTATION_MIN_LISTINGS", "1000")))
        if len(games) < minimum:
            raise PlayStationClientError(
                f"Catalogo PlayStation anormalmente piccolo: {len(games)} < {minimum}"
            )


def run(
    *,
    output_path: Path = DEFAULT_PLAYSTATION_CATALOG_PATH,
    pages: Iterable[dict] | None = None,
    now: datetime | None = None,
    page_size: int = 1_000,
    max_pages_per_category: int = 50,
) -> int:
    """Genera un JSON locale senza toccare Epic o Steam."""
    now = now or datetime.now(timezone.utc)
    try:
        games, live_fetch, _, _ = _collect_games(
            pages,
            page_size=page_size,
            max_pages_per_category=max_pages_per_category,
        )
        _validate_catalog(games, live_fetch=live_fetch)
        write_playstation_catalog_json(games, output_path, generated_at=now)
        logger.info("Catalogo PlayStation scritto: %d listing", len(games))
        return 0
    except Exception:
        logger.exception("Sincronizzazione catalogo PlayStation fallita")
        return 1


def run_to_supabase(
    *,
    pages: Iterable[dict] | None = None,
    now: datetime | None = None,
    page_size: int = 1_000,
    max_pages_per_category: int = 50,
) -> int:
    """Sincronizza le listing PlayStation nel catalogo canonico Supabase."""
    now = now or datetime.now(timezone.utc)
    sink = SupabaseCatalogSink.from_env()
    run_id: str | None = None

    try:
        run_id = sink.begin("playstation")
        games, live_fetch, locale, categories = _collect_games(
            pages,
            page_size=page_size,
            max_pages_per_category=max_pages_per_category,
        )
        _validate_catalog(games, live_fetch=live_fetch)

        sink.ensure_storage_capacity()
        sync_result = sink.upsert_games_incremental(
            games,
            store="playstation",
            run_id=run_id,
        )
        canonical_count = len({game.match_key for game in games})
        sink.finalize_incremental(
            "playstation",
            run_id,
            listing_count=len(games),
            canonical_count=canonical_count,
            sync_result=sync_result,
            years=[game.release_year for game in games if game.release_year],
            metadata={
                "source": "PlayStation Store categoryGridRetrieve",
                "generated_at": now.isoformat(),
                "received": len(games),
                "locale": locale,
                "category_ids": list(categories),
                "include_add_ons": _enabled("PLAYSTATION_INCLUDE_ADD_ONS"),
                "mode": "incremental",
                "stale_cleanup": "deferred",
            },
        )
        logger.info(
            "Catalogo PlayStation sincronizzato su Supabase: %d listing, %d giochi canonici",
            len(games),
            canonical_count,
        )
        return 0
    except Exception as exc:
        sink.fail("playstation", run_id, exc)
        logger.exception("Sincronizzazione catalogo PlayStation su Supabase fallita")
        return 1


def main() -> int:
    configure_logging()
    page_size = int(os.environ.get("PLAYSTATION_PAGE_SIZE", "1000"))
    max_pages = int(os.environ.get("PLAYSTATION_MAX_PAGES_PER_CATEGORY", "50"))
    if os.environ.get("CATALOG_SINK", "").casefold() == "supabase":
        return run_to_supabase(page_size=page_size, max_pages_per_category=max_pages)
    return run(page_size=page_size, max_pages_per_category=max_pages)


if __name__ == "__main__":
    raise SystemExit(main())
