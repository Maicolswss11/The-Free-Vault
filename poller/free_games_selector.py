"""Selezione temporale dei giochi gratuiti (attivi vs in arrivo)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

from . import constants as C
from .logging_config import get_logger
from .models import GamePromotion

logger = get_logger(__name__)


@dataclass(slots=True)
class FreeGamesSelection:
    """Esito della selezione: regali attivi e regali in arrivo."""

    current: list[GamePromotion]
    upcoming: list[GamePromotion]


def select_free_games(
    promotions: list[GamePromotion], *, now: datetime | None = None
) -> FreeGamesSelection:
    """Smista le promozioni in attive e future rispetto a `now` (iniettabile).

    Scarta quelle scadute e de-duplica per `unique_key`. Gli attivi sono ordinati
    per scadenza più vicina, i futuri per inizio più vicino.
    """
    now = now or datetime.now(timezone.utc)
    current: list[GamePromotion] = []
    upcoming: list[GamePromotion] = []
    seen: set[str] = set()
    for promo in promotions:
        if promo.unique_key in seen:
            continue
        seen.add(promo.unique_key)
        if promo.end_date <= now:
            continue  # scaduta
        if promo.start_date <= now < promo.end_date:
            promo.promotion_type = C.PROMO_CURRENT
            promo.is_current = True
            promo.is_upcoming = False
            current.append(promo)
        elif promo.start_date > now:
            promo.promotion_type = C.PROMO_UPCOMING
            promo.is_current = False
            promo.is_upcoming = True
            upcoming.append(promo)
    current.sort(key=lambda p: p.end_date)
    upcoming.sort(key=lambda p: p.start_date)
    logger.info("Selezione: %d attivi, %d in arrivo", len(current), len(upcoming))
    return FreeGamesSelection(current=current, upcoming=upcoming)