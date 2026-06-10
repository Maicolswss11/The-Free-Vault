from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_migration_builds_preaggregated_catalog_read_model():
    sql = (ROOT / "supabase/migrations/20260610_v412_catalog_read_model.sql").read_text(
        encoding="utf-8"
    )
    assert "create table if not exists public.catalog_games" in sql
    assert "create table if not exists public.catalog_stats_cache" in sql
    assert "rebuild_catalog_index_batch" in sql
    assert "from public.catalog_games cg" in sql
    assert "grant execute on function public.search_catalog" in sql


def test_sink_rebuilds_read_model_in_bounded_batches():
    source = (ROOT / "poller/supabase_catalog_sink.py").read_text(encoding="utf-8")
    assert "def rebuild_read_model" in source
    assert '"rebuild_catalog_index_batch"' in source
    assert '"finalize_catalog_index_rebuild"' in source


def test_catalog_syncs_share_concurrency_group():
    epic = (ROOT / ".github/workflows/sync-epic-catalog.yml").read_text(encoding="utf-8")
    steam = (ROOT / ".github/workflows/sync-steam-catalog.yml").read_text(encoding="utf-8")
    assert "group: catalog-database-sync" in epic
    assert "group: catalog-database-sync" in steam


def test_manual_rebuild_workflow_exists():
    workflow = (ROOT / ".github/workflows/rebuild-catalog-index.yml").read_text(
        encoding="utf-8"
    )
    assert "workflow_dispatch" in workflow
    assert "python -m poller.catalog_index_main" in workflow
