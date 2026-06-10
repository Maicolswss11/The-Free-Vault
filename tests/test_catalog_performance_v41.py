from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from poller.catalog_models import StoreGame
from poller.supabase_catalog_sink import game_to_catalog_row


ROOT = Path(__file__).resolve().parents[1]


def sample_game() -> StoreGame:
    return StoreGame(
        store="steam",
        external_id="10",
        namespace=None,
        title="Example Game",
        canonical_title="Example Game",
        canonical_id="game:example",
        match_key="title:example",
        listing_id="steam:10",
        description="Description",
        developer="Studio",
        publisher="Publisher",
        image_url="https://example.test/header.jpg",
        store_url="https://store.steampowered.com/app/10/",
        product_slug=None,
        offer_type="BASE_GAME",
        category_group="base_game",
        edition_name=None,
        market_segment="indie",
        market_segment_source="test",
        release_date=datetime(2026, 1, 2, tzinfo=timezone.utc),
        release_year=2026,
        original_price=1999,
        discount_price=999,
        currency_code="EUR",
        currency_decimals=2,
        fmt_original_price="19,99 €",
        fmt_discount_price="9,99 €",
        platforms=["pc"],
        genres=["Action"],
        tags=[],
        categories=["steam/game"],
    )


def test_catalog_row_contains_search_projection_fields():
    row = game_to_catalog_row(
        sample_game(),
        run_id="00000000-0000-0000-0000-000000000001",
        synced_at=datetime(2026, 6, 10, tzinfo=timezone.utc),
    )
    assert row["listing_id"] == "steam:10"
    assert row["canonical_id"] == "game:example"
    assert row["release_date"] == "2026-01-02"
    assert row["sync_run_id"] == "00000000-0000-0000-0000-000000000001"


def test_v41_migration_has_indexed_search_and_pagination_rpc():
    sql = (ROOT / "supabase/migrations/20260610_v41_catalog_performance.sql").read_text(encoding="utf-8")
    assert "create extension if not exists pg_trgm" in sql.lower()
    assert "create table if not exists public.catalog_items" in sql.lower()
    assert "create or replace function public.search_catalog" in sql.lower()
    assert "create or replace function public.get_catalog_game" in sql.lower()
    assert "create index if not exists catalog_items_title_trgm_idx" in sql.lower()


def test_frontend_no_longer_downloads_full_catalog_json():
    app = (ROOT / "docs/app.js").read_text(encoding="utf-8")
    worker = (ROOT / "docs/service-worker.js").read_text(encoding="utf-8")
    index = (ROOT / "docs/index.html").read_text(encoding="utf-8")
    assert 'const CATALOG_URL' not in app
    assert 'const STEAM_CATALOG_URL' not in app
    assert 'VaultCatalog.search' in app
    assert '"/catalog.json"' not in worker
    assert './catalog-api.js' in index


def test_workflows_sync_catalog_to_supabase():
    epic = (ROOT / ".github/workflows/sync-epic-catalog.yml").read_text(encoding="utf-8")
    steam = (ROOT / ".github/workflows/sync-steam-catalog.yml").read_text(encoding="utf-8")
    for workflow in (epic, steam):
        assert "CATALOG_SINK: supabase" in workflow
        assert "SUPABASE_SECRET_KEY" in workflow
        assert "Commit catalog" not in workflow


def test_catalog_sync_uses_incremental_read_model_updates():
    root = Path(__file__).resolve().parents[1]
    sink = (root / "poller" / "supabase_catalog_sink.py").read_text(encoding="utf-8")
    migration = (root / "supabase" / "migrations" / "20260610_v413_incremental_catalog_sync.sql").read_text(encoding="utf-8")
    steam_main = (root / "poller" / "steam_catalog_main.py").read_text(encoding="utf-8")

    assert "def upsert_games_incremental" in sink
    assert '"upsert_catalog_games_incremental"' in sink
    assert "def ensure_storage_capacity" in sink
    assert 'sink.upsert_games_incremental(' in steam_main
    assert 'sink.cleanup_stale("steam", run_id)' not in steam_main
    assert "sink.rebuild_read_model()" not in steam_main
    assert "create or replace function public.upsert_catalog_games_incremental" in migration.lower()
    assert "create or replace function public.catalog_storage_status" in migration.lower()
