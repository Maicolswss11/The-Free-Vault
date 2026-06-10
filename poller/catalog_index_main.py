"""Manual rebuild of the canonical Supabase catalog read model."""

from __future__ import annotations

from .logging_config import configure_logging, get_logger
from .supabase_catalog_sink import SupabaseCatalogSink

logger = get_logger(__name__)


def run() -> int:
    try:
        sink = SupabaseCatalogSink.from_env()
        sink.rebuild_read_model()
        return 0
    except Exception:
        logger.exception("Ricostruzione indice catalogo fallita")
        return 1


def main() -> int:
    configure_logging()
    return run()


if __name__ == "__main__":
    raise SystemExit(main())
