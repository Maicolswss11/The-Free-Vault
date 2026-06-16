from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "20260616_v535_admin_franchise_search_scalability.sql"
SCHEMA = ROOT / "supabase" / "schema.sql"


def test_v535_uses_bounded_candidate_first_editorial_search():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "v_candidate_keys text[]" in sql
    assert "unnest(v_candidate_keys) with ordinality" in sql
    assert "v_candidate_limit := least(1500" in sql
    assert "lower(cg.title) like '%' || v_q || '%'" in sql
    assert "lower(cg.canonical_title) like '%' || v_q || '%'" in sql
    assert "operator(extensions.%)" in sql
    assert "catalog_game_work_key(cg.match_key)" not in sql
    assert "catalog_game_work_json(representative.match_key)" not in sql


def test_v535_groups_ports_and_duplicate_covers_inside_candidate_boundary():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "catalog_is_subordinate_game_type(cd.game_type)" in sql
    assert "catalog_is_separate_game_type(cd.game_type)" in sql
    assert "public.catalog_editorial_identity(cg.title, cg.image_url)" in sql
    assert "'work:' || ts.primary_master_id" in sql
    assert "'cover:' || cd.cover_identity" in sql
    assert "'variant_role'" in sql
    assert "'variant_count'" in sql
    assert "'variants'" in sql


def test_v535_keeps_rpc_contract_permissions_and_schema_copy():
    sql = MIGRATION.read_text(encoding="utf-8")
    schema = SCHEMA.read_text(encoding="utf-8")
    signature = "public.admin_search_franchise_candidates(text, integer)"
    marker = "Ludograph v5.3.5: bounded candidate-first franchise/editorial search"
    assert signature in sql
    assert "to authenticated" in sql
    assert "notify pgrst, 'reload schema'" in sql.lower()
    assert marker in sql
    assert marker in schema
