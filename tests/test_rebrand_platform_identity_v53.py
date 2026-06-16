from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_v53_rebrands_public_pwa_as_ludograph():
    html = read("docs/index.html")
    manifest = read("docs/manifest.webmanifest")
    app = read("docs/app.js")
    worker = read("docs/service-worker.js")

    assert "<title>Ludograph</title>" in html
    assert '<strong>Ludograph</strong>' in html
    assert '"name": "Ludograph"' in manifest
    assert '`${label} · Ludograph`' in app
    assert 'const CACHE_NAME = "ludograph-v5-3-2-game-works-cloud-sync"' in worker
    assert (ROOT / "docs/icons/brand/ludograph-mark-64.png").is_file()
    assert (ROOT / "docs/icons/icon-192.png").read_bytes().startswith(b"\x89PNG")


def test_v53_uses_local_png_store_brand_assets():
    app = read("docs/app.js")
    worker = read("docs/service-worker.js")
    for name in ("steam", "epic", "playstation", "xbox", "gog", "nintendo"):
        asset = ROOT / f"docs/icons/stores/{name}.png"
        assert asset.is_file()
        assert asset.read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
        assert f'./icons/stores/{name}.png' in app
        assert f'"./icons/stores/{name}.png"' in worker


def test_v53_platform_identity_is_used_in_cards_details_and_franchises():
    html = read("docs/index.html")
    app = read("docs/app.js")
    css = read("docs/styles.css")
    worker = read("docs/service-worker.js")

    assert 'class="platform-chip-list card-platforms"' in html
    assert "function platformBrand" in app
    assert "function platformBadgesMarkup" in app
    assert "platformBadgesMarkup(game.platforms, { limit: 3, compact: true })" in app
    assert 'class="game-platform-meta"' in app
    assert 'class="platform-chip-list franchise-platforms"' in app
    assert ".platform-chip" in css

    for name in ("playstation", "xbox", "nintendo", "windows", "apple", "linux", "sega", "pc", "mobile", "arcade", "retro"):
        assert (ROOT / f"docs/icons/platforms/{name}.png").is_file()
        assert f'"./icons/platforms/{name}.png"' in worker


def test_v53_franchise_pages_have_visual_overview_and_richer_graph():
    html = read("docs/index.html")
    app = read("docs/app.js")
    css = read("docs/styles.css")

    assert 'id="franchise-overview"' in html
    assert "function renderFranchiseOverview" in app
    assert "function franchiseYearRange" in app
    assert "fallbackHero" in app
    assert "franchise-track-kicker" in app
    assert "relation-game" in app
    assert ".franchise-overview-strip" in css
    assert ".track-type-badge" in css


def test_v53_auth_templates_use_new_brand_name():
    templates = list((ROOT / "supabase/email-templates").glob("*.html"))
    assert templates
    for template in templates:
        text = template.read_text(encoding="utf-8")
        assert "The Free Vault" not in text
        assert "Ludograph" in text
