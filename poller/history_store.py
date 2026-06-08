"""Archivio storico delle promozioni viste dal tracker."""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from . import constants as C
from .free_games_selector import FreeGamesSelection
from .logging_config import get_logger

logger = get_logger(__name__)


def _read_history(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"updated_at": None, "games": []}
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        logger.warning("Cronologia non leggibile (%s): %s", path, exc)
        return {"updated_at": None, "games": []}
    if not isinstance(raw, dict) or not isinstance(raw.get("games"), list):
        return {"updated_at": None, "games": []}
    return raw


def update_history(
    selection: FreeGamesSelection,
    path: Path = C.HISTORY_JSON_PATH,
    *,
    updated_at: datetime | None = None,
) -> None:
    """Inserisce o aggiorna le promozioni correnti/future nella cronologia."""
    updated_at = updated_at or datetime.now(timezone.utc)
    history = _read_history(path)

    indexed: dict[str, dict[str, Any]] = {}
    for item in history.get("games", []):
        if isinstance(item, dict) and isinstance(item.get("promotion_key"), str):
            indexed[item["promotion_key"]] = item

    for promo in [*selection.current, *selection.upcoming]:
        item = promo.to_json_dict()
        item["promotion_key"] = promo.unique_key
        item["first_seen_at"] = indexed.get(promo.unique_key, {}).get(
            "first_seen_at", updated_at.isoformat()
        )
        item["last_seen_at"] = updated_at.isoformat()
        indexed[promo.unique_key] = item

    games = sorted(
        indexed.values(),
        key=lambda item: str(item.get("start_date", "")),
        reverse=True,
    )
    payload = {"updated_at": updated_at.isoformat(), "games": games}

    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        temp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)
