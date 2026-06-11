# The Free Vault v4.6 — Istruzioni patch

## Ordine di applicazione

1. Eseguire nel SQL Editor di Supabase il contenuto di:
   `supabase/migrations/20260611_v46_franchises_editorial.sql`.
2. Estrarre la patch nella root della repository, mantenendo le cartelle.
3. Eseguire i test:

   ```bat
   python -m pytest -v
   ```

4. Pubblicare:

   ```bat
   git add -A
   git commit -m "feat: add franchises and editorial collections v4.6"
   git pull --rebase origin main
   git push origin main
   ```

5. Su Android chiudere e riaprire la PWA, perché la cache frontend passa a
   `the-free-vault-v4-6-franchises-editorial`.

## Configurazione iniziale

Aprire `#/admin/editorial`, completare le bozze **Resident Evil** e
**Alan Wake** associando i relativi `match_key`, impostare ordine di uscita e
ordine narrativo, quindi cambiare lo stato in `published`.

## Workflow

Questa patch non modifica poller o sincronizzazione del catalogo. Non è
necessario rilanciare `Sync Epic Catalog` o `Sync Steam Catalog`.

## Sicurezza e dati

La patch non contiene `docs/config.js`, credenziali o dati personali. Le
operazioni di scrittura editoriali sono protette dal controllo admin esistente.
