from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def test_auth_callback_errors_are_parsed_before_success_state():
    auth = read("docs/auth.js")
    app = read("docs/app.js")

    assert "readAuthReturnFromLocation" in auth
    assert 'value("error_code")' in auth
    assert 'value("error_description")' in auth
    assert "authErrorDestination" in auth
    assert "returnDetails.error ? null : returnDetails.kind" in auth
    assert "authError: returnDetails.error" in auth

    assert 'new URLSearchParams(rawHash.slice(1))' in app
    assert 'callbackErrorCode === "otp_expired"' in app
    assert 'ui.authConfirmation.hidden = !isCallbackSuccess' in app
    assert 'ui.authCallbackError.hidden = !hasCallbackError' in app
    assert '"Link scaduto o già utilizzato"' in app


def test_auth_error_ui_exists_and_recovery_form_is_preserved():
    html = read("docs/index.html")
    styles = read("docs/styles.css")

    assert 'id="auth-callback-error"' in html
    assert 'id="auth-callback-error-title"' in html
    assert 'id="auth-callback-error-message"' in html
    assert 'id="auth-callback-error-action"' in html
    assert 'id="reset-password-form"' in html
    assert ".auth-confirmation-error" in styles
    assert ".auth-callback-actions" in styles


def test_v476_cache_name_is_updated():
    worker = read("docs/service-worker.js")
    assert 'the-free-vault-v4-7-6-auth-callback-recovery' in worker
