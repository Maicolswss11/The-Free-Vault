# Template email Auth self-hosted

Questa cartella contiene i template HTML usati da Supabase Auth self-hosted.
I file devono essere serviti tramite HTTP da un servizio raggiungibile dal
container `auth`; Supabase Auth non legge direttamente i template da un volume.

## Mappatura dei flussi

| Flusso Supabase | File | Variabile template |
| --- | --- | --- |
| Conferma registrazione | `confirmation.html` | `GOTRUE_MAILER_TEMPLATES_CONFIRMATION` |
| Invito | `invite.html` | `GOTRUE_MAILER_TEMPLATES_INVITE` |
| Magic link | `magic-link.html` | `GOTRUE_MAILER_TEMPLATES_MAGIC_LINK` |
| Cambio email | `email-change.html` | `GOTRUE_MAILER_TEMPLATES_EMAIL_CHANGE` |
| Recupero password OTP | `recovery.html` | `GOTRUE_MAILER_TEMPLATES_RECOVERY` |
| Riautenticazione | `reauthentication.html` | `GOTRUE_MAILER_TEMPLATES_REAUTHENTICATION` |

Il template recovery usa `{{ .Token }}` e non contiene
`{{ .ConfirmationURL }}`: il pulsante apre soltanto la pagina generica di
recupero, quindi il click tracking SMTP non può consumare il token monouso.

## Configurazione self-hosted

Esempio di variabili da aggiungere al servizio `auth`:

```yaml
GOTRUE_MAILER_TEMPLATES_CONFIRMATION: http://email-templates:8080/confirmation.html
GOTRUE_MAILER_TEMPLATES_INVITE: http://email-templates:8080/invite.html
GOTRUE_MAILER_TEMPLATES_MAGIC_LINK: http://email-templates:8080/magic-link.html
GOTRUE_MAILER_TEMPLATES_EMAIL_CHANGE: http://email-templates:8080/email-change.html
GOTRUE_MAILER_TEMPLATES_RECOVERY: http://email-templates:8080/recovery.html
GOTRUE_MAILER_TEMPLATES_REAUTHENTICATION: http://email-templates:8080/reauthentication.html

GOTRUE_MAILER_SUBJECTS_CONFIRMATION: "Conferma il tuo account · The Free Vault"
GOTRUE_MAILER_SUBJECTS_INVITE: "Sei stato invitato su The Free Vault"
GOTRUE_MAILER_SUBJECTS_MAGIC_LINK: "Il tuo link di accesso · The Free Vault"
GOTRUE_MAILER_SUBJECTS_EMAIL_CHANGE: "Conferma il nuovo indirizzo email · The Free Vault"
GOTRUE_MAILER_SUBJECTS_RECOVERY: "Codice di recupero · The Free Vault"
GOTRUE_MAILER_SUBJECTS_REAUTHENTICATION: "Codice di verifica · The Free Vault"
```
