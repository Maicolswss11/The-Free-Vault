"""Import riprendibile dell'enciclopedia IGDB nel database Master."""

from __future__ import annotations

import os
import uuid
from typing import Protocol

from .igdb_client import DEFAULT_PAGE_SIZE, IGDBClient
from .igdb_master_sink import SupabaseMasterSink
from .igdb_models import normalize_igdb_page
from .logging_config import configure_logging, get_logger

logger = get_logger(__name__)


class IGDBSource(Protocol):
    def fetch_games_after(self, after_id: int, *, limit: int) -> list[dict]: ...


class MasterSink(Protocol):
    def begin(self, *, run_id: str, reset_cursor: bool = False) -> dict[str, object]: ...
    def upsert(self, batch, *, run_id: str, cursor_id: int) -> dict[str, object]: ...
    def finish(self, *, run_id: str, complete: bool, metadata=None) -> dict[str, object]: ...
    def fail(self, *, run_id: str, error_message: str) -> None: ...


def _enabled(name: str) -> bool:
    return os.environ.get(name, "").strip().casefold() in {"1", "true", "yes", "on"}


def run(
    *,
    client: IGDBSource | None = None,
    sink: MasterSink | None = None,
    page_size: int | None = None,
    max_pages: int | None = None,
    reset_cursor: bool | None = None,
) -> int:
    """Importa un numero limitato di pagine e salva il cursore nel database.

    La prima esecuzione può essere ripetuta più volte: ogni workflow riparte
    dall'ultimo ID IGDB confermato. Un batch più corto della pagina indica che
    il bootstrap ha raggiunto la fine del catalogo disponibile.
    """

    client = client or IGDBClient.from_env()
    sink = sink or SupabaseMasterSink.from_env()
    size = max(1, min(int(page_size or os.environ.get("IGDB_PAGE_SIZE", DEFAULT_PAGE_SIZE)), 500))
    budget = max(1, min(int(max_pages or os.environ.get("IGDB_MAX_PAGES", 40)), 500))
    reset = _enabled("IGDB_RESET_CURSOR") if reset_cursor is None else bool(reset_cursor)
    run_id = str(uuid.uuid4())

    imported = 0
    raw_received = 0
    cursor = 0
    complete = False

    try:
        state = sink.begin(run_id=run_id, reset_cursor=reset)
        cursor = max(0, int(state.get("cursor_id") or 0))
        logger.info(
            "Bootstrap IGDB avviato: run=%s cursor=%d page_size=%d max_pages=%d",
            run_id,
            cursor,
            size,
            budget,
        )

        for page_number in range(1, budget + 1):
            records = client.fetch_games_after(cursor, limit=size)
            if not records:
                complete = True
                break

            valid_ids = [int(item["id"]) for item in records if isinstance(item.get("id"), int)]
            if not valid_ids:
                raise RuntimeError("La pagina IGDB non contiene ID validi")
            next_cursor = max(valid_ids)
            if next_cursor <= cursor:
                raise RuntimeError(f"Il cursore IGDB non avanza: {next_cursor} <= {cursor}")

            batch = normalize_igdb_page(records)
            result = sink.upsert(batch, run_id=run_id, cursor_id=next_cursor)
            imported += len(batch.games)
            raw_received += len(records)
            cursor = next_cursor
            logger.info(
                "IGDB pagina %d/%d: raw=%d master=%d cursor=%d result=%s",
                page_number,
                budget,
                len(records),
                len(batch.games),
                cursor,
                result,
            )

            if len(records) < size:
                complete = True
                break

        final = sink.finish(
            run_id=run_id,
            complete=complete,
            metadata={
                "source": "IGDB API v4",
                "page_size": size,
                "page_budget": budget,
                "raw_received": raw_received,
                "normalized_games": imported,
                "last_cursor": cursor,
                "bootstrap_complete": complete,
            },
        )
        logger.info("Bootstrap IGDB terminato: %s", final)
        return 0
    except Exception as exc:
        logger.exception("Import IGDB Master fallito")
        try:
            sink.fail(run_id=run_id, error_message=str(exc))
        except Exception:
            logger.exception("Impossibile registrare il fallimento IGDB su Supabase")
        return 1


def main() -> None:
    configure_logging()
    raise SystemExit(run())


if __name__ == "__main__":
    main()
