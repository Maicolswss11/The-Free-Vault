"""Parsing, deduplicazione e persistenza del catalogo Epic."""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

from .catalog_models import StoreGame
from .promotion_parser import build_store_url, extract_best_image, parse_epic_datetime


def _safe_int(value: object) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            return None
    return None


def _text(value: object) -> str | None:
    return value.strip() if isinstance(value, str) and value.strip() else None


def _release_date(element: dict[str, Any]) -> datetime | None:
    for key in ("releaseDate", "effectiveDate"):
        value = element.get(key)
        if not isinstance(value, str):
            continue
        try:
            return parse_epic_datetime(value)
        except ValueError:
            continue
    return None


def parse_catalog_element(element: dict[str, Any]) -> StoreGame | None:
    external_id = _text(element.get("id"))
    title = _text(element.get("title"))
    if not external_id or not title:
        return None

    total = ((element.get("price") or {}).get("totalPrice")) or {}
    fmt = total.get("fmtPrice") or {}
    seller = element.get("seller") or {}

    product_slug = _text(element.get("productSlug"))
    return StoreGame(
        store="epic",
        external_id=external_id,
        namespace=_text(element.get("namespace")),
        title=title,
        description=_text(element.get("description")) or "",
        developer=_text(element.get("developerDisplayName")),
        publisher=(
            _text(element.get("publisherDisplayName"))
            or _text(seller.get("name"))
        ),
        image_url=extract_best_image(element),
        store_url=build_store_url(element),
        product_slug=product_slug,
        offer_type=_text(element.get("offerType")),
        release_date=_release_date(element),
        original_price=_safe_int(total.get("originalPrice")),
        discount_price=_safe_int(total.get("discountPrice")),
        currency_code=_text(total.get("currencyCode")),
        currency_decimals=_safe_int((total.get("currencyInfo") or {}).get("decimals")) or 2,
        fmt_original_price=_text(fmt.get("originalPrice")),
        fmt_discount_price=_text(fmt.get("discountPrice")),
        tags=[
            str(tag["id"])
            for tag in (element.get("tags") or [])
            if isinstance(tag, dict) and tag.get("id") is not None
        ],
        categories=[
            str(category["path"])
            for category in (element.get("categories") or [])
            if isinstance(category, dict) and category.get("path")
        ],
    )


def parse_catalog_page(payload: dict[str, Any]) -> list[StoreGame]:
    elements = (
        payload.get("data", {})
        .get("Catalog", {})
        .get("searchStore", {})
        .get("elements", [])
    )
    if not isinstance(elements, list):
        return []

    games: list[StoreGame] = []
    for element in elements:
        if not isinstance(element, dict):
            continue
        game = parse_catalog_element(element)
        if game is not None:
            games.append(game)
    return games


def merge_catalog(games: Iterable[StoreGame]) -> list[StoreGame]:
    """Deduplica le listing mantenendo il record più ricco."""
    merged: dict[str, StoreGame] = {}
    for game in games:
        previous = merged.get(game.internal_id)
        if previous is None:
            merged[game.internal_id] = game
            continue

        previous_score = sum(
            bool(value)
            for value in (
                previous.description,
                previous.developer,
                previous.publisher,
                previous.image_url,
                previous.product_slug,
            )
        )
        current_score = sum(
            bool(value)
            for value in (
                game.description,
                game.developer,
                game.publisher,
                game.image_url,
                game.product_slug,
            )
        )
        if current_score >= previous_score:
            merged[game.internal_id] = game

    return sorted(merged.values(), key=lambda item: item.title.casefold())


def write_catalog_json(
    games: list[StoreGame],
    path: Path,
    *,
    generated_at: datetime | None = None,
) -> None:
    generated_at = generated_at or datetime.now(timezone.utc)
    payload = {
        "generated_at": generated_at.isoformat(),
        "store": "epic",
        "total": len(games),
        "games": [game.to_json_dict() for game in games],
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
