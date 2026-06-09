from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_global_search_is_suggestion_based():
    html = (ROOT / "docs" / "index.html").read_text(encoding="utf-8")
    app = (ROOT / "docs" / "app.js").read_text(encoding="utf-8")

    assert 'id="global-search-results"' in html
    assert "renderGlobalSearchResults" in app
    assert '#/catalog?q=${encodeURIComponent(' in app
    assert 'if (!routeToDashboardView(state.route.name)' not in app


def test_contextual_filters_exist_and_free_pages_do_not_use_them():
    html = (ROOT / "docs" / "index.html").read_text(encoding="utf-8")
    app = (ROOT / "docs" / "app.js").read_text(encoding="utf-8")

    for control_id in (
        "store-filter",
        "category-filter",
        "segment-filter",
        "price-filter",
        "year-filter",
    ):
        assert f'id="{control_id}"' in html

    assert 'const controlsVisible = ["catalog", "library", "history"].includes(route);' in app


def test_library_toggle_does_not_full_render_dashboard():
    app = (ROOT / "docs" / "app.js").read_text(encoding="utf-8")

    assert "toggleLibraryWithoutRerender" in app
    assert "refreshGamePresentation(game)" in app
    assert "libraryButton.onclick = () => toggleLibraryWithoutRerender(game);" in app


def test_multistore_sql_foundation_is_present():
    sql = (
        ROOT / "supabase" / "migrations" / "20260610_multistore_v331.sql"
    ).read_text(encoding="utf-8")

    assert "create table if not exists public.games" in sql
    assert "create table if not exists public.game_releases" in sql
    assert "create table if not exists public.store_listings" in sql
    assert "create table if not exists public.external_game_mappings" in sql
