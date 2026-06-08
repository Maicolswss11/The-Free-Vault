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
