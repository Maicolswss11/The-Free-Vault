const DATA_URL = "./games.json";
const HISTORY_URL = "./history.json";
const CATALOG_URL = "./catalog.json";
const LIBRARY_KEY = "the-free-vault-library-v3";
const LEGACY_LIBRARY_KEYS = ["the-free-vault-library-v2"];
const LISTS_KEY = "the-free-vault-lists-v1";
const PLACEHOLDER = "./placeholders/game-placeholder.svg";

const state = {
  current: [],
  upcoming: [],
  history: [],
  catalog: [],
  catalogMeta: null,
  library: loadLibrary(),
  lists: loadJson(LISTS_KEY, {}),
  view: "home",
  search: "",
  statusFilter: "all",
  sort: "relevance",
  selectedGame: null,
  selectedListId: null,
  pendingListGame: null,
};

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];

const ui = {
  grid: $("#games-grid"),
  template: $("#game-card-template"),
  search: $("#search-input"),
  filter: $("#status-filter"),
  sort: $("#sort-select"),
  refresh: $("#refresh-button"),
  status: $("#status-message"),
  title: $("#view-title"),
  eyebrow: $("#view-eyebrow"),
  hero: $("#hero"),
  heroImage: $("#hero-image"),
  heroTitle: $("#hero-title"),
  heroDescription: $("#hero-description"),
  heroPrice: $("#hero-price"),
  heroCountdown: $("#hero-countdown"),
  heroLink: $("#hero-link"),
  heroLibrary: $("#hero-library"),
  sidebarUpdate: $("#sidebar-update"),
  install: $("#install-button"),
  dialog: $("#game-dialog"),
  dialogImage: $("#dialog-image"),
  dialogBadge: $("#dialog-badge"),
  dialogTitle: $("#dialog-title"),
  dialogPublisher: $("#dialog-publisher"),
  dialogDescription: $("#dialog-description"),
  dialogMeta: $("#dialog-meta"),
  dialogLink: $("#dialog-link"),
  dialogLibrary: $("#dialog-library"),
  dialogFavorite: $("#dialog-favorite"),
  dialogAddList: $("#dialog-add-list"),
  dialogStatus: $("#dialog-status"),
  exportLibrary: $("#export-library"),
  importLibrary: $("#import-library"),
  importLibraryFile: $("#import-library-file"),
  toast: $("#toast"),
  statCatalog: $("#stat-catalog"),
  statLists: $("#stat-lists"),
  listsDashboard: $("#lists-dashboard"),
  listsGrid: $("#lists-grid"),
  createListButton: $("#create-list-button"),
  catalogMeta: $("#catalog-meta"),
  toolbar: $("#content-toolbar"),
  listDialog: $("#list-dialog"),
  listDialogTitle: $("#list-dialog-title"),
  listName: $("#list-name-input"),
  listDescription: $("#list-description-input"),
  listVisibility: $("#list-visibility-input"),
  saveList: $("#save-list-button"),
  listPicker: $("#list-picker-dialog"),
  listPickerItems: $("#list-picker-items"),
};

let installPrompt = null;
let countdownTimer = null;
let editingListId = null;

function loadJson(key, fallback) {
  try {
    const parsed = JSON.parse(localStorage.getItem(key) || "null");
    return parsed && typeof parsed === "object" ? parsed : fallback;
  } catch {
    return fallback;
  }
}

function loadLibrary() {
  const current = loadJson(LIBRARY_KEY, null);
  if (current) return current;
  for (const legacyKey of LEGACY_LIBRARY_KEYS) {
    const legacy = loadJson(legacyKey, null);
    if (legacy) {
      localStorage.setItem(LIBRARY_KEY, JSON.stringify(legacy));
      return legacy;
    }
  }
  return {};
}

function saveLibrary() {
  localStorage.setItem(LIBRARY_KEY, JSON.stringify(state.library));
  updateStats();
}

function saveLists() {
  localStorage.setItem(LISTS_KEY, JSON.stringify(state.lists));
  updateStats();
}

function showToast(message) {
  ui.toast.textContent = message;
  ui.toast.hidden = false;
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => { ui.toast.hidden = true; }, 3000);
}

function gameKey(game) {
  return game.internal_id || game.epic_id || game.promotion_key ||
    `epic:${game.namespace || "unknown"}:${game.external_id || game.title}`;
}

function snapshotGame(game) {
  return {
    internal_id: game.internal_id,
    store: game.store || "epic",
    external_id: game.external_id || game.epic_id,
    epic_id: game.epic_id,
    namespace: game.namespace,
    title: game.title,
    description: game.description,
    developer: game.developer,
    publisher: game.publisher,
    image_url: game.image_url,
    store_url: game.store_url,
    release_date: game.release_date,
    fmt_original_price: game.fmt_original_price,
    fmt_discount_price: game.fmt_discount_price,
    original_price: game.original_price,
    discount_price: game.discount_price,
    currency_code: game.currency_code,
    currency_decimals: game.currency_decimals,
    start_date: game.start_date,
    end_date: game.end_date,
    is_mystery_game: game.is_mystery_game,
    offer_type: game.offer_type,
    source_kind: game.source_kind,
  };
}

function getLibraryEntry(game) {
  return state.library[gameKey(game)] || null;
}

function setLibraryEntry(game, patch = {}) {
  const key = gameKey(game);
  const current = state.library[key] || {
    addedAt: new Date().toISOString(),
    status: "saved",
    favorite: false,
  };
  state.library[key] = { ...current, ...patch, game: snapshotGame(game) };
  saveLibrary();
}

function removeLibraryEntry(game) {
  delete state.library[gameKey(game)];
  saveLibrary();
}

function formatDate(value, withTime = false) {
  if (!value) return "Data non disponibile";
  return new Intl.DateTimeFormat("it-IT", withTime
    ? { dateStyle: "medium", timeStyle: "short" }
    : { dateStyle: "medium" }).format(new Date(value));
}

function priceText(game) {
  if (game.source_kind === "promotion") return game.fmt_original_price || "";
  return game.fmt_discount_price || game.fmt_original_price || "";
}

function getMode(game) {
  if (game.source_kind === "catalog") return "catalog";
  const now = Date.now();
  const start = new Date(game.start_date).getTime();
  const end = new Date(game.end_date).getTime();
  if (start && start > now) return "upcoming";
  if (end && end <= now) return "expired";
  return "current";
}

function countdownText(game) {
  const mode = getMode(game);
  if (mode === "catalog") return game.release_date ? formatDate(game.release_date) : "";
  const target = mode === "upcoming" ? game.start_date : game.end_date;
  const diff = new Date(target).getTime() - Date.now();
  if (diff <= 0) return mode === "upcoming" ? "Disponibile ora" : "Terminato";
  const mins = Math.floor(diff / 60000);
  const days = Math.floor(mins / 1440);
  const hours = Math.floor((mins % 1440) / 60);
  return `${mode === "upcoming" ? "Tra" : "Scade tra"} ${days ? `${days}g ` : ""}${hours}h`;
}

function normalizePromotion(game) {
  return { ...game, source_kind: "promotion", store: "epic" };
}

function normalizeCatalog(game) {
  return { ...game, source_kind: "catalog", store: "epic" };
}

function historyGames() {
  return state.history.map(normalizePromotion);
}

function libraryGames() {
  return Object.values(state.library)
    .filter((entry) => entry?.game)
    .map((entry) => ({ ...entry.game, libraryStatus: entry.status, favorite: entry.favorite }));
}

function allSearchText(game) {
  const entry = getLibraryEntry(game);
  return [
    game.title, game.description, game.publisher, game.developer,
    game.offer_type, entry?.status,
  ].filter(Boolean).join(" ").toLocaleLowerCase("it");
}

function gameMatchesSearch(game) {
  return !state.search || allSearchText(game).includes(state.search.toLocaleLowerCase("it"));
}

function matchesStatusFilter(game) {
  const entry = getLibraryEntry(game);
  if (state.statusFilter === "all") return true;
  if (state.statusFilter === "current" || state.statusFilter === "upcoming") {
    return getMode(game) === state.statusFilter;
  }
  if (state.statusFilter === "saved") return Boolean(entry);
  if (state.statusFilter === "favorite") return Boolean(entry?.favorite);
  return true;
}

function sortGames(games) {
  const sorted = [...games];
  if (state.sort === "title") sorted.sort((a, b) => a.title.localeCompare(b.title, "it"));
  if (state.sort === "date") sorted.sort((a, b) =>
    new Date(b.release_date || b.start_date || 0) - new Date(a.release_date || a.start_date || 0));
  if (state.sort === "value") sorted.sort((a, b) =>
    (b.original_price || 0) - (a.original_price || 0));
  return sorted;
}

function gamesForView() {
  let games = [];
  if (state.view === "home") games = [...state.current, ...state.upcoming].map(normalizePromotion);
  if (state.view === "current") games = state.current.map(normalizePromotion);
  if (state.view === "upcoming") games = state.upcoming.map(normalizePromotion);
  if (state.view === "history") games = historyGames();
  if (state.view === "catalog") games = state.catalog.map(normalizeCatalog);
  if (state.view === "library") games = libraryGames();
  if (state.view === "lists" && state.selectedListId) {
    const list = state.lists[state.selectedListId];
    games = (list?.games || []).map((key) => resolveGameByKey(key)).filter(Boolean);
  }
  return sortGames(games.filter(gameMatchesSearch).filter(matchesStatusFilter));
}

function resolveGameByKey(key) {
  const pools = [
    ...state.catalog.map(normalizeCatalog),
    ...state.current.map(normalizePromotion),
    ...state.upcoming.map(normalizePromotion),
    ...historyGames(),
    ...libraryGames(),
  ];
  return pools.find((game) => gameKey(game) === key) || state.library[key]?.game || null;
}

function updateStats() {
  $("#stat-current").textContent = state.current.length;
  ui.statCatalog.textContent = state.catalogMeta?.total ?? state.catalog.length;
  $("#stat-library").textContent = Object.keys(state.library).length;
  ui.statLists.textContent = Object.keys(state.lists).length;
}

function renderHero() {
  const game = state.current[0];
  ui.hero.hidden = state.view !== "home" || !game;
  if (!game) return;
  ui.heroImage.src = game.image_url || PLACEHOLDER;
  ui.heroTitle.textContent = game.title;
  ui.heroDescription.textContent = game.description || "";
  ui.heroPrice.textContent = game.fmt_original_price ? `${game.fmt_original_price} → GRATIS` : "GRATIS";
  ui.heroCountdown.textContent = countdownText(normalizePromotion(game));
  ui.heroLink.href = game.store_url;
  const inLibrary = Boolean(getLibraryEntry(game));
  ui.heroLibrary.textContent = inLibrary ? "Rimuovi dalla libreria" : "Aggiungi alla libreria";
  ui.heroLibrary.onclick = () => {
    if (getLibraryEntry(game)) removeLibraryEntry(game);
    else setLibraryEntry(game);
    render();
  };
}

function badgeText(game) {
  const mode = getMode(game);
  if (game.is_mystery_game) return "MYSTERY GAME";
  if (mode === "current") return "GRATIS ORA";
  if (mode === "upcoming") return "IN ARRIVO";
  if (mode === "expired") return "REGALO PASSATO";
  return "EPIC STORE";
}

function renderCard(game) {
  const fragment = ui.template.content.cloneNode(true);
  const card = fragment.querySelector(".game-card");
  const cover = fragment.querySelector(".card-cover");
  const image = fragment.querySelector(".game-image");
  const badge = fragment.querySelector(".game-badge");
  const publisher = fragment.querySelector(".publisher");
  const title = fragment.querySelector(".game-title");
  const description = fragment.querySelector(".game-description");
  const originalPrice = fragment.querySelector(".original-price");
  const freeLabel = fragment.querySelector(".free-label");
  const countdown = fragment.querySelector(".countdown");
  const progress = fragment.querySelector(".progress-track");
  const storeLink = fragment.querySelector(".store-link");
  const libraryButton = fragment.querySelector(".library-button");
  const favoriteButton = fragment.querySelector(".favorite-button");
  const favoriteIndicator = fragment.querySelector(".favorite-indicator");

  const entry = getLibraryEntry(game);
  image.src = game.image_url || PLACEHOLDER;
  image.alt = `Copertina di ${game.title}`;
  image.onerror = () => { image.src = PLACEHOLDER; };
  badge.textContent = badgeText(game);
  publisher.textContent = game.developer || game.publisher || "Epic Games Store";
  title.textContent = game.title;
  description.textContent = game.description || "Descrizione non disponibile.";
  originalPrice.textContent = priceText(game);
  freeLabel.textContent = game.source_kind === "promotion" ? "GRATIS" :
    (game.discount_price === 0 ? "FREE TO PLAY" : "EPIC");
  countdown.textContent = countdownText(game);
  progress.hidden = game.source_kind === "catalog";
  storeLink.href = game.store_url;
  libraryButton.textContent = entry ? "In libreria" : "Aggiungi";
  favoriteButton.textContent = entry?.favorite ? "♥" : "♡";
  favoriteIndicator.hidden = !entry?.favorite;
  card.classList.toggle("is-saved", Boolean(entry));

  cover.onclick = () => openGame(game);
  libraryButton.onclick = () => {
    if (entry) removeLibraryEntry(game); else setLibraryEntry(game);
    render();
  };
  favoriteButton.onclick = () => {
    setLibraryEntry(game, { favorite: !getLibraryEntry(game)?.favorite });
    render();
  };
  return fragment;
}

function renderGames() {
  const games = gamesForView();
  ui.grid.replaceChildren();
  if (!games.length) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.innerHTML = `<strong>Nessun gioco trovato</strong><span>Modifica ricerca o filtri.</span>`;
    ui.grid.append(empty);
    return;
  }
  const limit = state.view === "catalog" ? 300 : games.length;
  for (const game of games.slice(0, limit)) ui.grid.append(renderCard(game));
  if (games.length > limit) {
    const notice = document.createElement("div");
    notice.className = "catalog-limit-note";
    notice.textContent = `Mostrati i primi ${limit} risultati su ${games.length}. Usa la ricerca per restringere.`;
    ui.grid.append(notice);
  }
}

function renderViewHeader() {
  const labels = {
    home: ["THE FREE VAULT", "Scopri i giochi gratuiti"],
    current: ["FREE TRACKER", "Gratis adesso"],
    upcoming: ["FREE TRACKER", "In arrivo"],
    history: ["FREE TRACKER", "Cronologia dei regali"],
    catalog: ["DISCOVER", "Catalogo Epic Games Store"],
    library: ["PERSONALE", "La mia libreria"],
    lists: ["PERSONALE", state.selectedListId ? state.lists[state.selectedListId]?.name || "Lista" : "Le mie liste"],
  };
  [ui.eyebrow.textContent, ui.title.textContent] = labels[state.view] || labels.home;
  ui.listsDashboard.hidden = state.view !== "lists" || Boolean(state.selectedListId);
  ui.toolbar.hidden = state.view === "lists" && !state.selectedListId;
  ui.catalogMeta.hidden = state.view !== "catalog";
  if (state.view === "catalog") {
    const generated = state.catalogMeta?.generated_at;
    ui.catalogMeta.textContent = state.catalog.length
      ? `${state.catalog.length.toLocaleString("it-IT")} listing Epic · aggiornato ${formatDate(generated, true)}`
      : "Catalogo non ancora sincronizzato. Avvia il workflow “Sync Epic Catalog”.";
  }
}

function renderLists() {
  ui.listsGrid.replaceChildren();
  const lists = Object.values(state.lists).sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  if (!lists.length) {
    ui.listsGrid.innerHTML = `<div class="empty-state"><strong>Nessuna lista</strong><span>Crea raccolte ordinate come su Letterboxd.</span></div>`;
    return;
  }
  for (const list of lists) {
    const card = document.createElement("article");
    card.className = "list-card";
    const coverGames = (list.games || []).slice(0, 4).map(resolveGameByKey).filter(Boolean);
    card.innerHTML = `
      <button class="list-cover-stack" type="button" aria-label="Apri ${escapeHtml(list.name)}">
        ${[0,1,2,3].map((i) => `<img src="${escapeAttr(coverGames[i]?.image_url || PLACEHOLDER)}" alt="">`).join("")}
      </button>
      <div class="list-card-body">
        <span class="pill">${list.visibility === "public" ? "PUBBLICA" : "PRIVATA"}</span>
        <h3>${escapeHtml(list.name)}</h3>
        <p>${escapeHtml(list.description || "Nessuna descrizione.")}</p>
        <small>${(list.games || []).length} giochi</small>
        <div class="list-card-actions">
          <button class="button button-primary open-list" type="button">Apri</button>
          <button class="button button-secondary edit-list" type="button">Modifica</button>
          <button class="button button-secondary delete-list" type="button">Elimina</button>
        </div>
      </div>`;
    card.querySelector(".list-cover-stack").onclick = () => openList(list.id);
    card.querySelector(".open-list").onclick = () => openList(list.id);
    card.querySelector(".edit-list").onclick = () => openListEditor(list.id);
    card.querySelector(".delete-list").onclick = () => {
      if (confirm(`Eliminare la lista “${list.name}”?`)) {
        delete state.lists[list.id];
        saveLists();
        render();
      }
    };
    ui.listsGrid.append(card);
  }
}

function escapeHtml(value) {
  const div = document.createElement("div");
  div.textContent = value || "";
  return div.innerHTML;
}
function escapeAttr(value) { return escapeHtml(value).replaceAll('"', "&quot;"); }

function openGame(game) {
  state.selectedGame = game;
  const entry = getLibraryEntry(game);
  ui.dialogImage.src = game.image_url || PLACEHOLDER;
  ui.dialogBadge.textContent = badgeText(game);
  ui.dialogTitle.textContent = game.title;
  ui.dialogPublisher.textContent = [game.developer, game.publisher].filter(Boolean).join(" · ") || "Epic Games Store";
  ui.dialogDescription.textContent = game.description || "Descrizione non disponibile.";
  ui.dialogMeta.innerHTML = [
    game.release_date ? `<span>Uscita: ${formatDate(game.release_date)}</span>` : "",
    game.start_date ? `<span>Promo: ${formatDate(game.start_date)} – ${formatDate(game.end_date)}</span>` : "",
    priceText(game) ? `<span>Prezzo: ${escapeHtml(priceText(game))}</span>` : "",
  ].filter(Boolean).join("");
  ui.dialogLink.href = game.store_url;
  ui.dialogLibrary.textContent = entry ? "Rimuovi dalla libreria" : "Aggiungi alla libreria";
  ui.dialogFavorite.textContent = entry?.favorite ? "♥ Preferito" : "♡ Preferito";
  ui.dialogStatus.value = entry?.status || "saved";
  ui.dialogStatus.disabled = !entry;
  ui.dialog.showModal();
}

function openListEditor(id = null) {
  editingListId = id;
  const list = id ? state.lists[id] : null;
  ui.listDialogTitle.textContent = list ? "Modifica lista" : "Nuova lista";
  ui.listName.value = list?.name || "";
  ui.listDescription.value = list?.description || "";
  ui.listVisibility.value = list?.visibility || "private";
  ui.listDialog.showModal();
}

function saveListEditor() {
  const name = ui.listName.value.trim();
  if (!name) return showToast("Inserisci un titolo per la lista.");
  const id = editingListId || crypto.randomUUID();
  const previous = state.lists[id];
  state.lists[id] = {
    id,
    name,
    description: ui.listDescription.value.trim(),
    visibility: ui.listVisibility.value,
    games: previous?.games || [],
    createdAt: previous?.createdAt || new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
  saveLists();
  ui.listDialog.close();
  editingListId = null;
  render();
}

function openList(id) {
  state.selectedListId = id;
  state.view = "lists";
  setActiveNavigation("lists");
  render();
}

function openListPicker(game) {
  state.pendingListGame = game;
  ui.listPickerItems.replaceChildren();
  const lists = Object.values(state.lists);
  if (!lists.length) {
    ui.listPickerItems.innerHTML = `<div class="empty-state"><strong>Nessuna lista</strong><span>Creane una per iniziare.</span></div>`;
  }
  for (const list of lists) {
    const key = gameKey(game);
    const included = (list.games || []).includes(key);
    const button = document.createElement("button");
    button.className = "list-picker-button";
    button.innerHTML = `<span><strong>${escapeHtml(list.name)}</strong><small>${(list.games || []).length} giochi</small></span><span>${included ? "✓" : "+"}</span>`;
    button.onclick = () => {
      const games = new Set(list.games || []);
      if (games.has(key)) games.delete(key); else games.add(key);
      list.games = [...games];
      list.updatedAt = new Date().toISOString();
      saveLists();
      openListPicker(game);
    };
    ui.listPickerItems.append(button);
  }
  ui.listPicker.showModal();
}

function render() {
  renderHero();
  renderViewHeader();
  if (state.view === "lists" && !state.selectedListId) renderLists();
  else renderGames();
  updateStats();
  updateCountdowns();
}

function setActiveNavigation(view) {
  $$(".nav-item, .mobile-nav-item").forEach((button) =>
    button.classList.toggle("is-active", button.dataset.view === view));
}

function navigate(view) {
  state.view = view;
  if (view !== "lists") state.selectedListId = null;
  setActiveNavigation(view);
  document.body.classList.remove("sidebar-open");
  render();
}

function updateCountdowns() {
  $$(".countdown").forEach((node) => {
    const key = node.closest(".game-card")?.dataset?.gameKey;
    if (key) {
      const game = resolveGameByKey(key);
      if (game) node.textContent = countdownText(game);
    }
  });
}

async function loadData() {
  ui.refresh.disabled = true;
  ui.status.hidden = true;
  try {
    const [promotionsResponse, historyResponse, catalogResponse] = await Promise.all([
      fetch(`${DATA_URL}?v=${Date.now()}`, { cache: "no-store" }),
      fetch(`${HISTORY_URL}?v=${Date.now()}`, { cache: "no-store" }),
      fetch(`${CATALOG_URL}?v=${Date.now()}`, { cache: "no-store" }),
    ]);
    if (!promotionsResponse.ok) throw new Error(`Promotions HTTP ${promotionsResponse.status}`);
    const promotions = await promotionsResponse.json();
    const history = historyResponse.ok ? await historyResponse.json() : { games: [] };
    const catalog = catalogResponse.ok ? await catalogResponse.json() : { games: [], total: 0 };

    state.current = promotions.current || [];
    state.upcoming = promotions.upcoming || [];
    state.history = history.games || history.history || [];
    state.catalog = catalog.games || [];
    state.catalogMeta = catalog;
    ui.sidebarUpdate.textContent = promotions.generated_at
      ? `Aggiornato ${formatDate(promotions.generated_at, true)}`
      : "Dati caricati";
    render();
  } catch (error) {
    console.error(error);
    ui.status.hidden = false;
    ui.status.textContent = "Impossibile aggiornare tutti i dati. Il tracker può continuare a usare la cache disponibile.";
    render();
  } finally {
    ui.refresh.disabled = false;
  }
}

function exportData() {
  const payload = {
    app: "The Free Vault",
    schemaVersion: 3,
    exportedAt: new Date().toISOString(),
    library: state.library,
    lists: state.lists,
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `the-free-vault-backup-${new Date().toISOString().slice(0, 10)}.json`;
  link.click();
  URL.revokeObjectURL(url);
}

async function importData(file) {
  try {
    const payload = JSON.parse(await file.text());
    state.library = { ...state.library, ...(payload.library || {}) };
    state.lists = { ...state.lists, ...(payload.lists || {}) };
    saveLibrary();
    saveLists();
    render();
    showToast("Backup importato.");
  } catch (error) {
    console.error(error);
    showToast("File non valido.");
  }
}

$$("[data-view]").forEach((button) => button.addEventListener("click", () => navigate(button.dataset.view)));
ui.search.addEventListener("input", () => { state.search = ui.search.value.trim(); render(); });
ui.filter.addEventListener("change", () => { state.statusFilter = ui.filter.value; render(); });
ui.sort.addEventListener("change", () => { state.sort = ui.sort.value; render(); });
ui.refresh.addEventListener("click", loadData);
const menuButton = $("#menu-button");

if (menuButton) {
  menuButton.hidden = true;
}
$("#dialog-close").addEventListener("click", () => ui.dialog.close());
ui.dialogLibrary.addEventListener("click", () => {
  const game = state.selectedGame;
  if (getLibraryEntry(game)) removeLibraryEntry(game); else setLibraryEntry(game);
  openGame(game);
  render();
});
ui.dialogFavorite.addEventListener("click", () => {
  const game = state.selectedGame;
  setLibraryEntry(game, { favorite: !getLibraryEntry(game)?.favorite });
  openGame(game);
  render();
});
ui.dialogStatus.addEventListener("change", () => {
  setLibraryEntry(state.selectedGame, { status: ui.dialogStatus.value });
  render();
});
ui.dialogAddList.addEventListener("click", () => openListPicker(state.selectedGame));
ui.createListButton.addEventListener("click", () => openListEditor());
$("#list-dialog-close").addEventListener("click", () => ui.listDialog.close());
ui.saveList.addEventListener("click", saveListEditor);
$("#list-picker-close").addEventListener("click", () => ui.listPicker.close());
$("#picker-create-list").addEventListener("click", () => {
  ui.listPicker.close();
  openListEditor();
});
ui.exportLibrary.addEventListener("click", exportData);
ui.importLibrary.addEventListener("click", () => ui.importLibraryFile.click());
ui.importLibraryFile.addEventListener("change", () => importData(ui.importLibraryFile.files[0]));
window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault();
  installPrompt = event;
  ui.install.hidden = false;
});
ui.install.addEventListener("click", async () => {
  if (!installPrompt) return;
  await installPrompt.prompt();
  installPrompt = null;
  ui.install.hidden = true;
});
document.addEventListener("keydown", (event) => {
  if (event.key === "/" && document.activeElement.tagName !== "INPUT") {
    event.preventDefault();
    ui.search.focus();
  }
});
if ("serviceWorker" in navigator) navigator.serviceWorker.register("./service-worker.js").catch(console.error);

loadData();
countdownTimer = setInterval(updateCountdowns, 60000);
