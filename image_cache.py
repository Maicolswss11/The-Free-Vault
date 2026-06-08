"""Entrypoint e orchestrazione del poller Epic Free Games."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable

from . import constants as C
from .epic_client import EpicClientError, fetch_promotions
from .free_games_selector import FreeGamesSelection, select_free_games
from .history_store import update_history
from .image_cache import cache_selection_images
from .logging_config import configure_logging, get_logger
from .notifier import (
    NtfyNotifier,
    notify_expiring,
    notify_new_current,
    notify_new_upcoming,
)
from .promotion_parser import parse_promotions
from .state_store import State, load_state, save_state, write_games_json

logger = get_logger(__name__)

PayloadFetcher = Callable[[], dict[str, Any]]
ImageCacher = Callable[[FreeGamesSelection], None]


def _notification_completed(notifier: NtfyNotifier, sent: bool) -> bool:
    """Una notifica è gestita se inviata o se ntfy è volutamente disabilitato."""
    return sent or not notifier.enabled


def _process_current_notifications(
    selection: FreeGamesSelection,
    state: State,
    notifier: NtfyNotifier,
) -> None:
    for promo in selection.current:
        event_key = state.event_key("current", promo.unique_key)
        if state.is_notified(event_key):
            continue

        sent = notify_new_current(notifier, promo)
        if _notification_completed(notifier, sent):
            state.mark_notified(event_key)


def _process_upcoming_notifications(
    selection: FreeGamesSelection,
    state: State,
    notifier: NtfyNotifier,
) -> None:
    for promo in selection.upcoming:
        event_key = state.event_key("upcoming", promo.unique_key)
        if state.is_notified(event_key):
            continue

        sent = notify_new_upcoming(notifier, promo)
        if _notification_completed(notifier, sent):
            state.mark_notified(event_key)


def _process_expiry_reminders(
    selection: FreeGamesSelection,
    state: State,
    notifier: NtfyNotifier,
    *,
    now: datetime,
) -> None:
    reminder_window = timedelta(hours=C.EXPIRY_REMINDER_HOURS)

    for promo in selection.current:
        remaining = promo.end_date - now
        if not (timedelta(0) < remaining <= reminder_window):
            continue

        event_key = state.event_key("expiry", promo.unique_key)
        if state.is_expiry_reminded(event_key):
            continue

        sent = notify_expiring(notifier, promo)
        if _notification_completed(notifier, sent):
            state.mark_expiry_reminded(event_key)


def run(
    *,
    now: datetime | None = None,
    fetcher: PayloadFetcher = fetch_promotions,
    notifier: NtfyNotifier | None = None,
    state_path: Path = C.STATE_JSON_PATH,
    games_path: Path = C.GAMES_JSON_PATH,
    history_path: Path | None = None,
    image_cacher: ImageCacher | None = cache_selection_images,
) -> int:
    """Esegue un ciclo completo del tracker.

    Returns:
        0 in caso di successo, 1 in caso di errore di fetch/parsing/persistenza.
    """
    now = now or datetime.now(timezone.utc)
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)
    now = now.astimezone(timezone.utc)

    notifier = notifier or NtfyNotifier()
    state = load_state(state_path)

    try:
        payload = fetcher()
        promotions = parse_promotions(payload)
        selection = select_free_games(promotions, now=now)
    except (EpicClientError, Exception):
        logger.exception("Aggiornamento Epic fallito: i dati esistenti non saranno sovrascritti.")
        return 1

    try:
        if image_cacher is not None:
            image_cacher(selection)

        write_games_json(selection, games_path, generated_at=now)
        update_history(
            selection,
            history_path or games_path.with_name("history.json"),
            updated_at=now,
        )

        _process_current_notifications(selection, state, notifier)
        _process_upcoming_notifications(selection, state, notifier)
        _process_expiry_reminders(selection, state, notifier, now=now)

        state.last_run = now.isoformat()
        state.prune(now=now)
        save_state(state, state_path)
    except OSError:
        logger.exception("Errore durante il salvataggio dei file del tracker.")
        return 1
    except Exception:
        logger.exception("Errore inatteso durante l'aggiornamento dello stato.")
        return 1

    logger.info(
        "Aggiornamento completato: %d attivi, %d futuri.",
        len(selection.current),
        len(selection.upcoming),
    )
    return 0


def main() -> int:
    configure_logging()
    return run()


if __name__ == "__main__":
    raise SystemExit(main())
