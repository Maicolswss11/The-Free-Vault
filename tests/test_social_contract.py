from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_social_assets_and_routes_exist():
    html = (ROOT / "docs" / "index.html").read_text(encoding="utf-8")
    app = (ROOT / "docs" / "app.js").read_text(encoding="utf-8")
    social = (ROOT / "docs" / "social.js").read_text(encoding="utf-8")
    assert 'src="./social.js"' in html
    assert 'id="public-review-form"' in html
    assert 'id="public-profile-page"' in html
    assert 'id="shared-list-page"' in html
    assert 'name: "public-profile"' in app
    assert 'renderPublicProfilePage' in app
    assert 'renderSharedListPage' in app
    assert 'game_reviews' in social


def test_social_migration_has_rls_and_unique_review():
    sql = (ROOT / "supabase" / "migrations" / "20260609120000_social_v33.sql").read_text(encoding="utf-8")
    assert "create table if not exists public.game_reviews" in sql.lower()
    assert "unique (user_id, game_key)" in sql.lower()
    assert "enable row level security" in sql.lower()
    assert "can_view_user_content" in sql
    assert "Users insert own reviews" in sql
