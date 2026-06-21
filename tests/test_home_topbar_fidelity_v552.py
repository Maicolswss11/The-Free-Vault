from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


def test_v552_has_real_home_carousels_and_contextual_activity_icons():
    html = read("docs/index.html")
    app = read("docs/app.js")
    css = read("docs/interface-rebuild.css")

    for marker in [
        'id="hero-carousel-controls"',
        'id="hero-carousel-dots"',
        'id="home-editorial-carousel-controls"',
        'id="home-editorial-dots"',
        'id="icon-trophy"',
        'id="icon-library-add"',
    ]:
        assert marker in html

    for marker in [
        "buildHomeHeroSlides",
        "renderHomeHeroSlide",
        "startHomeHeroRotation",
        "buildHomeCatalogSlides",
        "renderHomeCatalogSlide",
        "buildHomeActivity",
        "homeActivityIcon",
    ]:
        assert marker in app

    assert ".carousel-dot.is-active" in css
    assert ".home-activity-item.is-completed" in css
    assert "text-decoration: none !important" in css


def test_v552_rebuilds_account_presentation_and_updates_cache():
    html = read("docs/index.html")
    app = read("docs/app.js")
    css = read("docs/interface-rebuild.css")
    worker = read("docs/service-worker.js")

    assert 'class="account-copy"' in html
    assert 'id="account-level"' in html
    assert "accountLevelValue" not in app
    assert "updateAccountLevelLabel" in app
    assert 'id="account-menu"' in html
    assert "toggleAccountMenu" in app
    assert ".account-copy small" in css
    assert ".topbar #refresh-button" in css
    assert 'const CACHE_NAME = "ludograph-v5-6-4-catalog-density-and-canonical-offers"' in worker
