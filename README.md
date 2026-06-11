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


## v3.2 — Account completo

La release aggiunge:

- recupero password e pagina per impostarne una nuova;
- modifica email e password;
- avatar su Supabase Storage;
- impostazioni privacy;
- pagina impostazioni con routing dedicato;
- esportazione/importazione dati dalla pagina account;
- eliminazione account tramite Edge Function server-side.

### Aggiornamento database

Esegui nuovamente tutto `supabase/schema.sql` nel **SQL Editor**. È idempotente e aggiunge
`user_settings`, la colonna `profiles.is_public`, il bucket `avatars` e le relative policy RLS.

### Redirect Supabase

Aggiungi agli URL consentiti anche:

```text
https://maicolswss11.github.io/The-Free-Vault/?auth=recovery
https://maicolswss11.github.io/The-Free-Vault/**
```

### Edge Function per eliminare l’account

Installa la Supabase CLI, collega il progetto e pubblica:

```bash
supabase login
supabase link --project-ref IL_TUO_PROJECT_REF
supabase functions deploy delete-account
```

La `service_role` resta esclusivamente nell’ambiente server della Edge Function e non viene mai
inserita nel frontend.


## v3.3 — Social Foundation

La release aggiunge:

- voti pubblici da 1 a 5;
- recensioni pubbliche con supporto spoiler;
- media voto e conteggio sulla pagina gioco;
- profili pubblici raggiungibili con `#/user/<username>`;
- recensioni e liste pubbliche nel profilo;
- pagine lista condivisibili tramite `#/list/<uuid>`;
- privacy RLS collegata alle preferenze di profilo, liste e attività.

Prima del deploy eseguire nel SQL Editor Supabase:

```text
supabase/migrations/20260609_social_v33.sql
```


## v3.3.1 — Stabilizzazione ricerca, filtri e fondazione multi-store

Questa release corregge quattro problemi strutturali:

- la ricerca nella topbar è ora globale, mostra suggerimenti da qualsiasi pagina e
  apre `#/catalog?q=...` soltanto quando si richiede la pagina completa;
- i filtri sono contestuali: vengono nascosti su Home, Gratis ora e In arrivo,
  mentre Catalogo, Libreria e Cronologia mostrano soltanto i controlli utili;
- aggiunta/rimozione e preferiti aggiornano soltanto la card interessata, senza
  ricostruire la pagina e senza riportare lo scroll all'inizio;
- il catalogo distingue `canonical_id` del gioco e `listing_id` del singolo store.

La sincronizzazione Epic arricchisce ogni listing con:

```text
canonical_id
listing_id
category_group
market_segment
market_segment_source
release_year
platforms
```

La classificazione AAA/indie è dichiaratamente conservativa e include il campo
`market_segment_source`; i titoli dubbi restano `unclassified`.

Per preparare Steam, PlayStation e Xbox è inclusa la migrazione:

```text
supabase/migrations/20260610_multistore_v331.sql
```

che crea:

```text
games
game_releases
store_listings
external_game_mappings
```

Il tracker dei giochi gratuiti continua a usare il proprio workflow separato.
Dopo il deploy, avvia manualmente `Sync Epic Catalog` una volta per rigenerare
`docs/catalog.json` con lo schema catalogo v2.


## v3.4 — Community

La v3.4 aggiunge la prima componente sociale completa:

- follow e unfollow tra profili pubblici;
- conteggi follower e seguiti;
- feed degli utenti seguiti e feed pubblico;
- pagina Esplora utenti;
- like alle recensioni e alle liste pubbliche;
- commenti su recensioni e liste;
- notifiche interne per follower, like e commenti;
- badge delle notifiche non lette;
- policy RLS e trigger server-side per attività e notifiche.

### Migrazione richiesta

Nel pannello Supabase apri **SQL Editor**, incolla ed esegui:

```text
supabase/migrations/20260610160000_community_v34.sql
```

La migrazione crea:

```text
user_follows
review_likes
list_likes
content_comments
activities
user_notifications
```

Le notifiche vengono create da trigger PostgreSQL. Il browser non possiede permessi
per inserire direttamente notifiche o attività.

### Nuove route

```text
#/feed
#/explore
#/notifications
```

Le interazioni sociali rispettano `profiles.is_public` e le preferenze
`show_lists` / `show_activity` già presenti in `user_settings`.


# v4.0 — Steam Integration

La v4.0 aggiunge Steam come secondo store senza modificare il tracker dei giochi
gratis Epic.

## Componenti indipendenti

```text
Check Epic Free Games   → ogni 3 ore
Sync Epic Catalog       → una volta al giorno
Sync Steam Catalog      → una volta al giorno
```

I dati Steam sono salvati in `docs/steam-catalog.json`; i dati Epic rimangono in
`docs/catalog.json`. La PWA li unisce in fase di visualizzazione, raggruppando
le listing tramite `match_key`.

## 1. Steam Web API key

Crea una Steam Web API key e salvala in due punti:

### GitHub

Repository → Settings → Secrets and variables → Actions:

```text
STEAM_WEB_API_KEY
```

Serve al workflow `Sync Steam Catalog`.

### Supabase

Project Settings → Edge Functions → Secrets:

```text
STEAM_WEB_API_KEY=<chiave>
APP_BASE_URL=https://maicolswss11.github.io/The-Free-Vault/
```

La chiave non deve comparire in `docs/`, `config.js` o nel repository.

## 2. Migrazione Supabase

Esegui nel SQL Editor:

```text
supabase/migrations/20260610_v40_steam_integration.sql
```

Crea:

- `steam_accounts`;
- `steam_link_states`;
- `user_owned_listings`;
- `canonical_match_queue`.

## 3. Edge Functions

Pubblica:

```text
steam-auth-start
steam-auth-callback
steam-sync-library
```

`steam-auth-callback` deve avere la verifica JWT disattivata perché viene
richiamata direttamente da Steam dopo il login. La funzione verifica comunque
la risposta OpenID e lo state monouso.

Le altre due funzioni devono mantenere la verifica JWT attiva.

## 4. Primo catalogo Steam

Avvia manualmente:

```text
Actions → Sync Steam Catalog → Run workflow
```

La sincronizzazione usa l'API ufficiale
`IStoreService/GetAppList` e scrive `docs/steam-catalog.json`.

## 5. Collegamento utente

Nella PWA:

```text
Impostazioni → Account collegati → Collega Steam
```

Dopo il collegamento, `Importa libreria` usa
`IPlayerService/GetOwnedGames`. Se Steam non restituisce giochi, controlla la
privacy del profilo e rendi visibili i dettagli dei giochi.

## Limiti iniziali

`GetAppList` fornisce un indice affidabile di AppID e nomi, ma non tutte le
schede contengono subito descrizione, prezzo e data. La pagina gioco usa i dati
Epic quando disponibili e mostra la listing Steam come disponibilità aggiuntiva.

Il matching automatico usa il titolo canonico (`match_key`). I casi ambigui
saranno gestiti in seguito tramite `canonical_match_queue`.

## v4.1 — Catalog Performance

La PWA non scarica più `catalog.json` e `steam-catalog.json` completi. Con oltre
160.000 listing, catalogo, ricerca, filtri e paginazione sono eseguiti da
Postgres/Supabase.

### Architettura

```text
Epic free tracker → games.json + history.json → PWA
Epic catalog      → GitHub Actions → Supabase catalog_items
Steam catalog     → GitHub Actions → Supabase catalog_items
PWA               → RPC search_catalog (36 risultati per pagina)
```

La migrazione `20260610_v41_catalog_performance.sql` aggiunge:

- proiezione denormalizzata `catalog_items`;
- stato delle sincronizzazioni per store;
- indici GIN full-text e trigram;
- RPC `search_catalog`, `catalog_stats`, `get_catalog_game` e
  `get_catalog_games`;
- paginazione e filtri server-side.

### Secret GitHub richiesti

```text
SUPABASE_URL
SUPABASE_SECRET_KEY (oppure la legacy SUPABASE_SERVICE_ROLE_KEY)
STEAM_WEB_API_KEY
```

`SUPABASE_SECRET_KEY` (o la legacy `SUPABASE_SERVICE_ROLE_KEY`) viene utilizzata esclusivamente dai workflow e non
deve mai essere inserita in `docs/config.js` o in altri file pubblici.

Dopo la migrazione, eseguire una volta entrambi i workflow:

```text
Sync Epic Catalog
Sync Steam Catalog
```

## v4.1.2 — Canonical catalog read model

`catalog_items` remains the ingestion table. Public catalog RPCs now query the
preaggregated `catalog_games` read model, rebuilt in bounded batches after each
store sync. For an existing populated database, run the manual GitHub Action
**Rebuild Catalog Index** once after applying the v4.1.2 migration.

## v4.1.3 — Incremental Catalog Sync

Il catalogo usa ora `catalog_games` come unica fonte persistente per la ricerca.
I workflow non riempiono più `catalog_items` e non ricostruiscono l'intero indice
canonico dopo ogni sincronizzazione.

Caratteristiche:

- upsert diretto dei soli giochi nuovi o modificati;
- confronto JSONB delle listing per evitare update inutili;
- Steam sincronizzato una volta a settimana;
- Epic sincronizzato ogni giorno;
- soglia prudenziale di 470 MiB prima dell'avvio dei workflow;
- statistiche aggiornate incrementalmente;
- rimozione degli indici di ricerca duplicati più costosi;
- workflow di rebuild completo marcato come legacy e protetto da conferma.

Prima di riattivare i workflow eseguire:

```text
supabase/migrations/20260610_v413_incremental_catalog_sync.sql
```

Le rimozioni di listing non più presenti sono intenzionalmente differite: questa
release privilegia stabilità e riduzione delle scritture sul piano Supabase Free.

## v4.1.5 — Account data isolation

Libreria e liste locali sono ora separate per identità:

```text
tfv:guest:library:v1
tfv:guest:lists:v1
tfv:user:<uuid>:library:v1
tfv:user:<uuid>:lists:v1
```

Il login non importa più automaticamente i dati guest o quelli dell'account
precedente. Al logout l'interfaccia torna immediatamente allo spazio guest.
I push cloud catturano lo user ID che li ha pianificati e vengono annullati al
cambio account, evitando scritture tardive sull'utente successivo.

Le liste importate da backup ricevono nuovi UUID, così non possono collidere
con liste appartenenti a un altro account e protette da RLS.


## v4.2 — Game Journal

La v4.2 introduce il diario personale di gioco senza modificare il tracker Epic
né i workflow del catalogo.

Nuove route:

```text
#/diary
#/stats
```

Funzioni principali:

- stato personale esteso: backlog, in corso, pausa, completato, abbandonato e replay;
- percentuale di avanzamento;
- data di inizio e completamento;
- conteggio completamenti;
- piattaforma principale e difficoltà;
- registrazione di sessioni con durata, progresso, piattaforma e note;
- sessioni private o pubbliche;
- diario filtrabile per testo, mese e piattaforma;
- statistiche mensili, completamenti, backlog e giochi più giocati;
- visualizzazione separata del tempo registrato manualmente e del playtime Steam;
- diario pubblico opzionale nel profilo;
- backup completo di libreria, liste, progressi e sessioni;
- storage locale separato per guest e per UUID account.

Prima del deploy del frontend eseguire:

```text
supabase/migrations/20260610_v42_game_journal.sql
```

La migrazione crea:

```text
user_game_progress
game_diary_entries
user_settings.show_diary
```

Le sessioni pubbliche sono leggibili soltanto se il profilo è pubblico e le
preferenze `show_activity` e `show_diary` sono abilitate.


## v4.3 — Mobile Navigation & UX

La navigazione mobile usa ora due livelli complementari:

- footer con cinque scorciatoie: Home, Gratis, Catalogo, Diario e Libreria;
- drawer laterale richiamabile dall’hamburger con tutte le route del sito.

Il drawer riutilizza la sidebar desktop, supporta backdrop, tasto Escape, focus
circolare e tasto Indietro di Android. I filtri di Catalogo, Libreria e
Cronologia sono mostrati in un pannello mobile dedicato, con conteggio dei
filtri attivi. La topbar mobile espone hamburger, ricerca globale e account,
mentre notifiche e tutte le pagine secondarie restano raggiungibili dal drawer.


## v4.4 — Discovery avanzata

La sezione **Scopri giochi** aggiunge:

- nuove uscite;
- titoli più apprezzati dalla community;
- giochi più recensiti;
- titoli disponibili sia su Epic sia su Steam;
- spotlight indie;
- suggerimenti personalizzati basati sulla libreria;
- pagine dedicate a sviluppatori e publisher;
- giochi correlati nelle schede dettaglio.

Nuove route:

```text
#/discover
#/developer/<nome>
#/publisher/<nome>
```

Prima del deploy del frontend eseguire:

```text
supabase/migrations/20260611_v44_discovery.sql
```

La migrazione aggiunge soltanto RPC leggere e paginate:

```text
catalog_discovery
catalog_entity
catalog_related_games
```

Non crea tabelle aggiuntive né nuovi indici pesanti.

## v4.5 — Catalog Quality & Admin Tools

La sidebar desktop è ora scrollabile anche su finestre basse. L'area
amministrativa è disponibile tramite route protette:

```text
#/admin/catalog
#/admin/matching
#/admin/moderation
#/admin/system
```

Funzioni:

- override persistenti di titolo, descrizione, sviluppatore, publisher,
  copertina, categoria, segmento e anno;
- trigger che riapplica gli override durante i successivi sync Epic/Steam;
- revisione della coda di matching canonico;
- segnalazioni di recensioni, commenti e liste;
- rimozione o archiviazione dei contenuti segnalati;
- audit log delle operazioni amministrative;
- dashboard leggera con dimensione database, catalogo e stato sync.

Prima del deploy eseguire:

```text
supabase/migrations/20260611_v45_admin_tools.sql
```

Dopo la migrazione assegnare manualmente il primo amministratore dal SQL
Editor, sostituendo l'indirizzo email:

```sql
insert into public.admin_users (user_id, role)
select id, 'admin'
from auth.users
where email = 'tuo-indirizzo@example.com'
on conflict (user_id) do update set
  role = excluded.role,
  updated_at = now();
```

La tabella del catalogo non viene duplicata e la migrazione non aggiunge indici
GIN o altre strutture pesanti.
