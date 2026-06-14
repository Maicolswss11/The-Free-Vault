"""Normalizzazione e persistenza del catalogo PlayStation Store."""

from __future__ import annotations

import json
import os
import re
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any, Iterable

from .catalog_models import StoreGame
from .catalog_store import (
    canonical_id_for_listing,
    canonical_title_for_listing,
    match_key_for_title,
)

_PLAYSTATION_BASE_URL = "https://store.playstation.com"
_NON_GAME_CLASSIFICATIONS = {
    "ADD_ON",
    "AVATAR",
    "CHARACTER",
    "COSTUME",
    "DEMO",
    "LEVEL",
    "MAP",
    "MUSIC",
    "SEASON_PASS",
    "THEME",
    "VEHICLE",
    "VIRTUAL_CURRENCY",
    "WEAPON",
}
_EDITION_WORDS = re.compile(
    r"\b(?:standard|deluxe|ultimate|gold|complete|premium|collector(?:'s)?|"
    r"digital deluxe|game of the year|goty|anniversary|definitive)\s+edition\b|"
    r"\bedizione\s+(?:standard|deluxe|ultimate|gold|completa|premium|"
    r"da collezione|anniversario|definitiva)\b",
    re.I,
)
_PLATFORM_SUFFIX = re.compile(
    r"(?:\s*[-–—:]?\s*)"
    r"(?:\(|\[)?(?:per\s+)?"
    r"(?:playstation\s*)?(?:ps)?[45](?:™|®)?"
    r"(?:\s*(?:e|&|/|,|\+)\s*(?:playstation\s*)?(?:ps)?[45](?:™|®)?)*"
    r"(?:\)|\])?\s*$",
    re.I,
)
_ITALIAN_EDITION_PREFIX = re.compile(
    r"^edizione\s+(.+?)\s+(?:di|del|della|dello|dei|degli|delle)\s+(.+)$",
    re.I,
)
_ITALIAN_EDITION_SUFFIX = re.compile(
    r"^(.+?)\s*[-–—:]\s*edizione\s+(.+)$",
    re.I,
)


def _text(value: object) -> str | None:
    return value.strip() if isinstance(value, str) and value.strip() else None


def _classification(element: dict[str, Any]) -> str:
    return (_text(element.get("storeDisplayClassification")) or "FULL_GAME").upper()


def _looks_like_edition(title: str) -> bool:
    return bool(_EDITION_WORDS.search(title) or _ITALIAN_EDITION_PREFIX.match(title))


def _category_group(title: str, classification: str) -> str:
    if classification in _NON_GAME_CLASSIFICATIONS:
        return "dlc"
    if _looks_like_edition(title) or "EDITION" in classification:
        return "edition"
    if "BUNDLE" in classification or "[bundle]" in title.casefold():
        return "bundle"
    if classification in {"FULL_GAME", "BASE_GAME", "GAME"}:
        return "base_game"
    return "other"


def _canonicalize_title(title: str, category_group: str) -> tuple[str, str | None]:
    cleaned = title.strip()
    previous = None
    while cleaned != previous:
        previous = cleaned
        cleaned = _PLATFORM_SUFFIX.sub("", cleaned).strip(" -–—:()[]")

    prefix = _ITALIAN_EDITION_PREFIX.match(cleaned)
    if prefix:
        edition = prefix.group(1).strip()
        canonical = prefix.group(2).strip()
        return canonical or title.strip(), f"{edition} Edition"

    suffix = _ITALIAN_EDITION_SUFFIX.match(cleaned)
    if suffix:
        canonical = suffix.group(1).strip()
        edition = suffix.group(2).strip()
        return canonical or title.strip(), f"{edition} Edition"

    # Il normalizzatore condiviso riconosce "Deluxe Edition"; qui gestiamo
    # prima le varianti composte tipiche del PS Store per non lasciare "Digital".
    compound_editions = (
        (re.compile(r"\s*[-–—:]?\s*digital deluxe edition\s*$", re.I), "Digital Deluxe Edition"),
        (re.compile(r"\s*[-–—:]?\s*collector(?:'s)? edition\s*$", re.I), "Collector's Edition"),
        (re.compile(r"\s*[-–—:]?\s*anniversary edition\s*$", re.I), "Anniversary Edition"),
        (re.compile(r"\s*[-–—:]?\s*definitive edition\s*$", re.I), "Definitive Edition"),
    )
    for pattern, label in compound_editions:
        if pattern.search(cleaned):
            canonical = pattern.sub("", cleaned).strip(" -–—:")
            return canonical or title.strip(), label

    helper_group = "edition" if _looks_like_edition(cleaned) else category_group
    return canonical_title_for_listing(cleaned, helper_group)


def _release_date(value: object) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    normalized = value.strip().replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def _price_string(price: dict[str, Any], *keys: str) -> str | None:
    for key in keys:
        value = price.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def _minor_units(value: object, *, decimals: int = 2) -> int | None:
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, int):
        # I campi numerici del catalogo possono essere già in minor units.
        return value if abs(value) >= 1_000 else value * (10**decimals)
    if isinstance(value, float):
        return int(round(value * (10**decimals)))
    if not isinstance(value, str):
        return None

    raw = value.strip()
    if not raw:
        return None
    raw = re.sub(r"[^0-9,.-]", "", raw)
    if not raw:
        return None
    if "," in raw and "." in raw:
        if raw.rfind(",") > raw.rfind("."):
            raw = raw.replace(".", "").replace(",", ".")
        else:
            raw = raw.replace(",", "")
    elif "," in raw:
        raw = raw.replace(".", "").replace(",", ".")
    try:
        return int((Decimal(raw) * (10**decimals)).quantize(Decimal("1")))
    except (InvalidOperation, ValueError):
        return None


def _price_values(element: dict[str, Any]) -> tuple[int | None, int | None, str | None, str | None, str]:
    price = element.get("price") or {}
    if not isinstance(price, dict):
        price = {}
    decimals = 2
    currency = _text(price.get("currencyCode")) or "EUR"
    fmt_original = _price_string(price, "basePrice", "originalPrice", "regularPrice")
    fmt_discount = _price_string(price, "discountedPrice", "finalPrice", "salePrice")

    original_raw = next(
        (price.get(key) for key in ("basePriceValue", "originalPriceValue", "regularPriceValue") if price.get(key) is not None),
        fmt_original,
    )
    discount_raw = next(
        (price.get(key) for key in ("discountedPriceValue", "finalPriceValue", "salePriceValue") if price.get(key) is not None),
        fmt_discount,
    )
    original = _minor_units(original_raw, decimals=decimals)
    discount = _minor_units(discount_raw, decimals=decimals)
    if discount is None:
        discount = original
    return original, discount, fmt_original, fmt_discount, currency


def _best_image(element: dict[str, Any]) -> str | None:
    media = element.get("media") or []
    if not isinstance(media, list):
        return None
    priorities = ("MASTER", "GAMEHUB_COVER_ART", "FOUR_BY_THREE_BANNER", "BACKGROUND")
    for role in priorities:
        for item in media:
            if not isinstance(item, dict):
                continue
            if str(item.get("role") or "").upper() == role and _text(item.get("url")):
                return _text(item.get("url"))
    for item in media:
        if isinstance(item, dict) and _text(item.get("url")):
            return _text(item.get("url"))
    return None


def _platforms(element: dict[str, Any]) -> list[str]:
    raw = element.get("platforms") or []
    if isinstance(raw, str):
        raw = [raw]
    normalized: list[str] = []
    for value in raw if isinstance(raw, list) else []:
        text = str(value).strip().casefold().replace("playstation", "ps")
        match = re.search(r"ps\s*([45])", text)
        platform = f"ps{match.group(1)}" if match else text.replace(" ", "")
        if platform and platform not in normalized:
            normalized.append(platform)
    return normalized or ["playstation"]


def _market_segment(publisher: str | None) -> tuple[str, str]:
    name = (publisher or "").casefold()
    if any(marker in name for marker in (
        "sony interactive", "playstation", "microsoft", "electronic arts",
        "activision", "ubisoft", "square enix", "capcom", "sega", "konami",
        "take-two", "2k", "warner bros", "bandai namco", "bethesda",
    )):
        return "aaa", "curated_publisher"
    return "unclassified", "insufficient_data"


def parse_playstation_product(
    element: dict[str, Any],
    *,
    locale_path: str = "it-it",
    include_add_ons: bool = False,
) -> StoreGame | None:
    external_id = _text(element.get("id"))
    title = _text(element.get("name")) or _text(element.get("title"))
    if not external_id or not title:
        return None

    classification = _classification(element)
    if classification in _NON_GAME_CLASSIFICATIONS and not include_add_ons:
        return None

    category_group = _category_group(title, classification)
    canonical_title, edition_name = _canonicalize_title(title, category_group)
    publisher = (
        _text(element.get("publisherName"))
        or _text(element.get("publisher"))
        or _text(element.get("providerName"))
    )
    developer = _text(element.get("developerName")) or _text(element.get("developer"))
    release_date = _release_date(element.get("releaseDate") or element.get("releaseDateTime"))
    original, discount, fmt_original, fmt_discount, currency = _price_values(element)
    market_segment, segment_source = _market_segment(publisher)
    locale_path = locale_path.strip("/") or "it-it"
    offer_type = {
        "FULL_GAME": "BASE_GAME",
        "BASE_GAME": "BASE_GAME",
        "GAME": "BASE_GAME",
    }.get(classification)
    if offer_type is None:
        if category_group == "dlc":
            offer_type = "DLC"
        elif category_group == "bundle":
            offer_type = "BUNDLE"
        elif category_group == "edition":
            offer_type = "EDITION"
        else:
            offer_type = classification

    genres_raw = element.get("genres") or []
    if isinstance(genres_raw, str):
        genres_raw = [genres_raw]
    genres = [str(value).strip() for value in genres_raw if str(value).strip()]

    return StoreGame(
        store="playstation",
        external_id=external_id,
        namespace=None,
        title=title,
        canonical_title=canonical_title,
        canonical_id=canonical_id_for_listing(canonical_title, developer, publisher),
        match_key=match_key_for_title(canonical_title),
        listing_id=f"playstation:{external_id}",
        description=_text(element.get("description")) or "",
        developer=developer,
        publisher=publisher,
        image_url=_best_image(element),
        store_url=f"{_PLAYSTATION_BASE_URL}/{locale_path}/product/{external_id}",
        product_slug=None,
        offer_type=offer_type,
        category_group=category_group,
        edition_name=edition_name,
        market_segment=market_segment,
        market_segment_source=segment_source,
        release_date=release_date,
        release_year=release_date.year if release_date else None,
        original_price=original,
        discount_price=discount,
        currency_code=currency,
        currency_decimals=2,
        fmt_original_price=fmt_original,
        fmt_discount_price=fmt_discount,
        platforms=_platforms(element),
        genres=genres,
        tags=[],
        categories=[
            "playstation/game" if category_group != "dlc" else "playstation/add-on",
            f"playstation/{classification.casefold()}",
        ],
    )


def parse_playstation_page(
    payload: dict[str, Any],
    *,
    locale_path: str = "it-it",
    include_add_ons: bool = False,
) -> list[StoreGame]:
    category = (payload.get("data") or {}).get("categoryGridRetrieve") or {}
    products = category.get("products") or [] if isinstance(category, dict) else []
    if not isinstance(products, list):
        return []

    games: list[StoreGame] = []
    for element in products:
        if not isinstance(element, dict):
            continue
        game = parse_playstation_product(
            element,
            locale_path=locale_path,
            include_add_ons=include_add_ons,
        )
        if game is not None:
            games.append(game)
    return games


def merge_playstation_catalog(games: Iterable[StoreGame]) -> list[StoreGame]:
    merged: dict[str, StoreGame] = {}
    for game in games:
        previous = merged.get(game.listing_id)
        if previous is None:
            merged[game.listing_id] = game
            continue
        previous_score = sum(bool(value) for value in (
            previous.description, previous.developer, previous.publisher,
            previous.image_url, previous.release_date,
        ))
        current_score = sum(bool(value) for value in (
            game.description, game.developer, game.publisher,
            game.image_url, game.release_date,
        ))
        if current_score >= previous_score:
            merged[game.listing_id] = game
    return sorted(merged.values(), key=lambda game: (game.title.casefold(), game.listing_id))


def write_playstation_catalog_json(
    games: list[StoreGame],
    path: Path,
    *,
    generated_at: datetime | None = None,
) -> None:
    generated_at = generated_at or datetime.now(timezone.utc)
    payload = {
        "schema_version": 3,
        "generated_at": generated_at.isoformat(),
        "stores": ["playstation"],
        "store": "playstation",
        "total": len(games),
        "canonical_total": len({game.match_key for game in games}),
        "data_quality": "playstation-category-grid",
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
