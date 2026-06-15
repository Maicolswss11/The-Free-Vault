from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def test_recovery_uses_six_digit_otp_and_creates_recovery_session():
    auth = read("docs/auth.js")

    assert "async function verifyRecoveryOtp" in auth
    assert "client.auth.verifyOtp" in auth
    assert "type: 'recovery'" in auth
    assert "replace(/\\D/g, '')" in auth
    assert "/^\\d{6}$/" in auth
    assert "recoveryMode = true" in auth
    assert "verifyRecoveryOtp," in auth


def test_recovery_code_form_and_loading_feedback_exist():
    html = read("docs/index.html")
    app = read("docs/app.js")
    styles = read("docs/styles.css")

    for element_id in (
        "recovery-code-form",
        "recovery-code-email",
        "recovery-code-value",
        "recovery-code-error",
        "recovery-code-submit",
    ):
        assert f'id="{element_id}"' in html

    assert 'autocomplete="one-time-code"' in html
    assert 'pattern="[0-9]{6}"' in html
    assert "window.VaultAuth.verifyRecoveryOtp({ email, token })" in app
    assert 'setButtonLoading(ui.forgotPasswordSubmit, true, "Invio codice…")' in app
    assert 'setButtonLoading(ui.recoveryCodeSubmit, true, "Verifica…")' in app
    assert 'window.sessionStorage.setItem("tfv:recovery-email", email)' in app
    assert ".auth-otp-input" in styles


def test_recovery_email_template_contains_otp_but_no_auth_link():
    template = read("supabase/email-templates/recovery.html")
    instructions = read("supabase/email-templates/README.md")

    assert "{{ .Token }}" in template
    assert "{{ .SiteURL }}#/forgot-password?step=code" in template
    assert "{{ .ConfirmationURL }}" not in template
    assert "GOTRUE_MAILER_TEMPLATES_RECOVERY" in instructions
    assert "GOTRUE_MAILER_SUBJECTS_RECOVERY" in instructions


def test_current_cache_name_is_universal_game_database():
    worker = read("docs/service-worker.js")
    assert 'const CACHE_NAME = "the-free-vault-v5-1-1-editorial-ui-fixes"' in worker
    assert 'the-free-vault-v4-7-9-self-hosted-cutover' in worker
    assert 'the-free-vault-v4-7-6-auth-callback-recovery' in worker
