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
- `IndexedDB`: libreria personale, note, valutazioni e stato di gioco del singolo browser/dispositivo.

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

## Novità v2.2

- libreria migrata automaticamente da `localStorage` a IndexedDB;
- fallback a `localStorage` sui browser senza IndexedDB;
- valutazione personale da 1 a 5 stelle;
- note personali con salvataggio automatico;
- filtri per giochi da giocare, in corso, completati e abbandonati;
- ricerca estesa alle note e allo stato personale;
- pannello dettagli rifinito per desktop e mobile.
