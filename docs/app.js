const DATA_URL = "./games.json";
const REDEEMED_KEY = "epic-free-games-redeemed-v1";

const currentContainer = document.querySelector("#current-games");
const upcomingContainer = document.querySelector("#upcoming-games");
const currentCount = document.querySelector("#current-count");
const upcomingCount = document.querySelector("#upcoming-count");
const updatedAt = document.querySelector("#updated-at");
const statusMessage = document.querySelector("#status-message");
const refreshButton = document.querySelector("#refresh-button");
const cardTemplate = document.querySelector("#game-card-template");

let countdownTimer = null;

function loadRedeemed() {
  try {
    return new Set(JSON.parse(localStorage.getItem(REDEEMED_KEY) || "[]"));
  } catch {
    return new Set();
  }
}

function saveRedeemed(values) {
  localStorage.setItem(REDEEMED_KEY, JSON.stringify([...values]));
}

function promotionKey(game) {
  return `${game.epic_id}|${game.start_date}|${game.end_date}`;
}

function formatDate(value) {
  return new Intl.DateTimeFormat("it-IT", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

function formatCountdown(target, mode) {
  const diff = new Date(target).getTime() - Date.now();
  if (diff <= 0) {
    return mode === "upcoming" ? "Disponibile ora" : "Promozione terminata";
  }

  const totalMinutes = Math.floor(diff / 60000);
  const days = Math.floor(totalMinutes / 1440);
  const hours = Math.floor((totalMinutes % 1440) / 60);
  const minutes = totalMinutes % 60;
  const prefix = mode === "upcoming" ? "Disponibile tra" : "Scade tra";

  if (days > 0) return `${prefix} ${days}g ${hours}h`;
  return `${prefix} ${hours}h ${minutes}m`;
}

function createCard(game, mode, redeemedSet) {
  const fragment = cardTemplate.content.cloneNode(true);
  const card = fragment.querySelector(".game-card");
  const image = fragment.querySelector(".game-image");
  const badge = fragment.querySelector(".game-badge");
  const title = fragment.querySelector(".game-title");
  const publisher = fragment.querySelector(".publisher");
  const description = fragment.querySelector(".game-description");
  const originalPrice = fragment.querySelector(".original-price");
  const countdown = fragment.querySelector(".countdown");
  const storeLink = fragment.querySelector(".store-link");
  const redeemedButton = fragment.querySelector(".redeemed-button");

  image.src = game.image_url || "./placeholders/game-placeholder.svg";
  image.alt = `Copertina di ${game.title}`;
  image.onerror = () => {
    image.src = "./placeholders/game-placeholder.svg";
  };

  badge.textContent = game.is_mystery_game
    ? "MYSTERY GAME"
    : mode === "current" ? "GRATIS ORA" : "IN ARRIVO";

  title.textContent = game.title;
  publisher.textContent = game.publisher || "Epic Games Store";
  description.textContent = game.description || "Nessuna descrizione disponibile.";
  originalPrice.textContent = game.fmt_original_price || "";
  storeLink.href = game.store_url;

  countdown.dataset.target = mode === "current" ? game.end_date : game.start_date;
  countdown.dataset.mode = mode;
  countdown.textContent = formatCountdown(countdown.dataset.target, mode);

  const key = promotionKey(game);
  const isRedeemed = redeemedSet.has(key);
  redeemedButton.hidden = mode !== "current";
  redeemedButton.setAttribute("aria-pressed", String(isRedeemed));
  redeemedButton.textContent = isRedeemed ? "Riscattato" : "Segna riscattato";
  card.classList.toggle("is-redeemed", isRedeemed);

  redeemedButton.addEventListener("click", () => {
    if (redeemedSet.has(key)) redeemedSet.delete(key);
    else redeemedSet.add(key);
    saveRedeemed(redeemedSet);

    const active = redeemedSet.has(key);
    redeemedButton.setAttribute("aria-pressed", String(active));
    redeemedButton.textContent = active ? "Riscattato" : "Segna riscattato";
    card.classList.toggle("is-redeemed", active);
  });

  return fragment;
}

function renderSection(container, games, mode, redeemedSet) {
  container.replaceChildren();
  if (!games.length) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = mode === "current"
      ? "Nessun gioco gratuito attivo rilevato."
      : "Nessuna promozione futura annunciata.";
    container.append(empty);
    return;
  }

  for (const game of games) {
    container.append(createCard(game, mode, redeemedSet));
  }
}

function updateCountdowns() {
  document.querySelectorAll(".countdown").forEach((node) => {
    node.textContent = formatCountdown(node.dataset.target, node.dataset.mode);
  });
}

async function loadGames() {
  refreshButton.disabled = true;
  statusMessage.hidden = true;

  try {
    const response = await fetch(`${DATA_URL}?v=${Date.now()}`, { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);

    const data = await response.json();
    const redeemed = loadRedeemed();

    renderSection(currentContainer, data.current || [], "current", redeemed);
    renderSection(upcomingContainer, data.upcoming || [], "upcoming", redeemed);

    currentCount.textContent = String((data.current || []).length);
    upcomingCount.textContent = String((data.upcoming || []).length);
    updatedAt.textContent = data.generated_at
      ? `Ultimo aggiornamento: ${formatDate(data.generated_at)}`
      : "Data aggiornamento non disponibile";

    clearInterval(countdownTimer);
    countdownTimer = setInterval(updateCountdowns, 60000);
  } catch (error) {
    statusMessage.hidden = false;
    statusMessage.textContent =
      "Impossibile aggiornare i dati. Se la PWA era già stata aperta, potrebbero essere mostrati dati memorizzati nella cache.";
    console.error(error);
  } finally {
    refreshButton.disabled = false;
  }
}

refreshButton.addEventListener("click", loadGames);

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("./service-worker.js").catch(console.error);
}

loadGames();
