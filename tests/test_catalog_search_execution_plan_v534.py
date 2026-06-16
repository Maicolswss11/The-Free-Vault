from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "20260616_v534_catalog_search_execution_plan.sql"
SCHEMA = ROOT / "supabase" / "schema.sql"


def test_v534_uses_two_phase_bounded_search():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "language plpgsql" in sql
    assert "v_candidate_keys text[]" in sql
    assert "unnest(v_candidate_keys) with ordinality" in sql
    assert "catalog_games_title_trgm_idx" not in sql  # indexes remain owned by v5.3.3
    assert "source_rows as" not in sql
    assert "catalog_game_card_json(cg)" in sql
    assert "Ludograph v5.3.4: two-phase bounded search" in sql


def test_v534_keeps_rpc_contract_and_permissions():
    sql = MIGRATION.read_text(encoding="utf-8")
    signature = (
        "public.search_catalog(text, text[], text, text, text, integer, "
        "text[], text[], text, text, integer, integer)"
    )
    assert signature in sql
    assert "grant execute on function" in sql
    assert "to anon, authenticated" in sql
    assert "notify pgrst, 'reload schema'" in sql.lower()


def test_v534_is_in_cumulative_schema():
    schema = SCHEMA.read_text(encoding="utf-8")
    assert "Ludograph v5.3.4 — deterministic bounded catalog search execution plan" in schema
    assert "v_candidate_keys text[]" in schema
