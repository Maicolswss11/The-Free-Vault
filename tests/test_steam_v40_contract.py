from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_frontend_loads_steam_catalog_and_module():
    app = (ROOT / "docs/app.js").read_text(encoding="utf-8")
    index = (ROOT / "docs/index.html").read_text(encoding="utf-8")
    worker = (ROOT / "docs/service-worker.js").read_text(encoding="utf-8")

    assert 'const STEAM_CATALOG_URL = "./steam-catalog.json";' in app
    assert "groupedCatalogGames" in app
    assert "game-page-store-options" in index
    assert "./steam.js" in index
    assert "/steam-catalog.json" in worker


def test_steam_backend_and_workflow_exist():
    assert (ROOT / "poller/steam_client.py").exists()
    assert (ROOT / "poller/steam_catalog_main.py").exists()
    assert (ROOT / ".github/workflows/sync-steam-catalog.yml").exists()


def test_steam_edge_functions_and_migration_exist():
    assert (ROOT / "supabase/functions/steam-auth-start/index.ts").exists()
    assert (ROOT / "supabase/functions/steam-auth-callback/index.ts").exists()
    assert (ROOT / "supabase/functions/steam-sync-library/index.ts").exists()
    sql = (ROOT / "supabase/migrations/20260610_v40_steam_integration.sql").read_text(encoding="utf-8")
    assert "create table if not exists public.steam_accounts" in sql
    assert "create table if not exists public.user_owned_listings" in sql
