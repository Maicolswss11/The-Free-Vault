from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_hash_routes_are_present_in_frontend():
    app = (ROOT / "docs" / "app.js").read_text(encoding="utf-8")
    html = (ROOT / "docs" / "index.html").read_text(encoding="utf-8")
    frontend = app + "\n" + html
    for route in (
        '"#/home"',
        '"#/profile"',
        '"#/login"',
        '"#/register"',
        '`#/game/${',
        '`#/list/${',
    ):
        assert route in frontend


def test_signup_uses_explicit_email_redirect():
    auth = (ROOT / "docs" / "auth.js").read_text(encoding="utf-8")
    assert "emailRedirectTo: confirmationRedirectUrl()" in auth
    assert 'url.searchParams.set("auth", "confirmed")' in auth


def test_primary_content_is_not_a_game_or_profile_dialog():
    html = (ROOT / "docs" / "index.html").read_text(encoding="utf-8")
    assert 'id="game-page"' in html
    assert 'id="profile-page"' in html
    assert 'id="auth-page"' in html
    assert 'id="game-dialog"' not in html
    assert 'id="profile-dialog"' not in html
    assert 'id="auth-dialog"' not in html
