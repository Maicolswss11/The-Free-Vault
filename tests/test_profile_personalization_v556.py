from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


def test_v556_profile_badges_are_not_fake_gamification():
    html = read("docs/index.html")
    app = read("docs/app.js")

    assert 'id="profile-level-chip"' not in html
    assert 'id="profile-level-badge"' not in html
    assert "Collezionista" not in html
    assert "accountLevelValue" not in app
    assert 'id="profile-member-since-text"' in html
    assert 'id="profile-visibility-text"' in html


def test_v556_account_chevron_opens_real_dropdown():
    html = read("docs/index.html")
    app = read("docs/app.js")
    css = read("docs/interface-rebuild.css")

    assert 'id="account-menu"' in html
    assert 'aria-haspopup="menu"' in html
    assert 'id="account-menu-public"' in html
    assert "toggleAccountMenu" in app
    assert "closeAccountMenu" in app
    assert '.account-button[aria-expanded="true"] .account-chevron' in css


def test_v556_profile_hero_is_persisted_and_selectable():
    html = read("docs/index.html")
    app = read("docs/app.js")
    auth = read("docs/auth.js")
    social = read("docs/social.js")
    schema = read("supabase/schema.sql")
    migration = read("supabase/migrations/20260617_v556_profile_personalization.sql")

    for marker in (
        'id="profile-hero-game-select"',
        'id="profile-hero-upload"',
        'id="profile-hero-reset"',
        'id="profile-hero-url"',
        'id="settings-hero-preview"',
    ):
        assert marker in html

    assert "profile?.hero_image_url" in app
    assert "updateProfileHero" in auth
    assert "uploadProfileHero" in auth
    assert "removeProfileHero" in auth
    assert "hero_image_url" in social
    assert "hero_image_url" in schema
    assert "add column if not exists hero_image_url" in migration


def test_v556_all_routes_use_full_available_width():
    css = read("docs/interface-rebuild.css")
    assert "body .main-column > main" in css
    assert "max-width: none;" in css
    assert "body .community-page" in css
    assert "body .admin-page" in css
