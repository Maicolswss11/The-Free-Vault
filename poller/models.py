"""Modello dati per le promozioni dei giochi gratuiti Epic Games.

Questo modulo dipende solo dalla libreria standard, così da restare puro e
facilmente testabile. La logica di parsing e selezione vive altrove
(`promotion_parser`, `free_games_selector`).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime


@dataclass(slots=True)
class GamePromotion:
    """Una singola promozione gratuita (attiva o futura) di un prodotto Epic.

    Le date sono sempre timezone-aware in UTC. La conversione in orario locale
    avviene solo in fase di visualizzazione (lato PWA) o nei testi delle
    notifiche.
    """

    epic_id: str
    namespace: str | None
    title: str
    description: str
    image_url: str | None
    store_url: str
    original_price: int | None  # unità minime della valuta (es. 1999 = 19,99)
    discount_price: int | None  # idem; per un vero regalo vale 0
    currency_code: str | None
    currency_decimals: int  # cifre decimali della valuta (di norma 2)
    fmt_original_price: str | None  # stringa già formattata da Epic (es. "$19.99")
    start_date: datetime  # inizio promozione, UTC-aware
    end_date: datetime  # fine promozione, UTC-aware
    promotion_type: str  # "current" oppure "upcoming"
    is_current: bool
    is_upcoming: bool
    is_mystery_game: bool
    offer_type: str | None  # es. "BASE_GAME", "ADD_ON", "BUNDLE", "OTHERS"
    publisher: str | None
    redeemed: bool = False

    @property
    def unique_key(self) -> str:
        """Chiave stabile per de-duplicare una promozione.

        Una promozione è "la stessa" se combaciano prodotto e finestra
        temporale: serve a evitare notifiche doppie.
        """
        return f"{self.epic_id}|{self.start_date.isoformat()}|{self.end_date.isoformat()}"

    @property
    def is_dlc(self) -> bool:
        """True se la promozione riguarda un DLC/add-on anziché un gioco intero."""
        return (self.offer_type or "").upper() in {"ADD_ON", "DLC"}

    def to_json_dict(self) -> dict[str, object]:
        """Serializza i campi necessari alla PWA, con le date in ISO 8601.

        Il campo `redeemed` è volutamente escluso: lo stato di riscatto vive nel
        browser dell'utente (localStorage), non lato server.
        """
        return {
            "epic_id": self.epic_id,
            "namespace": self.namespace,
            "title": self.title,
            "description": self.description,
            "image_url": self.image_url,
            "store_url": self.store_url,
            "original_price": self.original_price,
            "discount_price": self.discount_price,
            "currency_code": self.currency_code,
            "currency_decimals": self.currency_decimals,
            "fmt_original_price": self.fmt_original_price,
            "start_date": self.start_date.isoformat(),
            "end_date": self.end_date.isoformat(),
            "promotion_type": self.promotion_type,
            "is_current": self.is_current,
            "is_upcoming": self.is_upcoming,
            "is_mystery_game": self.is_mystery_game,
            "is_dlc": self.is_dlc,
            "offer_type": self.offer_type,
            "publisher": self.publisher,
        }