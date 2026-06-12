from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def test_admin_edge_function_enriches_editorial_games_from_steam():
    source = read("supabase/functions/admin-enrich-catalog-games/index.ts")
    assert '.from("admin_users")' in source
    assert "store.steampowered.com/api/appdetails" in source
    assert "release_date" in source
    assert "release_year" in source
    assert '.from("catalog_games")' in source
    assert ".update(patch)" in source


def test_franchise_admin_can_trigger_and_automatically_run_enrichment():
    html = read("docs/index.html")
    client = read("docs/franchise.js")
    app = read("docs/app.js")
    worker = read("docs/service-worker.js")

    assert 'id="admin-franchise-enrich"' in html
    assert 'functions.invoke("admin-enrich-catalog-games"' in client
    assert "enrichCatalogGames(payload.map((game) => game.gameKey))" in app
    assert "state.admin.selectedFranchise?.games" in app
    assert "the-free-vault-v4-7-2-editorial-steam-metadata" in worker
