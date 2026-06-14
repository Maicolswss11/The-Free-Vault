"""Normalizzazione IGDB nel database Master di The Free Vault."""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Iterable


EXTERNAL_SOURCE_NAMES: dict[int, str] = {
    1: "steam",
    5: "gog",
    10: "youtube",
    11: "microsoft",
    13: "apple",
    14: "twitch",
    15: "android",
    20: "amazon_asin",
    22: "amazon_luna",
    23: "amazon_adg",
    26: "epic",
    28: "oculus",
    29: "utomik",
    30: "itch_io",
    31: "xbox",
    32: "kartridge",
    36: "playstation",
    37: "focus_entertainment",
    54: "xbox_cloud",
    55: "gamejolt",
}

REGION_NAMES: dict[int, str] = {
    1: "europe",
    2: "north_america",
    3: "australia",
    4: "new_zealand",
    5: "japan",
    6: "china",
    7: "asia",
    8: "worldwide",
    9: "korea",
    10: "brazil",
}

DATE_PRECISION_NAMES: dict[int, str] = {
    0: "day",
    1: "month",
    2: "year",
    3: "quarter_1",
    4: "quarter_2",
    5: "quarter_3",
    6: "quarter_4",
    7: "tbd",
}

# Legacy game.category values and common names returned by game_types.
GAME_TYPE_NAMES: dict[int, str] = {
    0: "main_game",
    1: "dlc_addon",
    2: "expansion",
    3: "bundle",
    4: "standalone_expansion",
    5: "mod",
    6: "episode",
    7: "season",
    8: "remake",
    9: "remaster",
    10: "expanded_game",
    11: "port",
    12: "fork",
    13: "pack",
    14: "update",
}


@dataclass(slots=True)
class MasterBatch:
    games: list[dict[str, object]] = field(default_factory=list)
    platforms: list[dict[str, object]] = field(default_factory=list)
    releases: list[dict[str, object]] = field(default_factory=list)
    external_ids: list[dict[str, object]] = field(default_factory=list)
    titles: list[dict[str, object]] = field(default_factory=list)
    aliases: list[dict[str, object]] = field(default_factory=list)
    projections: list[dict[str, object]] = field(default_factory=list)

    def as_rpc_payload(self, *, run_id: str, cursor_id: int) -> dict[str, object]:
        return {
            "p_run_id": run_id,
            "p_cursor_id": int(cursor_id),
            "p_games": self.games,
            "p_platforms": self.platforms,
            "p_releases": self.releases,
            "p_external_ids": self.external_ids,
            "p_titles": self.titles,
            "p_aliases": self.aliases,
            "p_projections": self.projections,
        }


def normalize_identity(value: str | None) -> str:
    normalized = unicodedata.normalize("NFKD", value or "")
    ascii_value = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    ascii_value = ascii_value.casefold().replace("™", "").replace("®", "").replace("©", "")
    return re.sub(r"[^a-z0-9]+", " ", ascii_value).strip()


def _text(value: object) -> str | None:
    return value.strip() if isinstance(value, str) and value.strip() else None


def _integer(value: object) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.strip().lstrip("-").isdigit():
        return int(value)
    return None


def _object_id(value: object) -> int | None:
    if isinstance(value, dict):
        return _integer(value.get("id"))
    return _integer(value)


def _object_name(value: object, *fields: str) -> str | None:
    if isinstance(value, dict):
        for field_name in fields or ("name",):
            candidate = _text(value.get(field_name))
            if candidate:
                return candidate
    return _text(value)


def _unix_datetime(value: object) -> datetime | None:
    timestamp = _integer(value)
    if timestamp is None or timestamp <= 0:
        return None
    try:
        return datetime.fromtimestamp(timestamp, tz=timezone.utc)
    except (OverflowError, OSError, ValueError):
        return None


def _iso_datetime(value: object) -> str | None:
    parsed = _unix_datetime(value)
    return parsed.isoformat() if parsed else None


def _iso_date(value: object) -> str | None:
    parsed = _unix_datetime(value)
    return parsed.date().isoformat() if parsed else None


def _cover_url(raw: dict[str, Any]) -> str | None:
    cover = raw.get("cover")
    image_id = _object_name(cover, "image_id")
    if not image_id:
        return None
    return f"https://images.igdb.com/igdb/image/upload/t_cover_big_2x/{image_id}.jpg"


def _platform_family(name: str | None, slug: str | None) -> str:
    identity = normalize_identity(" ".join(filter(None, (name, slug))))
    if any(marker in identity for marker in ("playstation", "ps vita", "psp")):
        return "playstation"
    if "xbox" in identity:
        return "xbox"
    if any(marker in identity for marker in (
        "nintendo", "game boy", "gamecube", "wii", "famicom", "virtual boy",
    )):
        return "nintendo"
    if any(marker in identity for marker in (
        "windows", "linux", "mac", "dos", "amiga", "commodore", "atari st",
        "pc ", "pc dos",
    )):
        return "pc"
    return "other"


def _platform_record(raw: object) -> dict[str, object] | None:
    if not isinstance(raw, dict):
        platform_id = _integer(raw)
        if platform_id is None:
            return None
        return {
            "id": f"igdb:{platform_id}",
            "name": f"IGDB Platform {platform_id}",
            "slug": f"igdb-platform-{platform_id}",
            "abbreviation": None,
            "family": "other",
            "generation": None,
            "manufacturer": None,
            "source_provider": "igdb",
            "source_external_id": str(platform_id),
            "source_checksum": None,
            "metadata": {},
        }

    platform_id = _integer(raw.get("id"))
    if platform_id is None:
        return None
    name = _text(raw.get("name")) or f"IGDB Platform {platform_id}"
    slug = _text(raw.get("slug")) or f"igdb-platform-{platform_id}"
    family = _platform_family(name, slug)
    return {
        "id": f"igdb:{platform_id}",
        "name": name,
        "slug": slug,
        "abbreviation": _text(raw.get("abbreviation")),
        "family": family,
        "generation": _integer(raw.get("generation")),
        "manufacturer": None,
        "source_provider": "igdb",
        "source_external_id": str(platform_id),
        "source_checksum": _text(raw.get("checksum")),
        "metadata": {
            "igdb_url": _text(raw.get("url")),
            "alternative_name": _text(raw.get("alternative_name")),
        },
    }


def _company_names(raw: dict[str, Any]) -> tuple[str | None, str | None]:
    developers: list[str] = []
    publishers: list[str] = []
    for involved in raw.get("involved_companies") or []:
        if not isinstance(involved, dict):
            continue
        company = involved.get("company")
        name = _object_name(company, "name")
        if not name:
            continue
        if involved.get("developer") is True and name not in developers:
            developers.append(name)
        if involved.get("publisher") is True and name not in publishers:
            publishers.append(name)
    return (developers[0] if developers else None, publishers[0] if publishers else None)


def _genres(raw: dict[str, Any]) -> list[str]:
    values: list[str] = []
    for item in raw.get("genres") or []:
        name = _object_name(item, "name")
        if name and name not in values:
            values.append(name)
    return sorted(values, key=str.casefold)


def _game_type(raw: dict[str, Any]) -> str:
    value = raw.get("game_type", raw.get("category"))
    name = _object_name(value, "type", "name")
    if name:
        return normalize_identity(name).replace(" ", "_")
    type_id = _object_id(value)
    return GAME_TYPE_NAMES.get(type_id or -1, f"type_{type_id}" if type_id is not None else "unknown")


def _game_status(raw: dict[str, Any]) -> str | None:
    value = raw.get("game_status", raw.get("status"))
    name = _object_name(value, "name", "status")
    if name:
        return normalize_identity(name).replace(" ", "_")
    status_id = _object_id(value)
    return str(status_id) if status_id is not None else None


def _category_group(game_type: str) -> str:
    if game_type in {"dlc_addon", "dlc", "addon", "pack", "update"}:
        return "dlc"
    if game_type in {"expansion", "standalone_expansion", "expanded_game"}:
        return "expansion"
    if game_type in {"bundle", "season"}:
        return "bundle"
    if game_type in {"main_game", "remake", "remaster", "port", "fork"}:
        return "base_game"
    return "other"


def _date_precision(release: dict[str, Any]) -> str | None:
    value = _object_id(release.get("date_format", release.get("category")))
    return DATE_PRECISION_NAMES.get(value) if value is not None else None


def _region(release: dict[str, Any]) -> str | None:
    value = release.get("release_region", release.get("region"))
    name = _object_name(value, "region", "name")
    if name:
        return normalize_identity(name).replace(" ", "_")
    region_id = _object_id(value)
    return REGION_NAMES.get(region_id) if region_id is not None else None


def _source_provider(external: dict[str, Any]) -> str:
    value = external.get("external_game_source", external.get("category"))
    name = _object_name(value, "name")
    if name:
        normalized = normalize_identity(name).replace(" ", "_")
        aliases = {
            "epic_game_store": "epic",
            "playstation_store_us": "playstation",
            "xbox_marketplace": "xbox",
            "microsoft": "microsoft",
        }
        return aliases.get(normalized, normalized)
    source_id = _object_id(value)
    return EXTERNAL_SOURCE_NAMES.get(source_id or -1, f"igdb_source_{source_id}")


def _alternative_titles(raw: dict[str, Any]) -> list[tuple[str, str | None]]:
    values: list[tuple[str, str | None]] = []
    for item in raw.get("alternative_names") or []:
        if isinstance(item, dict):
            name = _text(item.get("name"))
            source_id = str(item.get("id")) if item.get("id") is not None else None
        else:
            name = _text(item)
            source_id = None
        if name and all(existing[0].casefold() != name.casefold() for existing in values):
            values.append((name, source_id))
    return values


def normalize_igdb_page(records: Iterable[dict[str, Any]]) -> MasterBatch:
    batch = MasterBatch()
    platform_map: dict[str, dict[str, object]] = {}
    release_keys: set[tuple[str, str]] = set()
    mapping_keys: set[tuple[str, str]] = set()
    title_keys: set[tuple[str, str, str]] = set()

    for raw in records:
        if not isinstance(raw, dict):
            continue
        igdb_id = _integer(raw.get("id"))
        title = _text(raw.get("name"))
        if igdb_id is None or not title:
            continue

        game_id = f"igdb:{igdb_id}"
        match_key = f"master:{game_id}"
        slug = _text(raw.get("slug")) or f"igdb-{igdb_id}"
        first_release = _iso_date(raw.get("first_release_date"))
        developer, publisher = _company_names(raw)
        genres = _genres(raw)
        game_type = _game_type(raw)
        game_status = _game_status(raw)
        cover_url = _cover_url(raw)
        source_url = _text(raw.get("url")) or f"https://www.igdb.com/games/{slug}"
        alternatives = _alternative_titles(raw)

        platform_slugs: list[str] = []
        for platform_raw in raw.get("platforms") or []:
            platform = _platform_record(platform_raw)
            if not platform:
                continue
            platform_map[str(platform["id"])] = platform
            platform_slug = str(platform["slug"])
            if platform_slug not in platform_slugs:
                platform_slugs.append(platform_slug)

        batch.games.append({
            "id": game_id,
            "title": title,
            "normalized_title": normalize_identity(title),
            "slug": slug,
            "original_title": title,
            "summary": _text(raw.get("summary")),
            "storyline": _text(raw.get("storyline")),
            "first_release_date": first_release,
            "developer": developer,
            "publisher": publisher,
            "market_segment": "unclassified",
            "genres": genres,
            "cover_url": cover_url,
            "source_url": source_url,
            "source_provider": "igdb",
            "source_external_id": str(igdb_id),
            "source_checksum": _text(raw.get("checksum")),
            "source_updated_at": _iso_datetime(raw.get("updated_at")),
            "game_type": game_type,
            "game_status": game_status,
            "alternative_titles": [value[0] for value in alternatives],
            "metadata": {
                "igdb_id": igdb_id,
                "parent_game": _object_id(raw.get("parent_game")),
                "version_parent": _object_id(raw.get("version_parent")),
                "rating": raw.get("rating"),
                "rating_count": raw.get("rating_count"),
            },
        })

        # Primary and alternative title index.
        title_candidates = [(title, "primary", str(igdb_id)), *(
            (alt_title, "alternative", source_id) for alt_title, source_id in alternatives
        )]
        for candidate, title_type, source_id in title_candidates:
            key = (game_id, candidate.casefold(), title_type)
            if key in title_keys:
                continue
            title_keys.add(key)
            batch.titles.append({
                "game_id": game_id,
                "title": candidate,
                "normalized_title": normalize_identity(candidate),
                "title_type": title_type,
                "locale": None,
                "source_provider": "igdb",
                "source_external_id": source_id,
            })

        # Stable aliases consumed by the existing game_key based frontend.
        batch.aliases.extend([
            {
                "alias_key": game_id,
                "game_id": game_id,
                "alias_kind": "provider_id",
                "provider": "igdb",
                "confidence": 1,
                "verified": True,
            },
            {
                "alias_key": match_key,
                "game_id": game_id,
                "alias_kind": "catalog_key",
                "provider": "igdb",
                "confidence": 1,
                "verified": True,
            },
        ])

        # IGDB itself is always an external mapping.
        batch.external_ids.append({
            "provider": "igdb",
            "external_id": str(igdb_id),
            "game_id": game_id,
            "external_type": "encyclopedia",
            "source_url": source_url,
            "confidence": 1,
            "verified": True,
            "metadata": {},
        })
        mapping_keys.add(("igdb", str(igdb_id)))

        for external in raw.get("external_games") or []:
            if not isinstance(external, dict):
                continue
            external_id = _text(external.get("uid"))
            if not external_id:
                continue
            provider = _source_provider(external)
            mapping_key = (provider, external_id)
            if mapping_key in mapping_keys:
                continue
            mapping_keys.add(mapping_key)
            batch.external_ids.append({
                "provider": provider,
                "external_id": external_id,
                "game_id": game_id,
                "external_type": "store" if provider != "igdb" else "encyclopedia",
                "source_url": _text(external.get("url")),
                "confidence": 1,
                "verified": True,
                "metadata": {
                    "igdb_external_game_id": _integer(external.get("id")),
                    "platform_id": _object_id(external.get("platform")),
                },
            })

        for release in raw.get("release_dates") or []:
            if not isinstance(release, dict):
                continue
            release_id = _integer(release.get("id"))
            if release_id is None:
                continue
            platform_raw = release.get("platform")
            platform = _platform_record(platform_raw)
            if platform:
                platform_map[str(platform["id"])] = platform
                platform_id = str(platform["id"])
                family = str(platform["family"])
            else:
                platform_id = None
                family = "other"
            release_key = ("igdb", str(release_id))
            if release_key in release_keys:
                continue
            release_keys.add(release_key)
            batch.releases.append({
                "game_id": game_id,
                "platform_id": platform_id,
                "platform_family": family,
                "edition_name": None,
                "release_date": _iso_date(release.get("date")),
                "region": _region(release),
                "human_release_date": _text(release.get("human")),
                "date_precision": _date_precision(release),
                "release_status": _object_name(release.get("status"), "name"),
                "source_provider": "igdb",
                "source_external_id": str(release_id),
                "source_checksum": _text(release.get("checksum")),
                "metadata": {
                    "year": _integer(release.get("y")),
                    "month": _integer(release.get("m")),
                    "day": _integer(release.get("d")),
                },
            })

        batch.projections.append({
            "match_key": match_key,
            "canonical_id": game_id,
            "master_game_id": game_id,
            "title": title,
            "canonical_title": title,
            "description": _text(raw.get("summary")),
            "developer": developer,
            "publisher": publisher,
            "image_url": cover_url,
            "store_url": source_url,
            "release_date": first_release,
            "release_year": int(first_release[:4]) if first_release else None,
            "market_segment": "unclassified",
            "category_group": _category_group(game_type),
            "offer_type": "IGDB_MASTER",
            "platforms": sorted(platform_slugs),
            "genres": genres,
            "categories": ["master", f"igdb/{game_type}"],
        })

    batch.platforms = sorted(platform_map.values(), key=lambda item: str(item["id"]))
    return batch
