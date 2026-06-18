from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_v52_schema_adds_franchise_graph_tables_and_rpcs():
    migration = read("supabase/migrations/20260615_v52_franchise_graph_editorial_import.sql")
    schema = read("supabase/schema.sql")

    for sql in (migration, schema):
        assert "create table if not exists public.franchise_tracks" in sql
        assert "create table if not exists public.franchise_game_tracks" in sql
        assert "create table if not exists public.franchise_game_relations" in sql
        assert "track_type in ('continuity', 'timeline', 'subseries', 'story_arc'" in sql
        assert "canon_status in ('canon', 'alternate_canon', 'reimagining'" in sql
        assert "relation_type in ('sequel_to', 'prequel_to', 'remake_of'" in sql
        assert "admin_export_franchise_editorial" in sql
        assert "admin_import_franchise_editorial" in sql
        assert "tfv-franchise-editorial-v2" in sql
        assert "notify pgrst, 'reload schema'" in sql.lower()


def test_v52_import_is_json_controlled_and_transactional():
    migration = read("supabase/migrations/20260615_v52_franchise_graph_editorial_import.sql")

    assert "p_dry_run boolean default true" in migration
    assert "Il JSON appartiene a un altro franchise" in migration
    assert "Il gioco % non appartiene a questo franchise" in migration
    assert "delete from public.franchise_game_relations" in migration
    assert "delete from public.franchise_tracks" in migration
    assert "franchise_editorial_json_imported" in migration


def test_v52_frontend_exposes_editorial_json_workflow():
    html = read("docs/index.html")
    app = read("docs/app.js")
    client = read("docs/franchise.js")

    for element_id in (
        "admin-franchise-export-json",
        "admin-franchise-copy-prompt",
        "admin-franchise-json-import",
        "admin-franchise-validate-json",
        "admin-franchise-apply-json",
    ):
        assert f'id="{element_id}"' in html

    assert "exportAdminFranchiseEditorial" in client
    assert "importAdminFranchiseEditorial" in client
    assert "buildFranchiseEditorialPrompt" in app
    assert "parseAdminFranchiseEditorialJson" in app
    assert "tfv-franchise-editorial-v2" in app
    assert "downloadJson" in app


def test_v52_public_franchise_page_supports_paths_and_relations():
    html = read("docs/index.html")
    app = read("docs/app.js")
    css = read("docs/styles.css")

    assert 'data-franchise-order="paths"' in html
    assert "FRANCHISE_TRACK_TYPE_LABELS" in app
    assert "FRANCHISE_CANON_LABELS" in app
    assert "FRANCHISE_RELATION_TYPE_LABELS" in app
    assert "function renderFranchiseTrackSection" in app
    assert "function renderFranchiseRelations" in app
    assert 'state.franchiseOrder === "paths"' in app
    assert ".franchise-track-group" in css
    assert ".franchise-relation-card" in css


def test_v52_cache_name_is_current():
    worker = read("docs/service-worker.js")
    assert 'const CACHE_NAME = "ludograph-v5-5-11-franchise-final-polish"' in worker
