"""Costanti centralizzate del progetto.

Raccoglie endpoint, parametri di rete, regole di selezione, percorsi di output
e template delle notifiche, così che ogni cambiamento resti confinato qui.
"""

from __future__ import annotations

from pathlib import Path

# --- Identità applicazione ---
APP_NAME: str = "Epic Free Games Tracker"

# --- Percorsi (il poller gira come Python normale, niente PyInstaller) ---
# constants.py vive in poller/, quindi la radice del repo è la cartella superiore.
PROJECT_ROOT: Path = Path(__file__).resolve().parent.parent
GAMES_JSON_PATH: Path = PROJECT_ROOT / "docs" / "games.json"
STATE_JSON_PATH: Path = PROJECT_ROOT / "state.json"

# --- Sorgente dati Epic ---
EPIC_PROMOTIONS_URL: str = (
    "https://store-site-backend-static.ak.epicgames.com/freeGamesPromotions"
)
EPIC_REQUEST_PARAMS: dict[str, str] = {
    "locale": "it-IT",
    "country": "IT",
    "allowCountries": "IT",
}
# User-Agent simile a un browser: riduce il rischio di filtraggio lato Epic.
HTTP_USER_AGENT: str = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)
HTTP_CONNECT_TIMEOUT: float = 10.0  # secondi
HTTP_READ_TIMEOUT: float = 20.0  # secondi
HTTP_MAX_RETRIES: int = 3
HTTP_RETRY_BACKOFF: float = 2.0  # secondi, moltiplicati per il numero di tentativo

# --- Costruzione URL dello store ---
STORE_BASE_URL: str = "https://store.epicgames.com"
STORE_URL_LOCALE: str = "it"
STORE_PRODUCT_PATH: str = "/{locale}/p/{slug}"
FREE_GAMES_FALLBACK_URL: str = f"{STORE_BASE_URL}/{STORE_URL_LOCALE}/free-games"
# pageType da preferire nelle mappings quando si sceglie lo slug del prodotto.
PRODUCT_PAGE_TYPE: str = "productHome"

# --- Selezione immagini (in ordine di preferenza) ---
IMAGE_TYPE_PRIORITY: tuple[str, ...] = (
    "OfferImageWide",
    "DieselStoreFrontWide",
    "VaultClosed",
    "Thumbnail",
)

# --- Regola "gratis" ---
# Convenzione Epic: discountPercentage indica quanto PAGHI. 0 => prezzo azzerato.
FREE_DISCOUNT_PERCENTAGE: int = 0

# --- Riconoscimento "gioco misterioso" ---
VAULT_IMAGE_TYPE: str = "VaultClosed"
VAULTED_CATEGORY: str = "freegames/vaulted"
MYSTERY_SLUG_MARKER: str = "mysterygame"
EPIC_TEST_SELLER: str = "Epic Dev Test Account"

# --- Tipi di offerta ---
OFFER_TYPES_DLC: frozenset[str] = frozenset({"ADD_ON", "DLC"})

# --- Tipi di promozione (valori del campo promotion_type) ---
PROMO_CURRENT: str = "current"
PROMO_UPCOMING: str = "upcoming"

# --- Promemoria scadenza ---
EXPIRY_REMINDER_HOURS: int = 24

# --- Visualizzazione date ---
# Il runner gira in UTC; per i testi delle notifiche convertiamo in orario IT.
# Su Linux (ambiente CI) zoneinfo trova il database fusi di sistema, niente tzdata.
DISPLAY_TIMEZONE: str = "Europe/Rome"
NOTIFY_DATE_FORMAT: str = "%d/%m alle %H:%M"

# --- Notifiche (ntfy) ---
DEFAULT_NTFY_BASE_URL: str = "https://ntfy.sh"
ENV_NTFY_TOPIC: str = "NTFY_TOPIC"
ENV_NTFY_TOKEN: str = "NTFY_TOKEN"
ENV_NTFY_BASE_URL: str = "NTFY_BASE_URL"

# I titoli restano ASCII/latin-1: gli header HTTP non trasportano emoji.
# Le emoji arrivano tramite l'header ntfy "Tags" (shortcode -> emoji).
NOTIFY_TITLE_NEW_CURRENT: str = "Gratis ora su Epic Games"
NOTIFY_TITLE_NEW_UPCOMING: str = "Presto gratis su Epic Games"
NOTIFY_TITLE_EXPIRING: str = "Ultimo giorno per riscattarlo"
NOTIFY_TAGS_NEW_CURRENT: tuple[str, ...] = ("video_game",)
NOTIFY_TAGS_NEW_UPCOMING: tuple[str, ...] = ("soon",)
NOTIFY_TAGS_EXPIRING: tuple[str, ...] = ("hourglass_flowing_sand",)
NOTIFY_PRIORITY_HIGH: str = "high"