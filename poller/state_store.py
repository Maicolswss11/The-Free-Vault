"""Persistenza su file: stato di de-duplica e dati JSON per la PWA."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from . import constants as C
from .free_games_selector import FreeGamesSelection
from .logging_config import get_logger

logger = get_logger(__name__)

_VALID_EVENT_PREFIXES = frozenset({"current", "upcoming", "expiry"})


@dataclass(slots=True)
class State:
    """Stato persistente usato per evitare notifiche doppie tra un run e l'altro."""

    notified_ids: set[str] = field(default_factory=set)
    expiry_reminded_ids: set[str] = field(default_factory=set)
    last_run: str | None = None

    @staticmethod
    def event_key(event_type: str, promotion_key: str) -> str:
        """Costruisce una chiave distinta per tipo di evento."""
        if event_type not in _VALID_EVENT_PREFIXES:
            raise ValueError(f"Tipo evento non valido: {event_type}")
        return f"{event_type}|{promotion_key}"

    def is_notified(self, key: str) -> bool:
        return key in self.notified_ids

    def mark_notified(self, key: str) -> None:
        self.notified_ids.add(key)

    def is_expiry_reminded(self, key: str) -> bool:
        return key in self.expiry_reminded_ids

    def mark_expiry_reminded(self, key: str) -> None:
        self.expiry_reminded_ids.add(key)

    def migrate_legacy_keys(self) -> None:
        """Migra in modo conservativo le vecchie chiavi prive di prefisso.

        Una vecchia chiave non distingue tra notifica futura e attiva. Per evitare
        di perdere la notifica "gratis ora", viene considerata come evento
        `upcoming`. Le chiavi già prefissate restano invariate.
        """
        migrated: set[str] = set()
        for key in self.notified_ids:
            if _has_event_prefix(key):
                migrated.add(key)
            else:
                migrated.add(self.event_key("upcoming", key))
        self.notified_ids = migrated

        migrated_expiry: set[str] = set()
        for key in self.expiry_reminded_ids:
            if _has_event_prefix(key):
                migrated_expiry.add(key)
            else:
                migrated_expiry.add(self.event_key("expiry", key))
        self.expiry_reminded_ids = migrated_expiry

    def prune(self, *, now: datetime | None = None, retention_days: int = 60) -> None:
        """Rimuove le chiavi delle promozioni concluse da oltre `retention_days`."""
        now = now or datetime.now(timezone.utc)
        cutoff = now.timestamp() - retention_days * 86_400
        self.notified_ids = {k for k in self.notified_ids if _key_end_after(k, cutoff)}
        self.expiry_reminded_ids = {
            k for k in self.expiry_reminded_ids if _key_end_after(k, cutoff)
        }


def _has_event_prefix(key: str) -> bool:
    prefix = key.split("|", 1)[0]
    return prefix in _VALID_EVENT_PREFIXES


def _extract_promotion_key(key: str) -> str:
    return key.split("|", 1)[1] if _has_event_prefix(key) else key


def _key_end_after(key: str, cutoff_ts: float) -> bool:
    promotion_key = _extract_promotion_key(key)
    parts = promotion_key.rsplit("|", 2)
    if len(parts) != 3:
        return True
    try:
        end = datetime.fromisoformat(parts[2])
    except ValueError:
        return True
    if end.tzinfo is None:
        end = end.replace(tzinfo=timezone.utc)
    return end.timestamp() >= cutoff_ts


def load_state(path: Path = C.STATE_JSON_PATH) -> State:
    """Carica e migra lo stato; se manca o è corrotto, parte da vuoto."""
    if not path.exists():
        return State()
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        logger.warning("Stato non leggibile (%s), si riparte da vuoto: %s", path, exc)
        return State()
    if not isinstance(raw, dict):
        return State()

    notified = raw.get("notified_ids")
    reminded = raw.get("expiry_reminded_ids")
    last_run = raw.get("last_run")

    state = State(
        notified_ids={str(v) for v in notified} if isinstance(notified, list) else set(),
        expiry_reminded_ids={str(v) for v in reminded} if isinstance(reminded, list) else set(),
        last_run=last_run if isinstance(last_run, str) else None,
    )
    state.migrate_legacy_keys()
    return state


def save_state(state: State, path: Path = C.STATE_JSON_PATH) -> None:
    payload = {
        "notified_ids": sorted(state.notified_ids),
        "expiry_reminded_ids": sorted(state.expiry_reminded_ids),
        "last_run": state.last_run,
    }
    _atomic_write_json(path, payload)


def write_games_json(
    selection: FreeGamesSelection,
    path: Path = C.GAMES_JSON_PATH,
    *,
    generated_at: datetime | None = None,
) -> None:
    generated_at = generated_at or datetime.now(timezone.utc)
    payload = {
        "generated_at": generated_at.isoformat(),
        "current": [p.to_json_dict() for p in selection.current],
        "upcoming": [p.to_json_dict() for p in selection.upcoming],
    }
    _atomic_write_json(path, payload)


def _atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        tmp.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            tmp.unlink(missing_ok=True)
