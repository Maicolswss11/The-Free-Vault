from __future__ import annotations

from pathlib import Path

from poller.supabase_catalog_sink import DEFAULT_INCREMENTAL_BATCH_SIZE

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260610_v414_setbased_catalog_upsert.sql"


def migration_sql() -> str:
    return MIGRATION.read_text(encoding="utf-8").lower()


def test_v414_replaces_row_loop_with_set_based_pipeline():
    sql = migration_sql()
    assert "jsonb_to_recordset(p_rows)" in sql
    assert "on conflict (match_key) do update" in sql
    assert "preclassified as materialized" in sql
    assert "for v_row in" not in sql
    assert "jsonb_array_elements(p_rows)" in sql  # validation only


def test_v414_deduplicates_composite_listing_identity():
    sql = migration_sql()
    assert "distinct on (match_key, listing_store, listing_id)" in sql
    assert "partition by a.match_key, a.listing_store, a.listing_id" in sql
    assert "a.source_priority desc" in sql


def test_v414_preserves_epic_metadata_without_blocking_epic_updates():
    sql = migration_sql()
    assert "p_store <> 'epic'" in sql
    assert "preserve_existing_epic" in sql
    assert "coalesce(b.new_description, b.old_description)" in sql


def test_v414_does_not_use_run_id_as_change_detector():
    sql = migration_sql()
    where_section = sql.split("on conflict (match_key) do update", 1)[1]
    where_section = where_section.split("returning cg.match_key", 1)[0]
    assert "index_run_id is distinct from" not in where_section
    assert "updated_at is distinct from" not in where_section


def test_v414_uses_safe_date_and_validates_store_batch():
    sql = migration_sql()
    assert "catalog_safe_date" in sql
    assert "listing non appartenenti allo store" in sql
    assert "jsonb_typeof(p_rows) <> 'array'" in sql


def test_incremental_batch_is_conservative_on_nano_compute():
    assert DEFAULT_INCREMENTAL_BATCH_SIZE == 100
    epic = (ROOT / ".github/workflows/sync-epic-catalog.yml").read_text(encoding="utf-8")
    steam = (ROOT / ".github/workflows/sync-steam-catalog.yml").read_text(encoding="utf-8")
    assert 'CATALOG_INCREMENTAL_BATCH_SIZE: "100"' in epic
    assert 'CATALOG_INCREMENTAL_BATCH_SIZE: "100"' in steam
