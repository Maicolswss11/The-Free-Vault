from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "20260621_v5603_fast_canonical_search_results.sql"
CATALOG_API = ROOT / "docs" / "catalog-api.js"
WORKER = ROOT / "docs" / "service-worker.js"


def test_v563_search_keeps_candidate_first_plan_and_groups_only_candidates():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "v_candidate_keys" in sql
    assert "v_candidate_limit" in sql
    assert "candidate_keys as materialized" in sql
    assert "featured as materialized" in sql
    assert "search_group_key" in sql
    assert "canonical_strategy', 'candidate_first_grouping'" in sql
    assert "from public.catalog_games cg" in sql
    assert "group by coalesce(public.catalog_resolve_canonical_key" not in sql


def test_v563_search_collapses_visible_store_and_port_variants():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "has_porting_signal" in sql
    assert "is_variant_candidate" in sql
    assert "source_kind <> 'master'" in sql
    assert "public.catalog_is_subordinate_game_type" in sql
    assert "abs(peer.year_value - f.year_value) <= 2" in sql
    assert "bundle containing" in sql
    assert "search_variant_count" in sql


def test_v563_frontend_has_search_group_fallback_deduplication():
    api = CATALOG_API.read_text(encoding="utf-8")
    assert "item?.search_group_key || item?.canonical_work_key" in api
    assert "function hasPortingOrEditionSignal" in api
    assert "function hasCatalogStoreFootprint" in api
    assert "hasVariantSignal" in api


def test_v563_cache_name_updated_for_frontend_dedupe_change():
    worker = WORKER.read_text(encoding="utf-8")
    assert 'const CACHE_NAME = "ludograph-v5-6-5-catalog-list-and-offer-polish"' in worker
    assert 'ludograph-v5-6-0-canonical-catalog-foundation' in worker
