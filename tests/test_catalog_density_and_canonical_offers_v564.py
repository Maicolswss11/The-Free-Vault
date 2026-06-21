from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_v564_updates_cache_name():
    worker = (ROOT / "docs" / "service-worker.js").read_text(encoding="utf-8")
    assert 'const CACHE_NAME = "ludograph-v5-6-4-catalog-density-and-canonical-offers"' in worker


def test_v564_catalog_view_toggle_and_compact_grid():
    index = (ROOT / "docs" / "index.html").read_text(encoding="utf-8")
    app = (ROOT / "docs" / "app.js").read_text(encoding="utf-8")
    css = (ROOT / "docs" / "styles.css").read_text(encoding="utf-8")
    assert 'id="catalog-view-toggle"' in index
    assert 'id="catalog-view-grid"' in index
    assert 'id="catalog-view-list"' in index
    assert 'CATALOG_VIEW_KEY' in app
    assert 'setCatalogView("grid")' in app
    assert 'setCatalogView("list")' in app
    assert 'games-grid.is-list-view' in css
    assert 'games-grid.is-compact-catalog' in css


def test_v564_search_catalog_groups_store_offers_and_ports():
    sql = (ROOT / "supabase" / "migrations" / "20260621_v5604_catalog_density_and_canonical_offers.sql").read_text(encoding="utf-8").lower()
    assert "create or replace function public.search_catalog" in sql
    assert "is_store_offer" in sql
    assert "bundle containing" in sql
    assert "undead nightmare expansion" in sql
    assert "g.is_store_offer asc" in sql
    assert "has_porting_signal" in sql
