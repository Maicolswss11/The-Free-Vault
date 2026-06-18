from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_v538_importer_is_set_based_and_bounded():
    migration = read("supabase/migrations/20260616_v538_editorial_json_import_performance.sql")
    schema = read("supabase/schema.sql")

    schema_v538 = schema[schema.rfind("-- Ludograph v5.3.8") :]
    for sql in (migration, schema_v538):
        assert "create or replace function public.admin_import_franchise_editorial" in sql.lower()
        assert "set statement_timeout = '30s'" in sql.lower()
        assert "write_strategy', 'set_based'" in sql
        assert "cross join lateral jsonb_array_elements" in sql.lower()
        assert "update public.franchise_games fg" in sql.lower()
        assert "insert into public.franchise_game_tracks" in sql.lower()
        assert "insert into public.franchise_game_relations" in sql.lower()
        assert "for v_game in" not in sql.lower()
        assert "for v_track in" not in sql.lower()
        assert "for v_relation in" not in sql.lower()


def test_v538_membership_canonicity_uses_editorial_fallback():
    migration = read("supabase/migrations/20260616_v538_editorial_json_import_performance.sql")
    assert "game.value #>> '{editorial,canon_status}'" in migration
    assert "'unknown'" in migration


def test_v538_frontend_does_not_consolidate_after_json_import():
    app = read("docs/app.js")
    apply_block = app[app.index('ui.adminFranchiseApplyJson?.addEventListener'):]
    apply_block = apply_block[:apply_block.index('ui.adminFranchiseGameSearchForm?.addEventListener')]

    assert "importAdminFranchiseEditorial(franchise.id, payload, false)" in apply_block
    assert "getAdminFranchise(franchise.id)" in apply_block
    assert "await window.VaultFranchises.consolidateAdminFranchiseVariants" not in apply_block


def test_v538_cache_name_is_current():
    worker = read("docs/service-worker.js")
    assert 'const CACHE_NAME = "ludograph-v5-5-11-franchise-final-polish"' in worker
