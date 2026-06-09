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
  gameIndex: new Map(),
  library: loadLibrary(),
  lists: loadJson(LISTS_KEY, {}),
  route: { name: "home", params: {}, query: new URLSearchParams() },
  search: "",
  statusFilter: "all",
  sort: "relevance",
  pendingListGame: null,
  auth: { configured: false, user: null, profile: null },
  dataLoaded: false,
};

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];

const ui = {
  dashboardPage: $("#dashboard-page"),
  gamePage: $("#game-page"),
  authPage: $("#auth-page"),
  profilePage: $("#profile-page"),
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
  heroDetails: $("#hero-details"),
  sidebarUpdate: $("#sidebar-update"),
  sidebarDataNote: $("#sidebar-data-note"),
  install: $("#install-button"),
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
  accountButton: $("#account-button"),
  accountAvatar: $("#account-avatar"),
  accountLabel: $("#account-label"),
  authEyebrow: $("#auth-page-eyebrow"),
  authTitle: $("#auth-page-title"),
  authSubtitle: $("#auth-page-subtitle"),
  authConfigWarning: $("#auth-config-warning"),
  loginForm: $("#login-form"),
  loginEmail: $("#login-email"),
  loginPassword: $("#login-password"),
  loginError: $("#login-error"),
  loginSubmit: $("#login-submit"),
  registerForm: $("#register-form"),
  registerUsername: $("#register-username"),
  registerEmail: $("#register-email"),
  registerPassword: $("#register-password"),
  registerPasswordConfirm: $("#register-password-confirm"),
  registerError: $("#register-error"),
  registerSubmit: $("#register-submit"),
  authConfirmation: $("#auth-confirmation-message"),
  profileSignedOut: $("#profile-signed-out"),
  profileSignedIn: $("#profile-signed-in"),
  profilePageAvatar: $("#profile-page-avatar"),
  profilePageName: $("#profile-page-name"),
  profilePageHandle: $("#profile-page-handle"),
  profilePageBio: $("#profile-page-bio"),
  profilePageEmail: $("#profile-page-email"),
  profileForm: $("#profile-form"),
  profileUsername: $("#profile-username"),
  profileDisplayName: $("#profile-display-name"),
  profileBio: $("#profile-bio"),
  profileError: $("#profile-error"),
  profileRecentGames: $("#profile-recent-games"),
  cloudStatus: $("#cloud-status"),
  gamePageImage: $("#game-page-image"),
  gamePageBadge: $("#game-page-badge"),
  gamePageTitle: $("#game-page-title"),
  gamePageByline: $("#game-page-byline"),
  gamePageDescription: $("#game-page-description"),
  gamePageMeta: $("#game-page-meta"),
  gamePageStoreLink: $("#game-page-store-link"),
  gamePageLibrary: $("#game-page-library"),
  gamePageFavorite: $("#game-page-favorite"),
  gamePageList: $("#game-page-list"),
  gamePageStatus: $("#game-page-status"),
  gamePageRating: $("#game-page-rating"),
  gamePageNotes: $("#game-page-notes"),
  gamePageSaveNotes: $("#game-page-save-notes"),
  gamePagePromotions: $("#game-page-promotions"),
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
  window.VaultCloud?.schedulePush(state.library, state.lists);
}

function saveLists() {
  localStorage.setItem(LISTS_KEY, JSON.stringify(state.lists));
  updateStats();
  window.VaultCloud?.schedulePush(state.library, state.lists);
}

function showToast(message) {
  ui.toast.textContent = message;
  ui.toast.hidden = false;
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => { ui.toast.hidden = true; }, 3200);
}

function escapeHtml(value) {
  const div = document.createElement("div");
  div.textContent = value || "";
  return div.innerHTML;
}

function escapeAttr(value) {
  return escapeHtml(value).replaceAll('"', "&quot;");
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
    rating: 0,
    notes: "",
  };
  state.library[key] = {
    ...current,
    ...patch,
    updatedAt: new Date().toISOString(),
    game: snapshotGame(game),
  };
  saveLibrary();
  rebuildGameIndex();
  return state.library[key];
}

function removeLibraryEntry(game) {
  const key = gameKey(game);
  delete state.library[key];
  saveLibrary();
  rebuildGameIndex();
  window.VaultCloud?.deleteLibraryItem(key).catch(console.error);
}

function formatDate(value, withTime = false) {
  if (!value) return "Data non disponibile";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Data non disponibile";
  return new Intl.DateTimeFormat("it-IT", withTime
    ? { dateStyle: "medium", timeStyle: "short" }
    : { dateStyle: "medium" }).format(date);
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
    .map((entry) => ({
      ...entry.game,
      libraryStatus: entry.status,
      favorite: entry.favorite,
      rating: entry.rating,
      notes: entry.notes,
    }));
}

function rebuildGameIndex() {
  const next = new Map();
  const insert = (game) => {
    if (!game?.title) return;
    const key = gameKey(game);
    const previous = next.get(key);
    if (!previous || game.source_kind === "promotion") next.set(key, game);
  };
  state.catalog.map(normalizeCatalog).forEach(insert);
  historyGames().forEach(insert);
  state.upcoming.map(normalizePromotion).forEach(insert);
  state.current.map(normalizePromotion).forEach(insert);
  libraryGames().forEach((game) => {
    const key = gameKey(game);
    if (!next.has(key)) next.set(key, game);
  });
  state.gameIndex = next;
}

function resolveGameByKey(key) {
  return state.gameIndex.get(key) || state.library[key]?.game || null;
}

function gameRoute(game) {
  return `#/game/${encodeURIComponent(gameKey(game))}`;
}

function listRoute(id) {
  return `#/list/${encodeURIComponent(id)}`;
}

function parseRoute() {
  const rawHash = window.location.hash || "#/home";
  if (/^#(?:access_token|refresh_token|error|error_description)=/.test(rawHash)) {
    return { name: "auth-callback", params: {}, query: new URLSearchParams() };
  }
  const raw = rawHash.startsWith("#/") ? rawHash.slice(2) : rawHash.replace(/^#/, "");
  const [pathPart = "home", queryPart = ""] = raw.split("?");
  const segments = pathPart.split("/").filter(Boolean);
  const query = new URLSearchParams(queryPart);
  const first = segments[0] || "home";
  const simple = {
    home: "home",
    free: "current",
    current: "current",
    upcoming: "upcoming",
    history: "history",
    catalog: "catalog",
    library: "library",
    lists: "lists",
    profile: "profile",
    login: "login",
    register: "register",
  };
  if (first === "game" && segments[1]) {
    return { name: "game", params: { key: decodeURIComponent(segments.slice(1).join("/")) }, query };
  }
  if (first === "list" && segments[1]) {
    return { name: "list", params: { id: decodeURIComponent(segments[1]) }, query };
  }
  if (first === "auth" && segments[1] === "callback") {
    return { name: "auth-callback", params: {}, query };
  }
  return { name: simple[first] || "home", params: {}, query };
}

function routeToDashboardView(routeName) {
  return ["home", "current", "upcoming", "history", "catalog", "library", "lists", "list"].includes(routeName);
}

function setPageVisibility(page) {
  ui.dashboardPage.hidden = page !== "dashboard";
  ui.gamePage.hidden = page !== "game";
  ui.authPage.hidden = page !== "auth";
  ui.profilePage.hidden = page !== "profile";
}

function updateDocumentTitle(label) {
  document.title = label ? `${label} · The Free Vault` : "The Free Vault";
}

function setActiveNavigation(routeName) {
  const normalized = routeName === "list" ? "lists" : routeName;
  $$('[data-route]').forEach((node) => {
    node.classList.toggle("is-active", node.dataset.route === normalized);
  });
}

function navigate(hash) {
  if (window.location.hash === hash) {
    handleRoute();
  } else {
    window.location.hash = hash;
  }
}

function handleRoute() {
  state.route = parseRoute();
  setActiveNavigation(state.route.name);

  if (routeToDashboardView(state.route.name)) {
    setPageVisibility("dashboard");
    renderDashboard();
  } else if (state.route.name === "game") {
    setPageVisibility("game");
    renderGamePage();
  } else if (["login", "register", "auth-callback"].includes(state.route.name)) {
    setPageVisibility("auth");
    renderAuthPage();
  } else if (state.route.name === "profile") {
    setPageVisibility("profile");
    renderProfilePage();
  } else {
    navigate("#/home");
  }
  window.scrollTo({ top: 0, behavior: "auto" });
}

function allSearchText(game) {
  const entry = getLibraryEntry(game);
  return [
    game.title, game.description, game.publisher, game.developer,
    game.offer_type, entry?.status, entry?.notes,
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

function gamesForDashboard() {
  let games = [];
  const route = state.route.name;
  if (route === "home") games = [...state.current, ...state.upcoming].map(normalizePromotion);
  if (route === "current") games = state.current.map(normalizePromotion);
  if (route === "upcoming") games = state.upcoming.map(normalizePromotion);
  if (route === "history") games = historyGames();
  if (route === "catalog") games = state.catalog.map(normalizeCatalog);
  if (route === "library") games = libraryGames();
  if (route === "list") {
    const list = state.lists[state.route.params.id];
    games = (list?.games || []).map(resolveGameByKey).filter(Boolean);
  }
  return sortGames(games.filter(gameMatchesSearch).filter(matchesStatusFilter));
}

function updateStats() {
  $("#stat-current").textContent = state.current.length;
  ui.statCatalog.textContent = state.catalogMeta?.total ?? state.catalog.length;
  $("#stat-library").textContent = Object.keys(state.library).length;
  ui.statLists.textContent = Object.keys(state.lists).length;
}

function renderHero() {
  const game = state.current[0] ? normalizePromotion(state.current[0]) : null;
  ui.hero.hidden = state.route.name !== "home" || !game;
  if (!game) return;
  ui.heroImage.src = game.image_url || PLACEHOLDER;
  ui.heroImage.onerror = () => { ui.heroImage.src = PLACEHOLDER; };
  ui.heroTitle.textContent = game.title;
  ui.heroDescription.textContent = game.description || "";
  ui.heroPrice.textContent = game.fmt_original_price ? `${game.fmt_original_price} → GRATIS` : "GRATIS";
  ui.heroCountdown.textContent = countdownText(game);
  ui.heroLink.href = game.store_url;
  const inLibrary = Boolean(getLibraryEntry(game));
  ui.heroLibrary.textContent = inLibrary ? "Rimuovi dalla libreria" : "Aggiungi alla libreria";
  ui.heroLibrary.onclick = () => {
    if (getLibraryEntry(game)) removeLibraryEntry(game);
    else setLibraryEntry(game);
    renderDashboard();
  };
  ui.heroDetails.onclick = () => navigate(gameRoute(game));
}

function badgeText(game) {
  const mode = getMode(game);
  if (game.is_mystery_game) return "MYSTERY GAME";
  if (mode === "current") return "GRATIS ORA";
  if (mode === "upcoming") return "IN ARRIVO";
  if (mode === "expired") return "REGALO PASSATO";
  return "EPIC STORE";
}

function applyPriceToCard(game, originalPrice, priceLabel) {
  if (game.source_kind === "promotion") {
    originalPrice.hidden = !game.fmt_original_price;
    originalPrice.textContent = game.fmt_original_price || "";
    priceLabel.textContent = "GRATIS";
    return;
  }

  const originalValue = Number(game.original_price);
  const discountedValue = Number(game.discount_price);
  const hasOriginal = Number.isFinite(originalValue) && originalValue > 0;
  const hasDiscount = hasOriginal && Number.isFinite(discountedValue) && discountedValue >= 0 && discountedValue < originalValue;
  const isFreeToPlay = Number.isFinite(discountedValue) && discountedValue === 0 && originalValue === 0;

  if (hasDiscount) {
    originalPrice.hidden = false;
    originalPrice.textContent = game.fmt_original_price || "";
    priceLabel.textContent = game.fmt_discount_price || "In offerta";
  } else {
    originalPrice.hidden = true;
    originalPrice.textContent = "";
    if (isFreeToPlay) priceLabel.textContent = "FREE TO PLAY";
    else priceLabel.textContent = game.fmt_discount_price || game.fmt_original_price || "Vedi su Epic";
  }
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
  const priceLabel = fragment.querySelector(".free-label");
  const countdown = fragment.querySelector(".countdown");
  const progress = fragment.querySelector(".progress-track");
  const storeLink = fragment.querySelector(".store-link");
  const libraryButton = fragment.querySelector(".library-button");
  const favoriteButton = fragment.querySelector(".favorite-button");
  const favoriteIndicator = fragment.querySelector(".favorite-indicator");

  const entry = getLibraryEntry(game);
  card.dataset.gameKey = gameKey(game);
  image.src = game.image_url || PLACEHOLDER;
  image.alt = `Copertina di ${game.title}`;
  image.onerror = () => { image.src = PLACEHOLDER; };
  badge.textContent = badgeText(game);
  publisher.textContent = game.developer || game.publisher || "Epic Games Store";
  title.textContent = game.title;
  description.textContent = game.description || "Descrizione non disponibile.";
  applyPriceToCard(game, originalPrice, priceLabel);
  countdown.textContent = countdownText(game);
  progress.hidden = game.source_kind === "catalog";
  storeLink.href = game.store_url;
  libraryButton.textContent = entry ? "In libreria" : "Aggiungi";
  favoriteButton.textContent = entry?.favorite ? "♥" : "♡";
  favoriteIndicator.hidden = !entry?.favorite;
  card.classList.toggle("is-saved", Boolean(entry));
  card.classList.toggle("is-favorite", Boolean(entry?.favorite));

  cover.onclick = () => navigate(gameRoute(game));
  libraryButton.onclick = () => {
    if (entry) removeLibraryEntry(game); else setLibraryEntry(game);
    renderDashboard();
  };
  favoriteButton.onclick = () => {
    setLibraryEntry(game, { favorite: !getLibraryEntry(game)?.favorite });
    renderDashboard();
  };
  return fragment;
}

function renderGames() {
  const games = gamesForDashboard();
  ui.grid.replaceChildren();
  if (!games.length) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.innerHTML = `<strong>Nessun gioco trovato</strong><span>Modifica ricerca o filtri.</span>`;
    ui.grid.append(empty);
    return;
  }
  const limit = state.route.name === "catalog" ? 300 : games.length;
  for (const game of games.slice(0, limit)) ui.grid.append(renderCard(game));
  if (games.length > limit) {
    const notice = document.createElement("div");
    notice.className = "catalog-limit-note";
    notice.textContent = `Mostrati i primi ${limit} risultati su ${games.length}. Usa la ricerca per restringere.`;
    ui.grid.append(notice);
  }
}

function renderDashboardHeader() {
  const labels = {
    home: ["THE FREE VAULT", "Scopri i giochi gratuiti"],
    current: ["FREE TRACKER", "Gratis adesso"],
    upcoming: ["FREE TRACKER", "In arrivo"],
    history: ["FREE TRACKER", "Cronologia dei regali"],
    catalog: ["DISCOVER", "Catalogo Epic Games Store"],
    library: ["PERSONALE", "La mia libreria"],
    lists: ["PERSONALE", "Le mie liste"],
    list: ["LISTA PERSONALE", state.lists[state.route.params.id]?.name || "Lista"],
  };
  const [eyebrow, title] = labels[state.route.name] || labels.home;
  ui.eyebrow.textContent = eyebrow;
  ui.title.textContent = title;
  updateDocumentTitle(title);
  ui.listsDashboard.hidden = state.route.name !== "lists";
  ui.toolbar.hidden = state.route.name === "lists";
  ui.catalogMeta.hidden = state.route.name !== "catalog";
  if (state.route.name === "catalog") {
    const generated = state.catalogMeta?.generated_at;
    ui.catalogMeta.textContent = state.catalog.length
      ? `${state.catalog.length.toLocaleString("it-IT")} listing Epic · aggiornato ${formatDate(generated, true)}`
      : "Catalogo non ancora sincronizzato. Avvia il workflow “Sync Epic Catalog”.";
  }
}

function renderListsOverview() {
  ui.listsGrid.replaceChildren();
  const lists = Object.values(state.lists).sort((a, b) => (b.updatedAt || "").localeCompare(a.updatedAt || ""));
  if (!lists.length) {
    ui.listsGrid.innerHTML = `<div class="empty-state"><strong>Nessuna lista</strong><span>Crea raccolte ordinate come su Letterboxd.</span></div>`;
    return;
  }
  for (const list of lists) {
    const card = document.createElement("article");
    card.className = "list-card";
    const coverGames = (list.games || []).slice(0, 4).map(resolveGameByKey).filter(Boolean);
    card.innerHTML = `
      <button class="list-cover-stack" type="button" aria-label="Apri ${escapeAttr(list.name)}">
        ${[0, 1, 2, 3].map((i) => `<img src="${escapeAttr(coverGames[i]?.image_url || PLACEHOLDER)}" alt="">`).join("")}
      </button>
      <div class="list-card-body">
        <span class="pill">${list.visibility === "public" ? "PUBBLICA" : "PRIVATA"}</span>
        <h3>${escapeHtml(list.name)}</h3>
        <p>${escapeHtml(list.description || "Nessuna descrizione.")}</p>
        <small>${(list.games || []).length} giochi</small>
        <div class="list-card-actions">
          <a class="button button-primary" href="${listRoute(list.id)}">Apri</a>
          <button class="button button-secondary edit-list" type="button">Modifica</button>
          <button class="button button-secondary delete-list" type="button">Elimina</button>
        </div>
      </div>`;
    card.querySelector(".list-cover-stack").onclick = () => navigate(listRoute(list.id));
    card.querySelector(".edit-list").onclick = () => openListEditor(list.id);
    card.querySelector(".delete-list").onclick = async () => {
      if (!confirm(`Eliminare la lista “${list.name}”?`)) return;
      delete state.lists[list.id];
      saveLists();
      await window.VaultCloud?.deleteList(list.id).catch(console.error);
      renderDashboard();
    };
    ui.listsGrid.append(card);
  }
}

function renderDashboard() {
  renderHero();
  renderDashboardHeader();
  ui.grid.hidden = state.route.name === "lists";
  if (state.route.name === "lists") renderListsOverview();
  else renderGames();
  updateStats();
  updateCountdowns();
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
  const games = new Set(previous?.games || []);
  if (!editingListId && state.pendingListGame) games.add(gameKey(state.pendingListGame));
  state.lists[id] = {
    id,
    name,
    description: ui.listDescription.value.trim(),
    visibility: ui.listVisibility.value,
    games: [...games],
    createdAt: previous?.createdAt || new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
  saveLists();
  ui.listDialog.close();
  editingListId = null;
  state.pendingListGame = null;
  if (state.route.name === "lists") renderDashboard();
  else showToast("Lista salvata.");
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

function matchingPromotions(game) {
  const targetIds = new Set([game.epic_id, game.external_id].filter(Boolean));
  const normalizedTitle = (game.title || "").trim().toLocaleLowerCase("it");
  return [...state.current, ...state.upcoming, ...state.history]
    .map(normalizePromotion)
    .filter((promo) => {
      const idsMatch = [promo.epic_id, promo.external_id].some((id) => id && targetIds.has(id));
      const namespaceMatch = game.namespace && promo.namespace === game.namespace;
      const titleMatch = normalizedTitle && (promo.title || "").trim().toLocaleLowerCase("it") === normalizedTitle;
      return idsMatch || (namespaceMatch && titleMatch) || titleMatch;
    })
    .sort((a, b) => new Date(b.start_date || 0) - new Date(a.start_date || 0));
}

function renderRating(game, entry) {
  ui.gamePageRating.replaceChildren();
  const selected = Number(entry?.rating || 0);
  for (let rating = 1; rating <= 5; rating += 1) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "rating-button";
    button.textContent = rating <= selected ? "★" : "☆";
    button.setAttribute("aria-label", `${rating} stelle`);
    button.onclick = () => {
      setLibraryEntry(game, { rating: selected === rating ? 0 : rating });
      renderGamePage();
    };
    ui.gamePageRating.append(button);
  }
}

function renderPromotionTimeline(game) {
  const promotions = matchingPromotions(game);
  ui.gamePagePromotions.replaceChildren();
  if (!promotions.length) {
    ui.gamePagePromotions.innerHTML = `<div class="timeline-empty">Nessuna promozione gratuita registrata per questo titolo.</div>`;
    return;
  }
  for (const promo of promotions) {
    const item = document.createElement("article");
    const mode = getMode(promo);
    item.className = `promotion-event promotion-event-${mode}`;
    item.innerHTML = `
      <span class="timeline-dot"></span>
      <div>
        <strong>${escapeHtml(badgeText(promo))}</strong>
        <span>${formatDate(promo.start_date)} → ${formatDate(promo.end_date)}</span>
        <small>${escapeHtml(promo.fmt_original_price || "Prezzo non disponibile")}</small>
      </div>`;
    ui.gamePagePromotions.append(item);
  }
}

function renderGamePage() {
  const game = resolveGameByKey(state.route.params.key);
  if (!game) {
    updateDocumentTitle("Gioco non trovato");
    ui.gamePageTitle.textContent = state.dataLoaded ? "Gioco non trovato" : "Caricamento…";
    ui.gamePageDescription.textContent = state.dataLoaded
      ? "Il titolo richiesto non è presente nel catalogo locale."
      : "Sto caricando il catalogo.";
    ui.gamePageImage.src = PLACEHOLDER;
    ui.gamePageMeta.replaceChildren();
    ui.gamePagePromotions.replaceChildren();
    return;
  }

  const entry = getLibraryEntry(game);
  updateDocumentTitle(game.title);
  ui.gamePageImage.src = game.image_url || PLACEHOLDER;
  ui.gamePageImage.alt = `Immagine di ${game.title}`;
  ui.gamePageImage.onerror = () => { ui.gamePageImage.src = PLACEHOLDER; };
  ui.gamePageBadge.textContent = badgeText(game);
  ui.gamePageTitle.textContent = game.title;
  ui.gamePageByline.textContent = [game.developer, game.publisher].filter(Boolean).join(" · ") || "Epic Games Store";
  ui.gamePageDescription.textContent = game.description || "Descrizione non disponibile.";
  ui.gamePageMeta.innerHTML = [
    game.release_date ? `<span><small>USCITA</small>${escapeHtml(formatDate(game.release_date))}</span>` : "",
    priceText(game) ? `<span><small>PREZZO</small>${escapeHtml(priceText(game))}</span>` : "",
    game.offer_type ? `<span><small>TIPO</small>${escapeHtml(game.offer_type)}</span>` : "",
    `<span><small>STORE</small>Epic Games Store</span>`,
  ].filter(Boolean).join("");
  ui.gamePageStoreLink.href = game.store_url;
  ui.gamePageLibrary.textContent = entry ? "Rimuovi dalla libreria" : "Aggiungi alla libreria";
  ui.gamePageFavorite.textContent = entry?.favorite ? "♥ Preferito" : "♡ Preferito";
  ui.gamePageStatus.value = entry?.status || "saved";
  ui.gamePageStatus.disabled = !entry;
  ui.gamePageNotes.value = entry?.notes || "";
  renderRating(game, entry);
  renderPromotionTimeline(game);

  ui.gamePageLibrary.onclick = () => {
    if (getLibraryEntry(game)) removeLibraryEntry(game);
    else setLibraryEntry(game);
    renderGamePage();
  };
  ui.gamePageFavorite.onclick = () => {
    setLibraryEntry(game, { favorite: !getLibraryEntry(game)?.favorite });
    renderGamePage();
  };
  ui.gamePageList.onclick = () => openListPicker(game);
  ui.gamePageStatus.onchange = () => {
    setLibraryEntry(game, { status: ui.gamePageStatus.value });
    renderGamePage();
  };
  ui.gamePageSaveNotes.onclick = () => {
    setLibraryEntry(game, { notes: ui.gamePageNotes.value.trim() });
    showToast("Diario aggiornato.");
    renderGamePage();
  };
}

function initialsForAccount(user, profile) {
  const source = profile?.display_name || profile?.username || user?.email || "?";
  return source.trim().slice(0, 2).toUpperCase();
}

function updateAccountUI(snapshot) {
  state.auth = snapshot;
  if (!snapshot.configured) {
    ui.accountLabel.textContent = "Configura account";
    ui.accountAvatar.textContent = "!";
    ui.sidebarDataNote.textContent = "Account cloud non configurato.";
    return;
  }
  if (!snapshot.user) {
    ui.accountLabel.textContent = "Accedi";
    ui.accountAvatar.textContent = "?";
    ui.sidebarDataNote.textContent = "I dati personali sono salvati localmente.";
    return;
  }
  ui.accountLabel.textContent = snapshot.profile?.display_name || snapshot.profile?.username || "Profilo";
  ui.accountAvatar.textContent = initialsForAccount(snapshot.user, snapshot.profile);
  ui.sidebarDataNote.textContent = "Libreria e liste sincronizzate con il tuo account.";
}

function renderAuthPage() {
  const mode = state.route.name;
  const isRegister = mode === "register";
  const isCallback = mode === "auth-callback" || state.route.query.get("confirmed") === "1";
  updateDocumentTitle(isRegister ? "Registrati" : "Accedi");
  ui.authConfigWarning.hidden = Boolean(window.VaultAuth?.configured);
  ui.loginForm.hidden = isRegister || isCallback;
  ui.registerForm.hidden = !isRegister || isCallback;
  ui.authConfirmation.hidden = !isCallback;
  ui.authEyebrow.textContent = isCallback ? "EMAIL CONFERMATA" : "THE FREE VAULT ACCOUNT";
  ui.authTitle.textContent = isCallback ? "Account attivato" : isRegister ? "Crea il tuo account" : "Bentornato";
  ui.authSubtitle.textContent = isCallback
    ? "La conferma è andata a buon fine."
    : isRegister
      ? "Servono solo username, email e password. Il resto si completa dal profilo."
      : "Accedi con email e password per sincronizzare il tuo Vault.";

  if (state.auth.user && !isCallback) {
    navigate("#/profile");
    return;
  }
  if (state.route.query.get("registered") === "1") {
    ui.authSubtitle.textContent = "Registrazione inviata. Controlla la posta e conferma l’indirizzo email, poi accedi.";
  }
}

function profileStats() {
  const entries = Object.values(state.library);
  return {
    library: entries.length,
    completed: entries.filter((entry) => entry.status === "completed").length,
    favorites: entries.filter((entry) => entry.favorite).length,
    lists: Object.keys(state.lists).length,
  };
}

function renderProfileRecentGames() {
  ui.profileRecentGames.replaceChildren();
  const entries = Object.values(state.library)
    .filter((entry) => entry?.game)
    .sort((a, b) => new Date(b.addedAt || b.updatedAt || 0) - new Date(a.addedAt || a.updatedAt || 0))
    .slice(0, 5);
  if (!entries.length) {
    ui.profileRecentGames.innerHTML = `<div class="timeline-empty">La libreria è ancora vuota.</div>`;
    return;
  }
  for (const entry of entries) {
    const game = entry.game;
    const link = document.createElement("a");
    link.className = "profile-game-row";
    link.href = gameRoute(game);
    link.innerHTML = `
      <img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt="">
      <span><strong>${escapeHtml(game.title)}</strong><small>${escapeHtml(entry.status || "In libreria")}</small></span>
      <span>→</span>`;
    ui.profileRecentGames.append(link);
  }
}

function renderProfilePage() {
  const { user, profile, configured } = state.auth;
  updateDocumentTitle("Profilo");
  ui.profileSignedOut.hidden = Boolean(user);
  ui.profileSignedIn.hidden = !user;
  if (!user) {
    if (!configured) ui.profileSignedOut.querySelector("p:last-of-type").textContent = "Configura Supabase per abilitare gli account cloud.";
    return;
  }

  const displayName = profile?.display_name || profile?.username || "Profilo";
  ui.profilePageAvatar.textContent = initialsForAccount(user, profile);
  ui.profilePageName.textContent = displayName;
  ui.profilePageHandle.textContent = profile?.username ? `@${profile.username}` : "";
  ui.profilePageBio.textContent = profile?.bio || "Nessuna bio inserita.";
  ui.profilePageEmail.textContent = user.email || "";
  ui.profileUsername.value = profile?.username || "";
  ui.profileDisplayName.value = profile?.display_name || profile?.username || "";
  ui.profileBio.value = profile?.bio || "";

  const stats = profileStats();
  $("#profile-stat-library").textContent = stats.library;
  $("#profile-stat-completed").textContent = stats.completed;
  $("#profile-stat-favorites").textContent = stats.favorites;
  $("#profile-stat-lists").textContent = stats.lists;
  renderProfileRecentGames();
}

async function synchronizeSignedInUser(snapshot) {
  updateAccountUI(snapshot);
  if (!snapshot.user) {
    if (state.route.name === "profile") renderProfilePage();
    return;
  }
  ui.cloudStatus.textContent = "Sincronizzazione…";
  try {
    const merged = await window.VaultCloud.pull(state.library, state.lists);
    state.library = merged.library;
    state.lists = merged.lists;
    localStorage.setItem(LIBRARY_KEY, JSON.stringify(state.library));
    localStorage.setItem(LISTS_KEY, JSON.stringify(state.lists));
    await window.VaultCloud.push(state.library, state.lists);
    rebuildGameIndex();
    ui.cloudStatus.textContent = "Sincronizzato";
    if (state.route.name === "profile") renderProfilePage();
    if (routeToDashboardView(state.route.name)) renderDashboard();
  } catch (error) {
    console.error(error);
    ui.cloudStatus.textContent = "Errore di sincronizzazione";
    showToast("Accesso riuscito, ma la sincronizzazione cloud è fallita.");
  }
}

async function initializeUserSystem() {
  if (!window.VaultAuth) return;
  window.VaultAuth.subscribe((snapshot) => {
    synchronizeSignedInUser(snapshot);
  });
  try {
    const result = await window.VaultAuth.initialize();
    if (result?.returnedFromConfirmation && result.session) {
      showToast("Email confermata correttamente.");
      handleRoute();
    }
  } catch (error) {
    console.error("Inizializzazione account fallita", error);
    showToast("Servizio account temporaneamente non disponibile.");
  }
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
    state.dataLoaded = true;
    rebuildGameIndex();
    ui.sidebarUpdate.textContent = promotions.generated_at
      ? `Aggiornato ${formatDate(promotions.generated_at, true)}`
      : "Dati caricati";
    handleRoute();
  } catch (error) {
    console.error(error);
    state.dataLoaded = true;
    ui.status.hidden = false;
    ui.status.textContent = "Impossibile aggiornare tutti i dati. Il tracker può continuare a usare la cache disponibile.";
    handleRoute();
  } finally {
    ui.refresh.disabled = false;
  }
}

function updateCountdowns() {
  $$(".countdown").forEach((node) => {
    const key = node.closest(".game-card")?.dataset?.gameKey;
    const game = key ? resolveGameByKey(key) : null;
    if (game) node.textContent = countdownText(game);
  });
  if (!ui.hero.hidden && state.current[0]) ui.heroCountdown.textContent = countdownText(normalizePromotion(state.current[0]));
}

function exportData() {
  const payload = {
    app: "The Free Vault",
    schemaVersion: 4,
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
  if (!file) return;
  try {
    const payload = JSON.parse(await file.text());
    state.library = { ...state.library, ...(payload.library || {}) };
    state.lists = { ...state.lists, ...(payload.lists || {}) };
    saveLibrary();
    saveLists();
    rebuildGameIndex();
    handleRoute();
    showToast("Backup importato.");
  } catch (error) {
    console.error(error);
    showToast("File non valido.");
  } finally {
    ui.importLibraryFile.value = "";
  }
}

ui.search.addEventListener("input", () => {
  state.search = ui.search.value.trim();
  if (!routeToDashboardView(state.route.name) || state.route.name === "lists") navigate("#/catalog");
  else renderDashboard();
});
ui.filter.addEventListener("change", () => { state.statusFilter = ui.filter.value; renderDashboard(); });
ui.sort.addEventListener("change", () => { state.sort = ui.sort.value; renderDashboard(); });
ui.refresh.addEventListener("click", loadData);
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
ui.accountButton.addEventListener("click", () => navigate(state.auth.user ? "#/profile" : "#/login"));

ui.loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  ui.loginError.hidden = true;
  ui.loginSubmit.disabled = true;
  try {
    await window.VaultAuth.signIn({
      email: ui.loginEmail.value.trim(),
      password: ui.loginPassword.value,
    });
    ui.loginForm.reset();
    navigate("#/profile");
  } catch (error) {
    ui.loginError.textContent = error.message || "Accesso fallito.";
    ui.loginError.hidden = false;
  } finally {
    ui.loginSubmit.disabled = false;
  }
});

ui.registerForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  ui.registerError.hidden = true;
  ui.registerSubmit.disabled = true;
  try {
    const username = ui.registerUsername.value.trim();
    if (!/^[a-zA-Z0-9_]{3,30}$/.test(username)) {
      throw new Error("Username: 3–30 caratteri, solo lettere, numeri e underscore.");
    }
    if (ui.registerPassword.value !== ui.registerPasswordConfirm.value) {
      throw new Error("Le password non coincidono.");
    }
    const result = await window.VaultAuth.signUp({
      email: ui.registerEmail.value.trim(),
      password: ui.registerPassword.value,
      username,
    });
    ui.registerForm.reset();
    if (result.session) navigate("#/profile");
    else navigate("#/login?registered=1");
  } catch (error) {
    ui.registerError.textContent = error.message || "Registrazione fallita.";
    ui.registerError.hidden = false;
  } finally {
    ui.registerSubmit.disabled = false;
  }
});

ui.profileForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  ui.profileError.hidden = true;
  try {
    await window.VaultAuth.updateProfile({
      username: ui.profileUsername.value,
      display_name: ui.profileDisplayName.value,
      bio: ui.profileBio.value,
    });
    showToast("Profilo aggiornato.");
    renderProfilePage();
  } catch (error) {
    ui.profileError.textContent = error.message || "Aggiornamento fallito.";
    ui.profileError.hidden = false;
  }
});

$("#logout-button").addEventListener("click", async () => {
  try {
    await window.VaultAuth.signOut();
    showToast("Disconnessione completata.");
    navigate("#/home");
  } catch (error) {
    showToast(error.message || "Disconnessione fallita.");
  }
});

$$('[data-back]').forEach((button) => button.addEventListener("click", () => {
  if (window.history.length > 1) window.history.back();
  else navigate("#/home");
}));

window.addEventListener("hashchange", handleRoute);
window.addEventListener("tfv:auth-return", handleRoute);
window.addEventListener("tfv:sync-error", () => {
  if (ui.cloudStatus) ui.cloudStatus.textContent = "Errore di sincronizzazione";
});
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
  if (event.key === "/" && !["INPUT", "TEXTAREA"].includes(document.activeElement.tagName)) {
    event.preventDefault();
    ui.search.focus();
  }
});

if (!window.location.hash) window.history.replaceState({}, "", "#/home");
if ("serviceWorker" in navigator) navigator.serviceWorker.register("./service-worker.js").catch(console.error);

handleRoute();
loadData();
initializeUserSystem();
countdownTimer = setInterval(updateCountdowns, 60000);
