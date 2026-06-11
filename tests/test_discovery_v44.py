from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_discovery_routes_and_pages_exist():
    html = read("docs/index.html")
    app = read("docs/app.js")

    assert 'data-route="discover"' in html
    assert 'href="#/discover"' in html
    assert 'id="discovery-page"' in html
    assert 'id="entity-page"' in html
    assert 'id="game-related-section"' in html
    assert 'discover: "discover"' in app
    assert 'name: "entity"' in app
    assert "function renderDiscoveryPage" in app
    assert "function loadEntityPage" in app
    assert "function renderRelatedGames" in app


def test_catalog_api_exposes_discovery_entity_and_related_methods():
    catalog_api = read("docs/catalog-api.js")

    assert 'rpc("catalog_discovery"' in catalog_api
    assert 'rpc("catalog_entity"' in catalog_api
    assert 'rpc("catalog_related_games"' in catalog_api
    assert "getDiscovery" in catalog_api
    assert "getEntity" in catalog_api
    assert "getRelated" in catalog_api


def test_discovery_migration_is_bounded_and_does_not_add_heavy_indexes():
    sql = read("supabase/migrations/20260611_v44_discovery.sql")

    assert "create or replace function public.catalog_discovery" in sql
    assert "create or replace function public.catalog_entity" in sql
    assert "create or replace function public.catalog_related_games" in sql
    assert "set statement_timeout = '15s'" in sql
    assert "greatest(4, least(coalesce(p_limit, 12), 24))" in sql
    assert "limit 80" in sql
    assert "limit 100" in sql
    assert "create index" not in sql.lower()
    assert "create table" not in sql.lower()


def test_game_page_links_developer_and_publisher_entities():
    app = read("docs/app.js")
    assert 'entityRoute("developer", game.developer)' in app
    assert 'entityRoute("publisher", game.publisher)' in app
    assert "void renderRelatedGames(game)" in app


def test_v44_service_worker_cache_is_versioned():
    worker = read("docs/service-worker.js")
    assert 'the-free-vault-v4-5-1-progress-rating-hotfix' in worker
