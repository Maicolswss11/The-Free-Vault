"""Parsing, classificazione e persistenza del catalogo Epic."""

from __future__ import annotations

import hashlib
import json
import os
import re
import unicodedata
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

from .catalog_models import StoreGame
from .promotion_parser import build_store_url, extract_best_image, parse_epic_datetime


_AAA_PUBLISHER_MARKERS = (
    "2k", "activision", "bandai namco", "bethesda", "blizzard", "capcom",
    "cd projekt", "deep silver", "electronic arts", "ea games", "epic games",
    "focus entertainment", "gearbox", "konami", "microsoft", "nacon",
    "nintendo", "paradox interactive", "playstation", "rockstar",
    "sega", "square enix", "take-two", "thq nordic", "ubisoft",
    "warner bros", "wb games", "xbox game studios",
)

_EDITION_PATTERNS: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"\s*[-–—:]?\s*standard edition\s*$", re.I), "Standard Edition"),
    (re.compile(r"\s*[-–—:]?\s*deluxe edition\s*$", re.I), "Deluxe Edition"),
    (re.compile(r"\s*[-–—:]?\s*ultimate edition\s*$", re.I), "Ultimate Edition"),
    (re.compile(r"\s*[-–—:]?\s*gold edition\s*$", re.I), "Gold Edition"),
    (re.compile(r"\s*[-–—:]?\s*complete edition\s*$", re.I), "Complete Edition"),
    (re.compile(r"\s*[-–—:]?\s*game of the year edition\s*$", re.I), "Game of the Year Edition"),
    (re.compile(r"\s*[-–—:]?\s*goty edition\s*$", re.I), "GOTY Edition"),
)


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


def _normalize_identity(value: str | None) -> str:
    normalized = unicodedata.normalize("NFKD", value or "")
    ascii_value = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    ascii_value = ascii_value.casefold().replace("™", "").replace("®", "").replace("©", "")
    return re.sub(r"[^a-z0-9]+", " ", ascii_value).strip()


def _canonical_title(title: str, category_group: str) -> tuple[str, str | None]:
    if category_group == "bundle":
        return title.strip(), None

    canonical = title.strip()
    edition_name: str | None = None
    for pattern, label in _EDITION_PATTERNS:
        if pattern.search(canonical):
            canonical = pattern.sub("", canonical).strip(" -–—:")
            edition_name = label
            break
    return canonical or title.strip(), edition_name


def _canonical_id(title: str, developer: str | None, publisher: str | None) -> str:
    identity = "|".join(
        (
            _normalize_identity(title),
            _normalize_identity(developer or publisher),
        )
    )
    digest = hashlib.sha1(identity.encode("utf-8")).hexdigest()[:20]
    return f"game:{digest}"


def _category_group(offer_type: str | None, categories: list[str]) -> str:
    normalized_offer = (offer_type or "").upper()
    category_text = " ".join(categories).casefold()

    if normalized_offer in {"ADD_ON", "DLC"} or "addons" in category_text or "add-ons" in category_text:
        return "dlc"
    if normalized_offer == "BUNDLE" or "bundle" in category_text:
        return "bundle"
    if "games/edition/base" in categories or normalized_offer == "BASE_GAME":
        return "base_game"
    if "games/edition" in categories or normalized_offer in {"EDITION", "OTHERS"}:
        return "edition"
    return "other"


def _market_segment(
    developer: str | None,
    publisher: str | None,
    original_price: int | None,
    category_group: str,
) -> tuple[str, str]:
    names = " ".join(filter(None, (developer, publisher))).casefold()
    if any(marker in names for marker in _AAA_PUBLISHER_MARKERS):
        return "aaa", "curated_publisher"

    if (
        category_group == "base_game"
        and developer
        and publisher
        and _normalize_identity(developer) == _normalize_identity(publisher)
        and (original_price is None or original_price <= 6000)
    ):
        return "indie", "self_published_estimate"

    return "unclassified", "insufficient_data"


def parse_catalog_element(element: dict[str, Any]) -> StoreGame | None:
    external_id = _text(element.get("id"))
    title = _text(element.get("title"))
    if not external_id or not title:
        return None

    total = ((element.get("price") or {}).get("totalPrice")) or {}
    fmt = total.get("fmtPrice") or {}
    seller = element.get("seller") or {}
    namespace = _text(element.get("namespace"))
    developer = _text(element.get("developerDisplayName"))
    publisher = _text(element.get("publisherDisplayName")) or _text(seller.get("name"))
    original_price = _safe_int(total.get("originalPrice"))
    release_date = _release_date(element)
    categories = [
        str(category["path"])
        for category in (element.get("categories") or [])
        if isinstance(category, dict) and category.get("path")
    ]
    offer_type = _text(element.get("offerType"))
    category_group = _category_group(offer_type, categories)
    canonical_title, edition_name = _canonical_title(title, category_group)
    market_segment, segment_source = _market_segment(
        developer,
        publisher,
        original_price,
        category_group,
    )
    listing_id = f"epic:{namespace or 'unknown'}:{external_id}"

    return StoreGame(
        store="epic",
        external_id=external_id,
        namespace=namespace,
        title=title,
        canonical_title=canonical_title,
        canonical_id=_canonical_id(canonical_title, developer, publisher),
        listing_id=listing_id,
        description=_text(element.get("description")) or "",
        developer=developer,
        publisher=publisher,
        image_url=extract_best_image(element),
        store_url=build_store_url(element),
        product_slug=_text(element.get("productSlug")),
        offer_type=offer_type,
        category_group=category_group,
        edition_name=edition_name,
        market_segment=market_segment,
        market_segment_source=segment_source,
        release_date=release_date,
        release_year=release_date.year if release_date else None,
        original_price=original_price,
        discount_price=_safe_int(total.get("discountPrice")),
        currency_code=_text(total.get("currencyCode")),
        currency_decimals=_safe_int((total.get("currencyInfo") or {}).get("decimals")) or 2,
        fmt_original_price=_text(fmt.get("originalPrice")),
        fmt_discount_price=_text(fmt.get("discountPrice")),
        platforms=["pc"],
        genres=[],
        tags=[
            str(tag["id"])
            for tag in (element.get("tags") or [])
            if isinstance(tag, dict) and tag.get("id") is not None
        ],
        categories=categories,
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
        previous = merged.get(game.listing_id)
        if previous is None:
            merged[game.listing_id] = game
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
            merged[game.listing_id] = game

    return sorted(merged.values(), key=lambda item: item.title.casefold())


def write_catalog_json(
    games: list[StoreGame],
    path: Path,
    *,
    generated_at: datetime | None = None,
) -> None:
    generated_at = generated_at or datetime.now(timezone.utc)
    canonical_total = len({game.canonical_id for game in games})
    payload = {
        "schema_version": 2,
        "generated_at": generated_at.isoformat(),
        "stores": ["epic"],
        "store": "epic",
        "total": len(games),
        "canonical_total": canonical_total,
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
