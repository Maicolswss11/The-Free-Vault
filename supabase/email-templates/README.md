# Template email Auth self-hosted

Il template `recovery.html` usa `{{ .Token }}` invece di
`{{ .ConfirmationURL }}`. Il recupero password non dipende quindi da link Auth
monouso che un provider SMTP o uno scanner potrebbe aprire anticipatamente.

Supabase Auth self-hosted carica i template da un URL HTTP raggiungibile dal
container `auth`; non legge direttamente file montati nel container.

Configurazione minima:

```yaml
services:
  email-templates:
    image: caddy:2-alpine
    restart: unless-stopped
    command: ["caddy", "file-server", "--root", "/srv", "--listen", ":8080"]
    volumes:
      - ./volumes/email-templates:/srv:ro
```

Nel servizio `auth`:

```yaml
environment:
  GOTRUE_MAILER_TEMPLATES_RECOVERY: http://email-templates:8080/recovery.html
  GOTRUE_MAILER_SUBJECTS_RECOVERY: "Codice di recupero · The Free Vault"
```

Copia `recovery.html` in `volumes/email-templates/`, verifica che
`http://email-templates:8080/recovery.html` sia raggiungibile dal container
`auth`, quindi ricrea i servizi `email-templates` e `auth`.
