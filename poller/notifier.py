"""Invio delle notifiche push tramite ntfy e composizione dei messaggi."""

from __future__ import annotations

import os
from datetime import datetime
from zoneinfo import ZoneInfo

import requests

from . import constants as C
from .logging_config import get_logger
from .models import GamePromotion

logger = get_logger(__name__)


def _ascii_header(value: str) -> str:
    """Rende un valore sicuro per un header HTTP (codifica latin-1)."""
    return value.encode("latin-1", "replace").decode("latin-1")


def format_local_datetime(dt: datetime) -> str:
    """Formatta una data UTC nell'orario locale di visualizzazione (Italia)."""
    return dt.astimezone(ZoneInfo(C.DISPLAY_TIMEZONE)).strftime(C.NOTIFY_DATE_FORMAT)


class NtfyNotifier:
    """Invia notifiche a un topic ntfy. Se non configurato, è un no-op sicuro."""

    def __init__(
        self,
        topic: str | None = None,
        *,
        base_url: str | None = None,
        token: str | None = None,
        session: requests.Session | None = None,
    ) -> None:
        self.topic = (topic or os.environ.get(C.ENV_NTFY_TOPIC, "")).strip()
        self.base_url = (
            base_url or os.environ.get(C.ENV_NTFY_BASE_URL) or C.DEFAULT_NTFY_BASE_URL
        ).rstrip("/")
        self.token = token or os.environ.get(C.ENV_NTFY_TOKEN) or None
        self._session = session or requests.Session()
        if not self.topic:
            logger.warning(
                "ntfy non configurato (manca %s): le notifiche sono disattivate.",
                C.ENV_NTFY_TOPIC,
            )

    @property
    def enabled(self) -> bool:
        return bool(self.topic)

    def send(
        self,
        *,
        title: str,
        message: str,
        click_url: str | None = None,
        tags: tuple[str, ...] = (),
        priority: str | None = None,
    ) -> bool:
        """Invia una notifica; restituisce True se inviata.

        Non solleva mai: un errore d'invio viene loggato ma non interrompe il run.
        """
        if not self.enabled:
            logger.info("Notifica non inviata (ntfy disattivato): %s", title)
            return False
        url = f"{self.base_url}/{self.topic}"
        headers: dict[str, str] = {"Title": _ascii_header(title)}
        if tags:
            headers["Tags"] = ",".join(tags)
        if click_url:
            headers["Click"] = click_url
        if priority:
            headers["Priority"] = priority
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        try:
            response = self._session.post(
                url,
                data=message.encode("utf-8"),
                headers=headers,
                timeout=(C.HTTP_CONNECT_TIMEOUT, C.HTTP_READ_TIMEOUT),
            )
            response.raise_for_status()
            logger.info("Notifica inviata: %s", title)
            return True
        except requests.RequestException as exc:
            logger.error("Invio notifica fallito (%s): %s", title, exc)
            return False


def _price_suffix(promo: GamePromotion) -> str:
    if promo.fmt_original_price:
        return f" (invece di {promo.fmt_original_price})"
    return ""


def notify_new_current(notifier: NtfyNotifier, promo: GamePromotion) -> bool:
    """Notifica un nuovo gioco gratis attivo adesso."""
    message = (
        f"{promo.title} è gratis su Epic fino al "
        f"{format_local_datetime(promo.end_date)}{_price_suffix(promo)}."
    )
    return notifier.send(
        title=C.NOTIFY_TITLE_NEW_CURRENT,
        message=message,
        click_url=promo.store_url,
        tags=C.NOTIFY_TAGS_NEW_CURRENT,
        priority=C.NOTIFY_PRIORITY_HIGH,
    )


def notify_new_upcoming(notifier: NtfyNotifier, promo: GamePromotion) -> bool:
    """Notifica una nuova promozione futura (giochi misteriosi inclusi)."""
    label = "Un gioco misterioso" if promo.is_mystery_game else promo.title
    message = (
        f"{label} sarà gratis su Epic dal {format_local_datetime(promo.start_date)}."
    )
    return notifier.send(
        title=C.NOTIFY_TITLE_NEW_UPCOMING,
        message=message,
        click_url=promo.store_url,
        tags=C.NOTIFY_TAGS_NEW_UPCOMING,
    )


def notify_expiring(notifier: NtfyNotifier, promo: GamePromotion) -> bool:
    """Promemoria: il gioco gratis scade entro meno di un giorno."""
    message = (
        f"Ultimo giorno per riscattare {promo.title}: scade il "
        f"{format_local_datetime(promo.end_date)}."
    )
    return notifier.send(
        title=C.NOTIFY_TITLE_EXPIRING,
        message=message,
        click_url=promo.store_url,
        tags=C.NOTIFY_TAGS_EXPIRING,
        priority=C.NOTIFY_PRIORITY_HIGH,
    )