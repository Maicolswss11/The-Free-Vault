from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def test_desktop_sidebar_is_scrollable_without_breaking_mobile_drawer():
    css = read("docs/styles.css")
    assert "@media (min-width: 821px)" in css
    assert "overflow-y: auto" in css
    assert "scrollbar-gutter: stable" in css
    assert "body.menu-open .sidebar" in css


def test_admin_routes_navigation_and_assets_exist():
    html = read("docs/index.html")
    app = read("docs/app.js")
    worker = read("docs/service-worker.js")
    assert 'id="admin-nav-section"' in html
    assert 'href="#/admin/catalog"' in html
    assert 'href="#/admin/matching"' in html
    assert 'href="#/admin/moderation"' in html
    assert 'href="#/admin/system"' in html
    assert 'id="admin-page"' in html
    assert 'src="./admin.js"' in html
    assert 'first === "admin"' in app
    assert 'renderAdminPage' in app
    assert '"./admin.js"' in worker
    assert "the-free-vault-v4-5-admin-tools" in worker


def test_admin_client_exposes_catalog_matching_moderation_and_system_methods():
    admin = read("docs/admin.js")
    for method in (
        "getContext",
        "getCatalogRecord",
        "saveCatalogOverride",
        "clearCatalogOverride",
        "listMatches",
        "reviewMatch",
        "listReports",
        "resolveReport",
        "getSystemStatus",
    ):
        assert method in admin


def test_v45_migration_is_role_protected_and_preserves_catalog_overrides():
    sql = read("supabase/migrations/20260611_v45_admin_tools.sql").lower()
    assert "create table if not exists public.admin_users" in sql
    assert "create table if not exists public.catalog_overrides" in sql
    assert "create table if not exists public.moderation_reports" in sql
    assert "create table if not exists public.admin_audit_log" in sql
    assert "security definer" in sql
    assert "public.is_admin()" in sql
    assert "public.can_moderate()" in sql
    assert "catalog_games_apply_override" in sql
    assert "before insert or update on public.catalog_games" in sql
    assert "grant execute on function public.admin_system_status() to authenticated" in sql
    assert "create index" in sql
    assert "using gin" not in sql


def test_reporting_is_available_for_reviews_comments_and_lists():
    social = read("docs/social.js")
    app = read("docs/app.js")
    html = read("docs/index.html")
    sql = read("supabase/migrations/20260611_v45_admin_tools.sql")
    assert "reportContent" in social
    assert 'requestContentReport("review"' in app
    assert 'requestContentReport("comment"' in app
    assert 'requestContentReport("list"' in app
    assert 'id="shared-list-report"' in html
    assert "create or replace function public.report_content" in sql
