from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def test_search_migration_pages_lightweight_keys_before_full_rows():
    sql = read("supabase/migrations/20260612_v474_catalog_search_performance.sql").lower()
    assert "eligible as not materialized" in sql
    assert "paged_keys as" in sql
    assert "join public.catalog_games cg on cg.match_key = pk.match_key" in sql
    assert "public.catalog_game_card_json(cg)" in sql
    assert "select\n    cg.*" not in sql
    assert "similarity(lower(cg.title), p.q) >=" not in sql


def test_search_uses_indexable_trigram_operator_without_new_indexes():
    sql = read("supabase/migrations/20260612_v474_catalog_search_performance.sql").lower()
    assert "operator(extensions.%)" in sql
    assert "lower(cg.title) like '%' || p.q || '%'" in sql
    assert "create index" not in sql
    assert "drop index" not in sql
    assert "analyze public.catalog_games" in sql
    assert "set pg_trgm.similarity_threshold" not in sql


def test_catalog_input_does_not_send_two_live_search_requests():
    app = read("docs/app.js")
    assert 'if (state.route.name === "catalog") {' in app
    assert "Do not\n    // launch a second autocomplete RPC" in app
    assert "state.globalSearch && state.globalSearch.length < 3" in app
    assert "}, 450);" in app
    assert "if (query.length < 3)" in app


def test_v474_cache_and_schema_are_updated():
    worker = read("docs/service-worker.js")
    schema = read("supabase/schema.sql").lower()
    assert "the-free-vault-v4-7-4-catalog-search-performance" in worker
    assert "catalog search v4.7.4" in schema
    assert "eligible as not materialized" in schema
