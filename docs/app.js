const DATA_URL = "./games.json";
const HISTORY_URL = "./history.json";
const PLACEHOLDER = "./placeholders/game-placeholder.svg";

const state = {
  current: [],
  upcoming: [],
  history: [],
  library: {},
  view: "home",
  search: "",
  statusFilter: "all",
  sort: "relevance",
  selectedGame: null,
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
  dialogStatus: $("#dialog-status"),
  dialogRating: $("#dialog-rating"),
  dialogNotes: $("#dialog-notes"),
  dialogSaveStatus: $("#dialog-save-status"),
  exportLibrary: $("#export-library"),
  importLibrary: $("#import-library"),
  importLibraryFile: $("#import-library-file"),
  toast: $("#toast"),
};

let installPrompt = null;
let countdownTimer = null;

async function loadLibrary() {
  state.library = await VaultDB.loadLibrary();
}

function saveLibrary() {
  VaultDB.saveLibrary(state.library).catch((error) => {
    console.error("Salvataggio libreria fallito", error);
    showToast("Impossibile salvare la libreria.");
  });
  updateStats();
}

function showToast(message) {
  ui.toast.textContent = message;
  ui.toast.hidden = false;
  window.clearTimeout(showToast.timer);
  showToast.timer = window.setTimeout(() => { ui.toast.hidden = true; }, 3200);
}

function exportLibrary() {
  const payload = {
    app: "The Free Vault",
    version: 2,
    exportedAt: new Date().toISOString(),
    library: state.library,
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `the-free-vault-library-${new Date().toISOString().slice(0, 10)}.json`;
  document.body.append(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
  showToast("Libreria esportata.");
}

async function importLibraryFile(file) {
  if (!file) return;
  try {
    const payload = JSON.parse(await file.text());
    const imported = payload?.library ?? payload;
    if (!imported || typeof imported !== "object" || Array.isArray(imported)) {
      throw new Error("Formato non valido");
    }
    state.library = { ...state.library, ...imported };
    saveLibrary();
    render();
    showToast("Libreria importata e unita a quella corrente.");
  } catch (error) {
    console.error(error);
    showToast("Impossibile importare il file selezionato.");
  } finally {
    ui.importLibraryFile.value = "";
  }
}

function gameKey(game) {
  return game.epic_id || game.promotion_key || `${game.title}|${game.start_date}`;
}

function getLibraryEntry(game) {
  return state.library[gameKey(game)] || null;
}

function setLibraryEntry(game, patch) {
  const key = gameKey(game);
  const current = state.library[key] || {
    addedAt: new Date().toISOString(),
    status: "saved",
    favorite: false,
    rating: 0,
    notes: "",
    game: snapshotGame(game),
  };
  state.library[key] = { ...current, ...patch, game: snapshotGame(game) };
  saveLibrary();
}

function removeLibraryEntry(game) {
  delete state.library[gameKey(game)];
  saveLibrary();
}

function snapshotGame(game) {
  return {
    epic_id: game.epic_id,
    title: game.title,
    description: game.description,
    publisher: game.publisher,
    image_url: game.image_url,
    store_url: game.store_url,
    fmt_original_price: game.fmt_original_price,
    original_price: game.original_price,
    currency_decimals: game.currency_decimals,
    start_date: game.start_date,
    end_date: game.end_date,
    is_mystery_game: game.is_mystery_game,
    offer_type: game.offer_type,
  };
}

function formatDate(value) {
  if (!value) return "Data non disponibile";
  return new Intl.DateTimeFormat("it-IT", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

function formatCurrencyValue(game) {
  if (game.fmt_original_price) return game.fmt_original_price;
  if (!Number.isFinite(game.original_price)) return "";
  const decimals = Number.isFinite(game.currency_decimals) ? game.currency_decimals : 2;
  const value = game.original_price / (10 ** decimals);
  try {
    return new Intl.NumberFormat("it-IT", {
      style: "currency",
      currency: game.currency_code || "EUR",
    }).format(value);
  } catch {
    return `${value.toFixed(decimals)} ${game.currency_code || ""}`.trim();
  }
}

function countdownText(game) {
  const upcoming = getMode(game) === "upcoming";
  const target = upcoming ? game.start_date : game.end_date;
  const diff = new Date(target).getTime() - Date.now();
  if (diff <= 0) return upcoming ? "Disponibile ora" : "Promozione terminata";
  const minutes = Math.floor(diff / 60000);
  const days = Math.floor(minutes / 1440);
  const hours = Math.floor((minutes % 1440) / 60);
  const mins = minutes % 60;
  const prefix = upcoming ? "Tra" : "Scade tra";
  return days > 0 ? `${prefix} ${days}g ${hours}h` : `${prefix} ${hours}h ${mins}m`;
}

function promotionProgress(game) {
  const start = new Date(game.start_date).getTime();
  const end = new Date(game.end_date).getTime();
  const now = Date.now();
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) return 0;
  if (now <= start) return 0;
  if (now >= end) return 100;
  return ((now - start) / (end - start)) * 100;
}

function getMode(game) {
  if (game.is_current || game.promotion_type === "current") return "current";
  if (game.is_upcoming || game.promotion_type === "upcoming") return "upcoming";
  const now = Date.now();
  if (new Date(game.start_date).getTime() > now) return "upcoming";
  return new Date(game.end_date).getTime() > now ? "current" : "history";
}

function allKnownGames() {
  const indexed = new Map();
  [...state.history, ...state.upcoming, ...state.current].forEach((game) => {
    indexed.set(game.promotion_key || `${gameKey(game)}|${game.start_date}|${game.end_date}`, game);
  });
  return [...indexed.values()];
}

function libraryGames() {
  return Object.values(state.library)
    .filter((entry) => entry?.game)
    .map((entry) => ({
      ...entry.game,
      libraryStatus: entry.status,
      favorite: entry.favorite,
      personalRating: entry.rating || 0,
      personalNotes: entry.notes || "",
    }));
}

function gameMatchesSearch(game) {
  if (!state.search) return true;
  const entry = getLibraryEntry(game);
  const haystack = [
    game.title,
    game.publisher,
    game.description,
    game.offer_type,
    entry?.notes,
    entry?.status,
  ]
    .filter(Boolean)
    .join(" ")
    .toLocaleLowerCase("it");
  return haystack.includes(state.search.toLocaleLowerCase("it"));
}

function matchesStatusFilter(game) {
  const entry = getLibraryEntry(game);
  if (state.statusFilter === "all") return true;
  if (state.statusFilter === "current" || state.statusFilter === "upcoming") {
    return getMode(game) === state.statusFilter;
  }
  if (state.statusFilter === "saved") return Boolean(entry);
  if (state.statusFilter === "favorite") return Boolean(entry?.favorite);
  if (["backlog", "playing", "completed", "abandoned"].includes(state.statusFilter)) {
    return entry?.status === state.statusFilter;
  }
  return true;
}

function gamesForView() {
  let games;
  switch (state.view) {
    case "current": games = [...state.current]; break;
    case "upcoming": games = [...state.upcoming]; break;
    case "history": games = allKnownGames(); break;
    case "library": games = libraryGames(); break;
    default: games = [...state.current, ...state.upcoming];
  }

  games = games.filter(gameMatchesSearch).filter(matchesStatusFilter);

  games.sort((a, b) => {
    if (state.sort === "title") return String(a.title).localeCompare(String(b.title), "it");
    if (state.sort === "date") {
      const dateA = new Date(getMode(a) === "upcoming" ? a.start_date : a.end_date).getTime();
      const dateB = new Date(getMode(b) === "upcoming" ? b.start_date : b.end_date).getTime();
      return dateA - dateB;
    }
    if (state.sort === "value") return (b.original_price || 0) - (a.original_price || 0);
    const score = (game) => (getMode(game) === "current" ? 0 : getMode(game) === "upcoming" ? 1 : 2);
    return score(a) - score(b);
  });

  return games;
}

function setView(view) {
  state.view = view;
  $$("[data-view]").forEach((button) => button.classList.toggle("is-active", button.dataset.view === view));
  document.body.classList.remove("menu-open");
  render();
}

function viewCopy() {
  const copies = {
    home: ["THE FREE VAULT", "Scopri i giochi gratuiti"],
    current: ["DISPONIBILI ADESSO", "Gratis ora"],
    upcoming: ["PROSSIME USCITE", "In arrivo"],
    history: ["ARCHIVIO", "Cronologia delle offerte"],
    library: ["COLLEZIONE PERSONALE", "La mia libreria"],
  };
  return copies[state.view] || copies.home;
}

function renderHero() {
  const game = state.current[0];
  ui.hero.hidden = state.view !== "home" || !game;
  if (!game) return;

  ui.heroImage.src = game.image_url || PLACEHOLDER;
  ui.heroImage.onerror = () => { ui.heroImage.src = PLACEHOLDER; };
  ui.heroImage.alt = `Immagine di ${game.title}`;
  ui.heroTitle.textContent = game.title;
  ui.heroDescription.textContent = game.description || "Disponibile gratuitamente per un periodo limitato.";
  ui.heroPrice.textContent = formatCurrencyValue(game) ? `${formatCurrencyValue(game)} → GRATIS` : "GRATIS";
  ui.heroCountdown.textContent = countdownText(game);
  ui.heroLink.href = game.store_url;
  updateHeroLibraryButton(game);
  ui.heroLibrary.onclick = () => toggleLibrary(game);
}

function updateHeroLibraryButton(game) {
  ui.heroLibrary.textContent = getLibraryEntry(game) ? "Rimuovi dalla libreria" : "Aggiungi alla libreria";
}

function createCard(game) {
  const fragment = ui.template.content.cloneNode(true);
  const card = fragment.querySelector(".game-card");
  const coverButton = fragment.querySelector(".card-cover");
  const image = fragment.querySelector(".game-image");
  const badge = fragment.querySelector(".game-badge");
  const title = fragment.querySelector(".game-title");
  const publisher = fragment.querySelector(".publisher");
  const description = fragment.querySelector(".game-description");
  const price = fragment.querySelector(".original-price");
  const countdown = fragment.querySelector(".countdown");
  const progress = fragment.querySelector(".progress-fill");
  const link = fragment.querySelector(".store-link");
  const libraryButton = fragment.querySelector(".library-button");
  const favoriteButton = fragment.querySelector(".favorite-button");

  const mode = getMode(game);
  const entry = getLibraryEntry(game);
  const favorite = Boolean(entry?.favorite);

  image.src = game.image_url || PLACEHOLDER;
  image.alt = `Copertina di ${game.title}`;
  image.onerror = () => { image.src = PLACEHOLDER; };
  badge.textContent = game.is_mystery_game ? "MYSTERY GAME" : mode === "current" ? "GRATIS ORA" : mode === "upcoming" ? "IN ARRIVO" : "ARCHIVIO";
  title.textContent = game.title || "Titolo sconosciuto";
  publisher.textContent = game.publisher || "Epic Games Store";
  description.textContent = game.description || "Nessuna descrizione disponibile.";
  price.textContent = formatCurrencyValue(game);
  countdown.textContent = mode === "history" ? `Terminato il ${formatDate(game.end_date)}` : countdownText(game);
  progress.style.width = `${mode === "current" ? promotionProgress(game) : 0}%`;
  link.href = game.store_url || "https://store.epicgames.com/it/free-games";
  libraryButton.textContent = entry ? "✓" : "+";
  libraryButton.title = entry ? "Rimuovi dalla libreria" : "Aggiungi alla libreria";
  favoriteButton.textContent = favorite ? "♥" : "♡";
  favoriteButton.setAttribute("aria-label", favorite ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti");

  card.classList.toggle("is-library", Boolean(entry));
  card.classList.toggle("is-favorite", favorite);

  coverButton.addEventListener("click", () => openGameDialog(game));
  libraryButton.addEventListener("click", () => toggleLibrary(game));
  favoriteButton.addEventListener("click", () => toggleFavorite(game));

  return fragment;
}

function renderGrid() {
  const games = gamesForView();
  ui.grid.replaceChildren();

  if (!games.length) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.innerHTML = `<strong>Nessun gioco trovato</strong><br><span>Prova a modificare ricerca o filtri.</span>`;
    ui.grid.append(empty);
    return;
  }

  games.forEach((game) => ui.grid.append(createCard(game)));
}

function render() {
  const [eyebrow, title] = viewCopy();
  ui.eyebrow.textContent = eyebrow;
  ui.title.textContent = title;
  renderHero();
  renderGrid();
  updateStats();
}

function toggleLibrary(game) {
  if (getLibraryEntry(game)) removeLibraryEntry(game);
  else setLibraryEntry(game, { status: "saved" });
  render();
  if (ui.dialog.open && state.selectedGame) populateDialog(state.selectedGame);
}

function toggleFavorite(game) {
  const entry = getLibraryEntry(game);
  if (!entry) setLibraryEntry(game, { favorite: true, status: "saved" });
  else setLibraryEntry(game, { favorite: !entry.favorite });
  render();
  if (ui.dialog.open && state.selectedGame) populateDialog(state.selectedGame);
}

function updateStats() {
  $("#stat-current").textContent = String(state.current.length);
  $("#stat-upcoming").textContent = String(state.upcoming.length);
  $("#stat-library").textContent = String(Object.keys(state.library).length);

  let cents = 0;
  Object.values(state.library).forEach((entry) => {
    const game = entry?.game;
    if (!game || !Number.isFinite(game.original_price)) return;
    const decimals = Number.isFinite(game.currency_decimals) ? game.currency_decimals : 2;
    cents += game.original_price / (10 ** decimals);
  });
  $("#stat-saved").textContent = `${new Intl.NumberFormat("it-IT", { maximumFractionDigits: 0 }).format(cents)} €`;
}

function openGameDialog(game) {
  state.selectedGame = game;
  populateDialog(game);
  ui.dialog.showModal();
}

function populateDialog(game) {
  const mode = getMode(game);
  const entry = getLibraryEntry(game);
  ui.dialogImage.src = game.image_url || PLACEHOLDER;
  ui.dialogImage.onerror = () => { ui.dialogImage.src = PLACEHOLDER; };
  ui.dialogImage.alt = `Immagine di ${game.title}`;
  ui.dialogBadge.textContent = game.is_mystery_game ? "MYSTERY GAME" : mode === "current" ? "GRATIS ORA" : mode === "upcoming" ? "IN ARRIVO" : "ARCHIVIO";
  ui.dialogTitle.textContent = game.title;
  ui.dialogPublisher.textContent = game.publisher || "Epic Games Store";
  ui.dialogDescription.textContent = game.description || "Nessuna descrizione disponibile.";
  ui.dialogMeta.replaceChildren();
  [
    formatCurrencyValue(game) ? `Prezzo originale: ${formatCurrencyValue(game)}` : null,
    `Inizio: ${formatDate(game.start_date)}`,
    `Fine: ${formatDate(game.end_date)}`,
    game.offer_type ? `Tipo: ${game.offer_type}` : null,
  ].filter(Boolean).forEach((text) => {
    const span = document.createElement("span");
    span.textContent = text;
    ui.dialogMeta.append(span);
  });
  ui.dialogLink.href = game.store_url;
  ui.dialogLibrary.textContent = entry ? "Rimuovi dalla libreria" : "Aggiungi alla libreria";
  ui.dialogFavorite.textContent = entry?.favorite ? "♥ Preferito" : "♡ Preferito";
  ui.dialogStatus.disabled = !entry;
  ui.dialogStatus.value = entry?.status || "saved";
  ui.dialogNotes.disabled = !entry;
  ui.dialogNotes.value = entry?.notes || "";
  ui.dialogSaveStatus.textContent = entry
    ? "Note e valutazione vengono salvate automaticamente."
    : "Aggiungi il gioco alla libreria per usare note e valutazione.";
  updateRatingControl(entry?.rating || 0, Boolean(entry));
}

function updateRatingControl(rating, enabled) {
  ui.dialogRating.querySelectorAll("[data-rating]").forEach((button) => {
    const value = Number(button.dataset.rating);
    button.disabled = !enabled;
    button.classList.toggle("is-active", value <= rating);
    button.setAttribute("aria-checked", String(value === rating));
  });
}

function updatePersonalField(patch, confirmation) {
  if (!state.selectedGame || !getLibraryEntry(state.selectedGame)) return;
  setLibraryEntry(state.selectedGame, patch);
  ui.dialogSaveStatus.textContent = confirmation;
  window.clearTimeout(updatePersonalField.timer);
  updatePersonalField.timer = window.setTimeout(() => {
    ui.dialogSaveStatus.textContent = "Note e valutazione vengono salvate automaticamente.";
  }, 1800);
  render();
}

async function loadJson(url, fallback) {
  try {
    const response = await fetch(`${url}?v=${Date.now()}`, { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return await response.json();
  } catch (error) {
    console.warn(`Caricamento fallito: ${url}`, error);
    return fallback;
  }
}

async function loadData() {
  ui.refresh.disabled = true;
  ui.status.hidden = true;
  try {
    const [data, history] = await Promise.all([
      loadJson(DATA_URL, null),
      loadJson(HISTORY_URL, { games: [] }),
    ]);
    if (!data) throw new Error("games.json non disponibile");

    state.current = Array.isArray(data.current) ? data.current : [];
    state.upcoming = Array.isArray(data.upcoming) ? data.upcoming : [];
    state.history = Array.isArray(history.games) ? history.games : [];

    ui.sidebarUpdate.textContent = data.generated_at ? formatDate(data.generated_at) : "Aggiornamento sconosciuto";
    render();
  } catch (error) {
    ui.status.hidden = false;
    ui.status.textContent = "Impossibile aggiornare i dati. Potrebbero essere mostrati contenuti presenti nella cache.";
    console.error(error);
  } finally {
    ui.refresh.disabled = false;
  }
}

ui.search.addEventListener("input", () => {
  state.search = ui.search.value.trim();
  renderGrid();
});
ui.filter.addEventListener("change", () => { state.statusFilter = ui.filter.value; renderGrid(); });
ui.sort.addEventListener("change", () => { state.sort = ui.sort.value; renderGrid(); });
ui.refresh.addEventListener("click", loadData);
$("#menu-button").addEventListener("click", () => document.body.classList.toggle("menu-open"));
$$("[data-view]").forEach((button) => button.addEventListener("click", () => setView(button.dataset.view)));
$("#dialog-close").addEventListener("click", () => ui.dialog.close());
ui.dialog.addEventListener("click", (event) => {
  const rect = ui.dialog.getBoundingClientRect();
  if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) ui.dialog.close();
});
ui.dialogLibrary.addEventListener("click", () => state.selectedGame && toggleLibrary(state.selectedGame));
ui.dialogFavorite.addEventListener("click", () => state.selectedGame && toggleFavorite(state.selectedGame));
ui.dialogStatus.addEventListener("change", () => {
  updatePersonalField({ status: ui.dialogStatus.value }, "Stato aggiornato.");
});
ui.dialogRating.addEventListener("click", (event) => {
  const button = event.target.closest("[data-rating]");
  if (!button) return;
  const current = getLibraryEntry(state.selectedGame)?.rating || 0;
  const selected = Number(button.dataset.rating);
  const rating = current === selected ? 0 : selected;
  updatePersonalField({ rating }, rating ? `Valutazione: ${rating}/5.` : "Valutazione rimossa.");
  updateRatingControl(rating, true);
});
ui.dialogNotes.addEventListener("input", () => {
  window.clearTimeout(ui.dialogNotes.saveTimer);
  ui.dialogSaveStatus.textContent = "Salvataggio…";
  ui.dialogNotes.saveTimer = window.setTimeout(() => {
    updatePersonalField({ notes: ui.dialogNotes.value.trim() }, "Note salvate.");
  }, 450);
});
ui.exportLibrary.addEventListener("click", exportLibrary);
ui.importLibrary.addEventListener("click", () => ui.importLibraryFile.click());
ui.importLibraryFile.addEventListener("change", () => importLibraryFile(ui.importLibraryFile.files?.[0]));

document.addEventListener("keydown", (event) => {
  if (event.key === "/" && document.activeElement !== ui.search) {
    event.preventDefault();
    ui.search.focus();
  }
  if (event.key === "Escape" && ui.dialog.open) ui.dialog.close();
});

window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault();
  installPrompt = event;
  ui.install.hidden = false;
});
ui.install.addEventListener("click", async () => {
  if (!installPrompt) return;
  installPrompt.prompt();
  await installPrompt.userChoice;
  installPrompt = null;
  ui.install.hidden = true;
});

if ("serviceWorker" in navigator) navigator.serviceWorker.register("./service-worker.js").catch(console.error);
countdownTimer = setInterval(() => {
  if (state.current.length || state.upcoming.length) render();
}, 60000);

async function initializeApp() {
  await loadLibrary();
  updateStats();
  await loadData();
}

initializeApp();
