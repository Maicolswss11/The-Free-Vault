from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def test_public_routes_pages_and_navigation_exist():
    html = read("docs/index.html")
    app = read("docs/app.js")

    assert 'href="#/franchises"' in html
    assert 'id="editorial-directory-page"' in html
    assert 'id="franchise-page"' in html
    assert 'id="editorial-collection-page"' in html
    assert 'first === "franchise"' in app
    assert 'first === "collection"' in app
    assert 'name: "franchise"' in app
    assert 'name: "editorial-collection"' in app
    assert "function renderEditorialDirectory" in app
    assert "function renderFranchisePage" in app
    assert "function renderEditorialCollectionPage" in app


def test_franchise_client_exposes_public_and_admin_methods():
    client = read("docs/franchise.js")
    for method in (
        "getDirectory",
        "getFranchise",
        "getCollection",
        "getMemberships",
        "listAdminFranchises",
        "saveAdminFranchise",
        "saveAdminFranchiseGame",
        "listAdminCollections",
        "saveAdminCollection",
        "saveAdminCollectionGame",
    ):
        assert method in client

    assert 'rpc("editorial_directory"' in client
    assert 'rpc("franchise_detail"' in client
    assert 'rpc("editorial_collection_detail"' in client


def test_v46_migration_uses_four_light_relation_tables_without_catalog_copy():
    sql = read("supabase/migrations/20260611_v46_franchises_editorial.sql").lower()

    for table in (
        "franchises",
        "franchise_games",
        "editorial_collections",
        "editorial_collection_games",
    ):
        assert f"create table if not exists public.{table}" in sql

    assert "references public.catalog_games(match_key)" in sql
    assert "create table if not exists public.catalog_games" not in sql
    assert "create table if not exists public.catalog_items" not in sql
    assert "using gin" not in sql
    assert "release_order" in sql
    assert "narrative_order" in sql
    assert "relation_type" in sql
    assert "spin_off" in sql
    assert "remake" in sql
    assert "dlc" in sql


def test_v46_public_rpcs_and_admin_protection_exist():
    sql = read("supabase/migrations/20260611_v46_franchises_editorial.sql").lower()

    for function in (
        "editorial_directory",
        "franchise_detail",
        "editorial_collection_detail",
        "catalog_editorial_memberships",
    ):
        assert f"create or replace function public.{function}" in sql

    assert "grant execute on function public.editorial_directory() to anon, authenticated" in sql
    assert "grant execute on function public.franchise_detail(text) to anon, authenticated" in sql
    assert "if not public.is_admin()" in sql
    assert "admin_save_franchise_game" in sql
    assert "admin_save_editorial_collection_game" in sql


def test_admin_editorial_panel_is_integrated():
    html = read("docs/index.html")
    app = read("docs/app.js")

    assert 'href="#/admin/editorial"' in html
    assert 'id="admin-panel-editorial"' in html
    assert 'id="admin-franchise-form"' in html
    assert 'id="admin-collection-form"' in html
    assert 'editorial: ui.adminEditorialPanel' in app
    assert 'if (section === "editorial") await loadAdminEditorial()' in app
    assert "function loadAdminEditorial" in app


def test_saga_progress_and_official_collection_distinction_are_visible():
    html = read("docs/index.html")
    app = read("docs/app.js")

    assert 'id="franchise-progress"' in html
    assert 'data-franchise-order="release"' in html
    assert 'data-franchise-order="narrative"' in html
    assert "function renderFranchiseProgress" in app
    assert "COLLEZIONE UFFICIALE" in html
    assert "liste personali" in html.lower()


def test_service_worker_caches_v46_module_and_new_frontend_version():
    worker = read("docs/service-worker.js")
    html = read("docs/index.html")

    assert 'the-free-vault-v4-6-franchises-editorial' in worker
    assert '"./franchise.js"' in worker
    assert 'src="./franchise.js"' in html
