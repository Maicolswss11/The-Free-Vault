"""Entry point della sincronizzazione indipendente del catalogo Steam."""

from __future__ import annotations

import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from . import constants as C
from .logging_config import configure_logging, get_logger
from .supabase_catalog_sink import SupabaseCatalogSink
from .steam_client import SteamClientError, iter_app_list_pages
from .steam_catalog_store import (
    merge_steam_catalog,
    parse_steam_page,
    write_steam_catalog_json,
)

logger = get_logger(__name__)

DEFAULT_STEAM_CATALOG_PATH = C.PROJECT_ROOT / "docs" / "steam-catalog.json"


def run(
    *,
    output_path: Path = DEFAULT_STEAM_CATALOG_PATH,
    pages: Iterable[dict] | None = None,
    now: datetime | None = None,
    max_results: int = 50_000,
    max_pages: int = 20,
) -> int:
    """Sincronizza Steam senza alterare catalogo e tracker Epic."""
    now = now or datetime.now(timezone.utc)
    include_dlc = os.environ.get("STEAM_INCLUDE_DLC", "").casefold() in {
        "1", "true", "yes", "on",
    }

    try:
        payloads = (
            pages
            if pages is not None
            else iter_app_list_pages(
                max_results=max_results,
                max_pages=max_pages,
                include_dlc=include_dlc,
            )
        )
        parsed = []
        for payload in payloads:
            parsed.extend(parse_steam_page(payload))

        games = merge_steam_catalog(parsed)
        if not games:
            raise SteamClientError(
                "Il catalogo Steam ricevuto è vuoto; file precedente preservato"
            )

        write_steam_catalog_json(games, output_path, generated_at=now)
        logger.info("Catalogo Steam scritto: %d listing", len(games))
        return 0
    except Exception:
        logger.exception("Sincronizzazione catalogo Steam fallita")
        return 1


def run_to_supabase(
    *,
    pages: Iterable[dict] | None = None,
    now: datetime | None = None,
    max_results: int = 50_000,
    max_pages: int = 20,
) -> int:
    """Synchronize Steam listings into Supabase without generating a huge JSON."""
    now = now or datetime.now(timezone.utc)
    include_dlc = os.environ.get("STEAM_INCLUDE_DLC", "").casefold() in {
        "1", "true", "yes", "on",
    }
    sink = SupabaseCatalogSink.from_env()
    run_id: str | None = None

    try:
        run_id = sink.begin("steam")
        payloads = (
            pages
            if pages is not None
            else iter_app_list_pages(
                max_results=max_results,
                max_pages=max_pages,
                include_dlc=include_dlc,
            )
        )
        parsed = []
        for payload in payloads:
            parsed.extend(parse_steam_page(payload))

        games = merge_steam_catalog(parsed)
        if not games:
            raise SteamClientError("Il catalogo Steam ricevuto è vuoto")

        listing_count = sink.upsert_games(games, run_id=run_id, synced_at=now)
        canonical_count = len({game.match_key for game in games})
        sink.cleanup_stale("steam", run_id)
        sink.finalize(
            "steam",
            run_id,
            listing_count=listing_count,
            canonical_count=canonical_count,
            metadata={
                "source": "Steam IStoreService/GetAppList",
                "generated_at": now.isoformat(),
                "received": len(games),
                "include_dlc": include_dlc,
            },
        )
        logger.info("Catalogo Steam sincronizzato su Supabase: %d listing", len(games))
        return 0
    except Exception as exc:
        sink.fail("steam", run_id, exc)
        logger.exception("Sincronizzazione catalogo Steam su Supabase fallita")
        return 1


def main() -> int:
    configure_logging()
    if os.environ.get("CATALOG_SINK", "").casefold() == "supabase":
        return run_to_supabase()
    return run()


if __name__ == "__main__":
    raise SystemExit(main())
