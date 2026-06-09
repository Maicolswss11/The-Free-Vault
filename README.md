# The Free Vault

Web app/PWA per seguire i giochi gratuiti su Epic Games Store, ricevere notifiche e costruire una libreria personale.

## Funzioni

- rilevamento automatico dei giochi gratis e delle offerte future;
- aggiornamento ogni 3 ore tramite GitHub Actions;
- notifiche Android tramite ntfy;
- copertine scaricate nel repository, così il sito non dipende dal CDN Epic durante la navigazione;
- cronologia delle promozioni viste;
- ricerca e filtri;
- libreria personale locale con preferiti e stato di gioco;
- installazione come PWA e apertura offline dei contenuti già caricati.

## Struttura dati

- `docs/games.json`: offerte correnti e future;
- `docs/history.json`: archivio progressivo delle promozioni;
- `docs/assets/covers/`: cache locale delle copertine;
- `state.json`: deduplicazione delle notifiche;
- `localStorage`: libreria personale del singolo browser/dispositivo.

## Configurazione GitHub

1. Pubblica GitHub Pages dalla branch `main`, cartella `/docs`.
2. Aggiungi in **Settings → Secrets and variables → Actions**:
   - `NTFY_TOPIC`;
   - `NTFY_TOKEN`, solo se il topic è protetto.
3. Avvia manualmente una prima volta il workflow **Check Epic Free Games**.

Dopo il primo run, il workflow aggiorna dati, cronologia e copertine automaticamente.

## Esecuzione locale

```bash
python -m pip install -r poller/requirements.txt
python -m poller.main
```

## Test

```bash
pip install pytest
python -m pytest -v
```

## Privacy della libreria

La libreria personale non viene inviata a GitHub né a Epic. Resta nel browser in uso. Per sincronizzarla fra dispositivi servirà, in una fase successiva, un backend con autenticazione.

## Nota sull'endpoint Epic

Il tracker usa un endpoint pubblico dello storefront non formalmente documentato. Il parser è isolato perché la struttura potrebbe cambiare.

## Novità v2.1

- correzione dei badge Mystery Game rimasti dopo la rivelazione del titolo;
- hero e ricerca mobile rifinite;
- maggiore spazio sopra la navigazione mobile;
- esportazione e importazione della libreria personale in JSON;
- notifiche toast per le operazioni sulla libreria.


## v2.3 — Catalog Foundation

Il tracker gratuito resta indipendente e continua a girare ogni tre ore.

È stato aggiunto un secondo flusso:

```text
Sync Epic Catalog
```

che gira una volta al giorno e aggiorna `docs/catalog.json` tramite lo storefront
GraphQL di Epic. Questo endpoint non è una API consumer formalmente documentata,
quindi la sincronizzazione è isolata e un suo errore non interrompe il tracker.

La web app aggiunge:

- catalogo Epic separato dalle promozioni;
- ricerca su catalogo, sviluppatore e publisher;
- scheda gioco unificata;
- liste personalizzate locali;
- aggiunta/rimozione giochi dalle liste;
- liste private o predisposte come pubbliche;
- backup unico di libreria e liste.

Prima sincronizzazione manuale:

```text
Actions → Sync Epic Catalog → Run workflow
```


### v2.3.1

Corretto il percorso GraphQL Epic e aggiunto fallback automatico tra endpoint.


## v3 — Account e sincronizzazione

La web app supporta account email/password tramite Supabase Auth e sincronizza:

- profilo pubblico;
- libreria personale;
- preferiti e stati;
- liste personalizzate.

### Configurazione

1. Crea un progetto Supabase.
2. Apri **SQL Editor** ed esegui `supabase/schema.sql`.
3. Copia `docs/config.example.js` in `docs/config.js`.
4. Inserisci URL progetto e chiave publishable/anon.
5. In **Authentication → URL Configuration** imposta:
   - Site URL: URL GitHub Pages;
   - Redirect URL: lo stesso URL con `/**`.
6. Fai commit e deploy.

La chiave publishable/anon può stare nel frontend: la protezione dei dati è
affidata alle policy Row Level Security incluse nello schema. Non inserire mai
la `service_role` key.

## v3.1 — Routing & Profiles

La web app usa ora route hash compatibili con GitHub Pages:

```text
#/home
#/free
#/upcoming
#/history
#/catalog
#/game/<id>
#/library
#/lists
#/list/<id>
#/profile
#/login
#/register
```

Le schede gioco, il login, la registrazione e il profilo sono pagine vere della
PWA, non più finestre modali. Il tasto indietro del browser e i link condivisibili
funzionano senza richiedere configurazione server-side.

### Redirect di conferma Supabase

In **Authentication → URL Configuration** imposta:

```text
Site URL:
https://maicolswss11.github.io/The-Free-Vault/
```

Aggiungi ai Redirect URLs sia l'URL esatto sia il wildcard:

```text
https://maicolswss11.github.io/The-Free-Vault/
https://maicolswss11.github.io/The-Free-Vault/?auth=confirmed
https://maicolswss11.github.io/The-Free-Vault/**
```

La registrazione passa esplicitamente a Supabase un `emailRedirectTo` basato
sull'URL di produzione corrente. Al rientro dalla conferma, l'app pulisce i
parametri di autenticazione e apre `#/profile`.

### Accesso e registrazione

- Accesso: email e password.
- Registrazione: username, email, password e conferma password.
- Nome visualizzato e bio si compilano dalla pagina Profilo.

### Dati personali aggiuntivi

La scheda gioco permette di salvare nel JSON sincronizzato di `user_library`:

- stato personale;
- preferito;
- voto da 1 a 5;
- note personali.
