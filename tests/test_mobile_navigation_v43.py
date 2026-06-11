from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_mobile_drawer_reuses_complete_sidebar():
    html = read("docs/index.html")
    app = read("docs/app.js")
    css = read("docs/styles.css")

    assert 'id="app-sidebar"' in html
    assert 'id="menu-button"' in html
    assert 'id="sidebar-close"' in html
    assert 'id="sidebar-backdrop"' in html
    for route in ("upcoming", "history", "feed", "explore", "notifications", "stats", "settings"):
        assert f'data-route="{route}"' in html
    assert "function openMobileMenu()" in app
    assert "function requestCloseMobileMenu()" in app
    assert 'window.addEventListener("popstate"' in app
    assert "trapMobileOverlayFocus" in app
    assert "body.menu-open .sidebar" in css


def test_mobile_footer_has_exactly_five_primary_shortcuts():
    html = read("docs/index.html")
    start = html.index('<nav class="mobile-nav"')
    end = html.index("</nav>", start)
    mobile_nav = html[start:end]

    assert mobile_nav.count('class="mobile-nav-item') == 5
    for route in ("home", "current", "catalog", "diary", "library"):
        assert f'data-route="{route}"' in mobile_nav
    assert 'data-route="lists"' not in mobile_nav


def test_mobile_filters_are_accessible_as_panel():
    html = read("docs/index.html")
    app = read("docs/app.js")
    css = read("docs/styles.css")

    for control in (
        "mobile-filter-toggle",
        "mobile-filter-count",
        "mobile-filter-close",
        "mobile-filter-apply",
        "filter-backdrop",
    ):
        assert f'id="{control}"' in html
    assert "function openMobileFilters()" in app
    assert "activeDashboardFilterCount" in app
    assert "updateMobileFilterSummary" in app
    assert "body.filters-open .toolbar-controls" in css


def test_v43_service_worker_cache_is_versioned():
    service_worker = read("docs/service-worker.js")
    assert 'the-free-vault-v4-4-discovery' in service_worker
