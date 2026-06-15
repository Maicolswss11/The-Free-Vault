from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_franchise_mass_editor_is_exposed_in_frontend():
    html = read("docs/index.html")
    app = read("docs/app.js")
    franchise = read("docs/franchise.js")

    assert 'id="admin-franchise-mass-editor"' in html
    assert 'id="admin-franchise-editor-select-all"' in html
    assert 'id="admin-franchise-apply-type"' in html
    assert 'id="admin-franchise-number-release"' in html
    assert 'id="admin-franchise-number-narrative"' in html
    assert 'id="admin-franchise-save-selected"' in html
    assert 'id="admin-franchise-save-all"' in html
    assert 'id="admin-franchise-remove-selected"' in html
    assert "function syncFranchiseEditorRows" in app
    assert "function saveFranchiseEditorRows" in app
    assert "removeAdminFranchiseGames" in franchise
    assert "offset += 100" in franchise


def test_franchise_mass_removal_rpc_is_versioned():
    migration = read("supabase/migrations/20260615_v51_franchise_mass_editor.sql")
    schema = read("supabase/schema.sql")

    for sql in (migration, schema):
        assert "admin_remove_franchise_games_batch" in sql
        assert "jsonb_array_elements_text" in sql
        assert "franchise_games_batch_removed" in sql
    assert "notify pgrst, 'reload schema'" in migration.lower()


def test_store_logos_and_multistore_actions_are_local():
    app = read("docs/app.js")
    html = read("docs/index.html")
    worker = read("docs/service-worker.js")

    assert "function storeLogoPath" in app
    assert "function commercialListingsForGame" in app
    assert "function configureStoreAction" in app
    assert "Confronta ${stores.length} store" in app
    assert "Nessuna disponibilità digitale registrata" in app
    assert 'id="game-page-availability"' in html

    for name in ("steam", "epic", "playstation", "xbox", "gog", "nintendo"):
        assert (ROOT / f"docs/icons/stores/{name}.svg").is_file()
        assert f'"./icons/stores/{name}.svg"' in worker


def test_navigation_uses_svg_icons_and_account_is_improved():
    html = read("docs/index.html")
    css = read("docs/styles.css")

    assert 'id="icon-bell"' in html
    assert '<use href="#icon-bell"></use>' in html
    assert 'class="account-chevron"' in html
    assert "Catalogo universale" in html
    assert ".nav-icon" in css
    assert "border-radius: 50%" in css


def test_v51_cache_name_is_current():
    worker = read("docs/service-worker.js")
    assert 'const CACHE_NAME = "the-free-vault-v5-1-frontend-editorial-overhaul"' in worker
