from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

def test_v55_loads_structural_interface_layer():
    html = read("docs/index.html")
    css = read("docs/interface-rebuild.css")
    assert '<link rel="stylesheet" href="./interface-rebuild.css">' in html
    assert "Ludograph v5.5 — Full Interface Rebuild" in css
    for marker in ["home-stage", "home-diary-preview", "stat-today-minutes", "library-showcase", "profile-dashboard-grid", "game-insight-strip", "franchise-cinematic-layout"]:
        assert marker in html

def test_v55_renders_data_driven_home_library_profile_and_game_views():
    app = read("docs/app.js")
    for marker in ["renderHomeExperience", "renderHomeDiaryPreview", "hydrateHomeHighlights", "renderLibraryExperience", "renderProfileGenres", "gameSummaryProgress", "gamePageBackdrop"]:
        assert marker in app

def test_v55_pwa_cache_includes_interface_layer():
    worker = read("docs/service-worker.js")
    assert 'const CACHE_NAME = "ludograph-v5-5-6-profile-personalization"' in worker
    assert '"./interface-rebuild.css"' in worker

def test_v55_keeps_mobile_and_reduced_motion_support():
    css = read("docs/interface-rebuild.css")
    assert "@media (max-width: 820px)" in css
    assert "@media (max-width: 560px)" in css
    assert "@media (prefers-reduced-motion: reduce)" in css
    assert 'grid-template-areas:' in css
    assert '"resume activity editorial"' in css
