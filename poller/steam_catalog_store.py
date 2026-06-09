"""Normalizzazione e persistenza del catalogo Steam."""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

from .catalog_models import StoreGame
from .catalog_store import (
    canonical_id_for_listing,
    canonical_title_for_listing,
    match_key_for_title,
)


def _text(value: object) -> str | None:
    return value.strip() if isinstance(value, str) and value.strip() else None


def _safe_int(value: object) -> int | None:
    if isinstance(value, bool):
        return None
    try:
        return int(value) if value is not None else None
    except (TypeError, ValueError):
        return None


def _response_object(payload: dict[str, Any]) -> dict[str, Any]:
    response = payload.get("response")
    return response if isinstance(response, dict) else payload


def steam_header_image(appid: int) -> str:
    return f"https://cdn.akamai.steamstatic.com/steam/apps/{appid}/header.jpg"


def parse_steam_app(element: dict[str, Any]) -> StoreGame | None:
    appid = _safe_int(element.get("appid"))
    title = _text(element.get("name"))
    if appid is None or appid <= 0 or not title:
        return None

    canonical_title, edition_name = canonical_title_for_listing(
        title,
        "base_game",
    )
    external_id = str(appid)
    return StoreGame(
        store="steam",
        external_id=external_id,
        namespace=None,
        title=title,
        canonical_title=canonical_title,
        canonical_id=canonical_id_for_listing(canonical_title),
        match_key=match_key_for_title(canonical_title),
        listing_id=f"steam:{external_id}",
        description="",
        developer=None,
        publisher=None,
        image_url=steam_header_image(appid),
        store_url=f"https://store.steampowered.com/app/{appid}/",
        product_slug=None,
        offer_type="BASE_GAME",
        category_group="base_game",
        edition_name=edition_name,
        market_segment="unclassified",
        market_segment_source="steam_app_list",
        release_date=None,
        release_year=None,
        original_price=None,
        discount_price=None,
        currency_code=None,
        currency_decimals=2,
        fmt_original_price=None,
        fmt_discount_price=None,
        platforms=["pc"],
        genres=[],
        tags=[],
        categories=["steam/game"],
    )


def parse_steam_page(payload: dict[str, Any]) -> list[StoreGame]:
    apps = _response_object(payload).get("apps") or []
    if not isinstance(apps, list):
        return []
    parsed: list[StoreGame] = []
    for element in apps:
        if not isinstance(element, dict):
            continue
        game = parse_steam_app(element)
        if game is not None:
            parsed.append(game)
    return parsed


def merge_steam_catalog(games: Iterable[StoreGame]) -> list[StoreGame]:
    merged: dict[str, StoreGame] = {}
    for game in games:
        merged[game.listing_id] = game
    return sorted(merged.values(), key=lambda game: game.title.casefold())


def write_steam_catalog_json(
    games: list[StoreGame],
    path: Path,
    *,
    generated_at: datetime | None = None,
) -> None:
    generated_at = generated_at or datetime.now(timezone.utc)
    payload = {
        "schema_version": 3,
        "generated_at": generated_at.isoformat(),
        "stores": ["steam"],
        "store": "steam",
        "total": len(games),
        "canonical_total": len({game.match_key for game in games}),
        "data_quality": "app-list",
        "games": [
            {
                "canonical_id": game.canonical_id,
                "canonical_title": game.canonical_title,
                "match_key": game.match_key,
                "listing_id": game.listing_id,
                "internal_id": game.listing_id,
                "store": "steam",
                "external_id": game.external_id,
                "title": game.title,
                "image_url": game.image_url,
                "store_url": game.store_url,
                "offer_type": game.offer_type,
                "category_group": game.category_group,
                "edition_name": game.edition_name,
                "market_segment": game.market_segment,
                "market_segment_source": game.market_segment_source,
                "platforms": ["pc"],
            }
            for game in games
        ],
    }

    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        tmp.write_text(
            json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)
