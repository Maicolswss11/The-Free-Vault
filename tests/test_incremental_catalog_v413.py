from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from poller.catalog_models import StoreGame
from poller.supabase_catalog_sink import IncrementalSyncResult, game_to_incremental_row

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


def test_incremental_payload_matches_store_listing_shape():
    row = game_to_incremental_row(sample_game())
    assert row["match_key"] == "title:example"
    assert row["listing"]["listing_id"] == "steam:10"
    assert row["listing"]["store"] == "steam"
    assert len(row["source_hash"]) == 64


def test_incremental_result_accumulates_batches():
    result = IncrementalSyncResult()
    result.add({"processed": 10, "inserted_games": 2, "updated_games": 3, "unchanged_games": 5})
    result.add({"processed": 4, "inserted_games": 0, "updated_games": 1, "unchanged_games": 3})
    assert result.to_dict() == {
        "total": 14,
        "inserted_games": 2,
        "updated_games": 4,
        "unchanged_games": 8,
    }


def test_v413_migration_reduces_write_amplification():
    sql = (ROOT / "supabase/migrations/20260610_v413_incremental_catalog_sync.sql").read_text(encoding="utf-8").lower()
    assert "upsert_catalog_games_incremental" in sql
    assert "finalize_incremental_catalog_sync" in sql
    assert "catalog_storage_status" in sql
    assert "drop index if exists public.catalog_games_search_text_trgm_idx" in sql
    assert "v_existing_listing is distinct from v_listing" in sql


def test_steam_sync_is_weekly_and_full_rebuild_is_guarded():
    steam = (ROOT / ".github/workflows/sync-steam-catalog.yml").read_text(encoding="utf-8")
    rebuild = (ROOT / ".github/workflows/rebuild-catalog-index.yml").read_text(encoding="utf-8")
    assert 'cron: "19 5 * * 0"' in steam
    assert "CATALOG_MAX_DATABASE_BYTES" in steam
    assert "DO_NOT_RUN" in rebuild
    assert "inputs.confirmation == 'REBUILD'" in rebuild
