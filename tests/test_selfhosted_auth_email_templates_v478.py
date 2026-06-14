from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATES = ROOT / "supabase" / "email-templates"


def read(name: str) -> str:
    return (TEMPLATES / name).read_text(encoding="utf-8")


def test_all_selfhosted_auth_templates_are_versioned():
    expected = {
        "confirmation.html",
        "invite.html",
        "magic-link.html",
        "email-change.html",
        "recovery.html",
        "reauthentication.html",
    }
    assert expected.issubset({path.name for path in TEMPLATES.glob("*.html")})


def test_link_based_templates_keep_their_required_variables():
    assert "{{ .ConfirmationURL }}" in read("confirmation.html")
    assert "{{ .ConfirmationURL }}" in read("invite.html")
    assert "{{ .ConfirmationURL }}" in read("magic-link.html")
    email_change = read("email-change.html")
    assert "{{ .ConfirmationURL }}" in email_change
    assert "{{ .NewEmail }}" in email_change


def test_recovery_template_is_styled_and_tracking_safe():
    recovery = read("recovery.html")
    assert "{{ .Token }}" in recovery
    assert "{{ .ConfirmationURL }}" not in recovery
    assert "{{ .SiteURL }}#/forgot-password?step=code" in recovery
    assert "Codice di recupero" in recovery
    assert "The Free Vault" in recovery


def test_reauthentication_template_uses_otp():
    template = read("reauthentication.html")
    assert "{{ .Token }}" in template
    assert "{{ .ConfirmationURL }}" not in template
    assert "Codice di verifica" in template
