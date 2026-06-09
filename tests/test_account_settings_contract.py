from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_account_routes_and_forms_exist():
    app = (ROOT / "docs" / "app.js").read_text(encoding="utf-8")
    html = (ROOT / "docs" / "index.html").read_text(encoding="utf-8")
    frontend = app + "\n" + html
    for value in (
        '"forgot-password": "forgot-password"',
        '"reset-password": "reset-password"',
        'name: "settings"',
        'id="forgot-password-form"',
        'id="reset-password-form"',
        'id="settings-page"',
        'id="change-email-form"',
        'id="change-password-form"',
        'id="privacy-form"',
        'id="delete-account-button"',
    ):
        assert value in frontend


def test_auth_supports_recovery_avatar_privacy_and_deletion():
    auth = (ROOT / "docs" / "auth.js").read_text(encoding="utf-8")
    for value in (
        "resetPasswordForEmail",
        "PASSWORD_RECOVERY",
        "updateUser({ password",
        "updateUser({ email",
        ".from('avatars')",
        "updatePrivacy",
        "functions.invoke('delete-account'",
    ):
        assert value in auth


def test_schema_adds_settings_storage_and_private_profiles():
    schema = (ROOT / "supabase" / "schema.sql").read_text(encoding="utf-8")
    for value in (
        "create table if not exists public.user_settings",
        "add column if not exists is_public",
        "Public or own profiles are readable",
        "insert into storage.buckets",
        "Users upload own avatar",
    ):
        assert value in schema


def test_delete_account_edge_function_is_server_side():
    function = (ROOT / "supabase" / "functions" / "delete-account" / "index.ts").read_text(encoding="utf-8")
    assert "SUPABASE_SERVICE_ROLE_KEY" in function
    assert "auth.admin.deleteUser" in function
    assert "auth.getUser" in function
