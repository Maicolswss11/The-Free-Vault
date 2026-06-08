"""Sincronizzazione indipendente del catalogo Epic."""

from __future__ import annotations

import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from . import constants as C
from .catalog_client import CatalogClientError, iter_catalog_pages
from .catalog_models import StoreGame
from .catalog_store import merge_catalog, parse_catalog_page, write_catalog_json
from .logging_config import configure_logging, get_logger

logger = get_logger(__name__)

DEFAULT_CATALOG_PATH = C.PROJECT_ROOT / "docs" / "catalog.json"


def run(
    *,
    output_path: Path = DEFAULT_CATALOG_PATH,
    page_size: int = 100,
    max_pages: int = 200,
    category: str | None = None,
    pages: Iterable[dict] | None = None,
    now: datetime | None = None,
) -> int:
    """Sincronizza il catalogo senza toccare il tracker gratuito."""
    category = category or os.environ.get(
        "EPIC_CATALOG_CATEGORY",
        "games/edition/base|bundles/games",
    )
    now = now or datetime.now(timezone.utc)

    try:
        payloads = pages or iter_catalog_pages(
            page_size=page_size,
            max_pages=max_pages,
            category=category,
        )
        parsed: list[StoreGame] = []
        for payload in payloads:
            parsed.extend(parse_catalog_page(payload))

        games = merge_catalog(parsed)
        if not games:
            raise CatalogClientError("Il catalogo ricevuto è vuoto; file precedente preservato")

        write_catalog_json(games, output_path, generated_at=now)
        logger.info("Catalogo scritto: %d listing", len(games))
        return 0
    except Exception:
        logger.exception("Sincronizzazione catalogo fallita")
        return 1


def main() -> int:
    configure_logging()
    return run()


if __name__ == "__main__":
    raise SystemExit(main())
