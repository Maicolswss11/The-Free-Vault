from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_v54_loads_separate_visual_design_system():
    html = read("docs/index.html")
    css = read("docs/visual-overhaul.css")

    assert '<link rel="stylesheet" href="./visual-overhaul.css">' in html
    assert "Ludograph v5.4 — Complete Visual Overhaul" in css
    assert "--content-width: 1520px" in css
    assert ".profile-hero" in css
    assert ".game-detail-shell" in css
    assert ".editorial-detail-hero" in css
    assert ".settings-layout" in css
    assert ".admin-tabs" in css
    assert ".mobile-nav" in css


def test_v54_tracks_current_route_for_route_level_presentation():
    app = read("docs/app.js")
    assert "document.body.dataset.route = state.route.name" in app


def test_v54_pwa_caches_visual_layer():
    worker = read("docs/service-worker.js")
    assert 'const CACHE_NAME = "ludograph-v5-6-0-canonical-catalog-foundation"' in worker
    assert '"./visual-overhaul.css"' in worker


def test_v54_keeps_reduced_motion_and_responsive_support():
    css = read("docs/visual-overhaul.css")
    assert "@media (prefers-reduced-motion: reduce)" in css
    assert "@media (max-width: 820px)" in css
    assert "@media (max-width: 640px)" in css
