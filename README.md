# Epic Free Games Tracker

Tracker personale dei giochi gratuiti su Epic Games Store.

## Componenti

- poller Python eseguito da GitHub Actions ogni 3 ore;
- notifiche push tramite ntfy;
- PWA statica pubblicata da GitHub Pages;
- stato persistente in `state.json`;
- dati pubblici della PWA in `docs/games.json`.

## Configurazione

1. Crea un repository GitHub pubblico e carica i file.
2. In **Settings → Pages**, pubblica dalla branch `main`, cartella `/docs`.
3. Installa ntfy sul telefono e scegli un topic lungo e casuale.
4. In **Settings → Secrets and variables → Actions**, crea:
   - `NTFY_TOPIC`
   - `NTFY_TOKEN` solo se il topic richiede autenticazione.
5. Avvia manualmente il workflow **Check Epic Free Games** una prima volta.

## Esecuzione locale

```bash
python -m pip install -r poller/requirements.txt
python -m poller.main
```

## Test

Aggiungi `pytest` all'ambiente e avvia:

```bash
pip install pytest
pytest
```

## Note

L'endpoint Epic usato dal poller è pubblico ma non formalmente documentato.
Può cambiare struttura senza preavviso. Il parser è quindi isolato dal resto
dell'applicazione.
