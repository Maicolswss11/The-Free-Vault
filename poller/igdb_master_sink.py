"""Persistenza del catalogo Master IGDB attraverso RPC Supabase."""

from __future__ import annotations

from dataclasses import dataclass

from .igdb_models import MasterBatch
from .supabase_catalog_sink import SupabaseCatalogSink


@dataclass(slots=True)
class SupabaseMasterSink:
    catalog_sink: SupabaseCatalogSink

    @classmethod
    def from_env(cls) -> "SupabaseMasterSink":
        return cls(SupabaseCatalogSink.from_env())

    def begin(self, *, run_id: str, reset_cursor: bool = False) -> dict[str, object]:
        result = self.catalog_sink.rpc(
            "begin_master_catalog_sync",
            {
                "p_provider": "igdb",
                "p_run_id": run_id,
                "p_reset_cursor": bool(reset_cursor),
            },
        )
        return result if isinstance(result, dict) else {}

    def upsert(self, batch: MasterBatch, *, run_id: str, cursor_id: int) -> dict[str, object]:
        result = self.catalog_sink.rpc(
            "upsert_igdb_master_payload",
            {
                "p_payload": batch.as_rpc_payload(
                    run_id=run_id,
                    cursor_id=cursor_id,
                )
            },
        )
        return result if isinstance(result, dict) else {}

    def finish(
        self,
        *,
        run_id: str,
        complete: bool,
        metadata: dict[str, object] | None = None,
    ) -> dict[str, object]:
        result = self.catalog_sink.rpc(
            "finish_master_catalog_sync",
            {
                "p_provider": "igdb",
                "p_run_id": run_id,
                "p_complete": bool(complete),
                "p_metadata": metadata or {},
            },
        )
        return result if isinstance(result, dict) else {}

    def fail(self, *, run_id: str, error_message: str) -> None:
        self.catalog_sink.rpc(
            "fail_master_catalog_sync",
            {
                "p_provider": "igdb",
                "p_run_id": run_id,
                "p_error_message": error_message,
            },
        )
