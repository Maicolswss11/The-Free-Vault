from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "20260618_v5514_canonical_quality_score.sql"
APP = ROOT / "docs" / "app.js"
WORKER = ROOT / "docs" / "service-worker.js"


def test_v5514_migration_scores_canonical_pages_by_content_quality():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "catalog_detail_media_count" in sql
    assert "catalog_review_anchor_count" in sql
    assert "catalog_library_anchor_count" in sql
    assert "f.review_count desc" in sql
    assert "f.library_count desc" in sql
    assert "f.media_count desc" in sql
    assert "case f.source_kind when 'master' then 0" in sql


def test_v5514_game_payload_merges_store_listings_and_aliases():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "listing_rows as materialized" in sql
    assert "merged_listings" in sql
    assert "merged_stores" in sql
    assert "canonical_aliases" in sql
    assert "payload scheda gioco con media canonici e listing store aggregati" in sql


def test_v5514_frontend_uses_canonical_aliases_for_local_data():
    app = APP.read_text(encoding="utf-8")
    assert "const canonicalAliases = Array.isArray(game.canonical_aliases)" in app
    assert "...canonicalAliases" in app
    assert ".map((listing) => listing?.listing_id || listing?.external_id)" in app


def test_v5514_cache_name_is_updated():
    worker = WORKER.read_text(encoding="utf-8")
    assert 'const CACHE_NAME = "ludograph-v5-6-5-catalog-list-and-offer-polish"' in worker
