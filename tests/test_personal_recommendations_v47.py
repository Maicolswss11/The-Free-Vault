from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def test_v47_migration_adds_only_lightweight_rpcs():
    sql = read("supabase/migrations/20260612_v47_personal_recommendations.sql").lower()

    assert "create or replace function public.catalog_personalized_recommendations" in sql
    assert "create or replace function public.admin_save_franchise_games_batch" in sql
    assert "create table" not in sql
    assert "create index" not in sql
    assert "create table if not exists public.catalog_games" not in sql
    assert "jsonb_array_length(p_games) > 100" in sql
    assert "set statement_timeout = '15s'" in sql


def test_personal_ranking_uses_positive_negative_and_collaborative_signals():
    sql = read("supabase/migrations/20260612_v47_personal_recommendations.sql").lower()

    for signal in (
        "user_library",
        "user_game_progress",
        "game_diary_entries",
        "game_reviews",
        "user_lists",
        "favorite",
        "steamplaytimeminutes",
        "abandoned",
        "similar_users",
        "negative_genres",
        "top_developers",
    ):
        assert signal in sql

    assert "apprezzato da utenti con gusti simili ai tuoi" in sql
    assert "public.can_view_user_content" in sql
    assert "gde.visibility = 'public'" in sql
    assert "perché hai apprezzato" in sql
    assert "grant execute on function public.catalog_personalized_recommendations(integer) to authenticated" in sql


def test_catalog_client_and_discovery_render_personal_recommendations():
    catalog = read("docs/catalog-api.js")
    app = read("docs/app.js")
    html = read("docs/index.html")

    assert 'rpc("catalog_personalized_recommendations"' in catalog
    assert "getRecommendations" in catalog
    assert "clearRecommendationCache" in catalog
    assert 'title: "Per te"' in app
    assert "recommendation-explanation" in app
    assert "getHeuristicDiscoveryRecommendations" in app
    assert "Raccomandazioni ordinate sui tuoi gusti" in html


def test_franchise_admin_supports_multiple_game_selection_and_batch_save():
    html = read("docs/index.html")
    app = read("docs/app.js")
    client = read("docs/franchise.js")

    assert 'id="admin-franchise-batch-toolbar"' in html
    assert 'id="admin-franchise-select-all"' in html
    assert 'id="admin-franchise-deselect-results"' in html
    assert 'id="admin-franchise-selected-list"' in html
    assert 'id="admin-franchise-sort-release"' in html
    assert 'id="admin-franchise-batch-clear"' in html
    assert 'id="admin-franchise-game-submit"' in html
    assert "franchiseGameSelection" in app
    assert "updateAdminFranchiseSelectionUI" in app
    assert "setAdminFranchiseGameSelection" in app
    assert "state.admin.franchiseSearchResults" in app
    assert "searchAdminFranchiseCandidates(query, 50)" in app
    assert "saveAdminFranchiseGames(franchise.id, payload)" in app
    assert 'rpc("admin_save_franchise_games_batch"' in client


def test_v47_cache_and_schema_are_updated():
    worker = read("docs/service-worker.js")
    schema = read("supabase/schema.sql")

    assert 'the-free-vault-v4-7-1-franchise-bulk-selection' in worker
    assert "catalog_personalized_recommendations" in schema
    assert "admin_save_franchise_games_batch" in schema
