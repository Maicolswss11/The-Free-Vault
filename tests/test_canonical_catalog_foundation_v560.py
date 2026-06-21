from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "20260621_v5600_canonical_catalog_foundation.sql"
CATALOG_API = ROOT / "docs" / "catalog-api.js"
APP = ROOT / "docs" / "app.js"
WORKER = ROOT / "docs" / "service-worker.js"


def test_v560_creates_alias_and_store_listing_foundation():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "create table if not exists public.catalog_game_aliases" in sql
    assert "create table if not exists public.game_store_listings" in sql
    assert "Steam/Epic/PSN non sono più cataloghi paralleli" in sql
    assert "catalog_resolve_canonical_key" in sql
    assert "catalog_register_canonical_aliases" in sql


def test_v560_get_catalog_game_resolves_to_canonical_route():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "create or replace function public.get_catalog_game" in sql
    assert "v_match_key := public.catalog_resolve_canonical_key(v_key);" in sql
    assert "'canonical_route_key', v_game.match_key" in sql
    assert "'canonical_work_key', public.catalog_work_key_for_game(v_game)" in sql
    assert "'canonical_source'" in sql


def test_v560_search_catalog_returns_canonicalized_results():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "create or replace function public.search_catalog" in sql
    assert "coalesce(public.catalog_resolve_canonical_key(er.match_key), er.match_key) as canonical_key" in sql
    assert "'canonicalized', true" in sql
    assert "'canonical_total'" in sql
    assert "public.catalog_is_master_catalog_game(cg)" in sql


def test_v560_frontend_prefers_canonical_route_and_groups():
    catalog_api = CATALOG_API.read_text(encoding="utf-8")
    app = APP.read_text(encoding="utf-8")
    assert "canonicalDuplicateGroupKey" in catalog_api
    assert "item?.canonical_route_key || item?.canonical_work_key" in catalog_api
    assert "total: Number(data?.canonical_total || data?.total || 0)" in catalog_api
    assert "return game.canonical_route_key || game.match_key" in app
    assert "canonical_work_key: game.canonical_work_key || null" in app


def test_v560_cache_name_is_updated():
    worker = WORKER.read_text(encoding="utf-8")
    assert 'const CACHE_NAME = "ludograph-v5-6-0-canonical-catalog-foundation"' in worker
