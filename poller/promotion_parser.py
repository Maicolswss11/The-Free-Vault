"""Parsing del payload Epic in oggetti GamePromotion (funzioni pure)."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from . import constants as C
from .logging_config import get_logger
from .models import GamePromotion

logger = get_logger(__name__)


def parse_epic_datetime(value: str) -> datetime:
    """Converte una data ISO 8601 di Epic in un datetime UTC-aware.

    Epic usa il formato "2026-06-04T15:00:00.000Z"; se manca il fuso, si assume
    UTC. Solleva ValueError se la stringa non è una data valida.
    """
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"Data Epic non valida: {value!r}")
    normalized = value.strip().replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


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


def _is_http_url(value: object) -> bool:
    return isinstance(value, str) and value.startswith(("http://", "https://"))


def extract_best_image(element: dict[str, Any]) -> str | None:
    """Sceglie l'immagine migliore secondo IMAGE_TYPE_PRIORITY.

    Ignora gli URL non http (es. i video `com.epicgames.video://`).
    """
    images = element.get("keyImages") or []
    by_type: dict[str, str] = {}
    for image in images:
        if not isinstance(image, dict):
            continue
        img_type = image.get("type")
        url = image.get("url")
        if isinstance(img_type, str) and _is_http_url(url):
            by_type.setdefault(img_type, url)  # type: ignore[arg-type]
    for preferred in C.IMAGE_TYPE_PRIORITY:
        if preferred in by_type:
            return by_type[preferred]
    for image in images:
        if isinstance(image, dict) and _is_http_url(image.get("url")):
            return image["url"]
    return None


def _select_mapping_slug(mappings: Any) -> str | None:
    if not isinstance(mappings, list):
        return None
    for mapping in mappings:
        if isinstance(mapping, dict) and mapping.get("pageType") == C.PRODUCT_PAGE_TYPE:
            slug = mapping.get("pageSlug")
            if isinstance(slug, str) and slug:
                return slug
    for mapping in mappings:
        if isinstance(mapping, dict):
            slug = mapping.get("pageSlug")
            if isinstance(slug, str) and slug:
                return slug
    return None


def build_store_url(element: dict[str, Any]) -> str:
    """Costruisce l'URL dello store seguendo la catena di fallback.

    Ordine: offerMappings -> catalogNs.mappings -> productSlug -> pagina
    generale dei giochi gratuiti.
    """
    slug = _select_mapping_slug(element.get("offerMappings"))
    if not slug:
        catalog_ns = element.get("catalogNs")
        if isinstance(catalog_ns, dict):
            slug = _select_mapping_slug(catalog_ns.get("mappings"))
    if not slug:
        product_slug = element.get("productSlug")
        if isinstance(product_slug, str) and product_slug:
            slug = product_slug.split("/", 1)[0]  # rimuove eventuale suffisso "/home"
    if not slug:
        return C.FREE_GAMES_FALLBACK_URL
    slug = slug.strip("/")
    path = C.STORE_PRODUCT_PATH.format(locale=C.STORE_URL_LOCALE, slug=slug)
    return f"{C.STORE_BASE_URL}{path}"


def is_mystery_game(element: dict[str, Any]) -> bool:
    """Riconosce un "gioco misterioso" combinando più segnali del payload."""
    for image in element.get("keyImages") or []:
        if isinstance(image, dict) and image.get("type") == C.VAULT_IMAGE_TYPE:
            return True
    url_slug = element.get("urlSlug")
    if isinstance(url_slug, str) and C.MYSTERY_SLUG_MARKER in url_slug.lower():
        return True
    for category in element.get("categories") or []:
        if isinstance(category, dict) and category.get("path") == C.VAULTED_CATEGORY:
            return True
    seller = element.get("seller")
    if isinstance(seller, dict) and seller.get("name") == C.EPIC_TEST_SELLER:
        return True
    title = element.get("title")
    if isinstance(title, str) and "mystery game" in title.lower():
        return True
    return False


def _extract_price(
    element: dict[str, Any],
) -> tuple[int | None, int | None, str | None, int, str | None]:
    total = ((element.get("price") or {}).get("totalPrice")) or {}
    original_price = _safe_int(total.get("originalPrice"))
    discount_price = _safe_int(total.get("discountPrice"))
    currency = total.get("currencyCode")
    currency_code = currency if isinstance(currency, str) and currency else None
    decimals = _safe_int((total.get("currencyInfo") or {}).get("decimals"))
    if decimals is None:
        decimals = 2
    fmt = (total.get("fmtPrice") or {}).get("originalPrice")
    fmt_original = fmt if isinstance(fmt, str) and fmt else None
    return original_price, discount_price, currency_code, decimals, fmt_original


def _publisher(element: dict[str, Any]) -> str | None:
    seller = element.get("seller")
    if isinstance(seller, dict):
        name = seller.get("name")
        if isinstance(name, str) and name:
            return name
    return None


def _offer_is_free(offer: dict[str, Any]) -> bool:
    """True solo se lo sconto azzera il prezzo (discountPercentage == 0)."""
    setting = offer.get("discountSetting")
    if not isinstance(setting, dict):
        return False
    return _safe_int(setting.get("discountPercentage")) == C.FREE_DISCOUNT_PERCENTAGE


def _str_or(element: dict[str, Any], key: str, default: str | None) -> str | None:
    value = element.get(key)
    return value if isinstance(value, str) and value else default


def _build_promotion(
    element: dict[str, Any], offer: dict[str, Any], promotion_type: str
) -> GamePromotion | None:
    try:
        start_date = parse_epic_datetime(offer.get("startDate"))  # type: ignore[arg-type]
        end_date = parse_epic_datetime(offer.get("endDate"))  # type: ignore[arg-type]
    except (ValueError, TypeError):
        logger.warning(
            "Promozione ignorata per date non valide (%s): start=%r end=%r",
            element.get("title"),
            offer.get("startDate"),
            offer.get("endDate"),
        )
        return None

    epic_id = element.get("id")
    if not isinstance(epic_id, str) or not epic_id:
        logger.warning("Elemento senza id valido, ignorato: %r", element.get("title"))
        return None

    original_price, discount_price, currency_code, decimals, fmt_original = _extract_price(
        element
    )

    return GamePromotion(
        epic_id=epic_id,
        namespace=_str_or(element, "namespace", None),
        title=_str_or(element, "title", "(senza titolo)") or "(senza titolo)",
        description=_str_or(element, "description", "") or "",
        image_url=extract_best_image(element),
        store_url=build_store_url(element),
        original_price=original_price,
        discount_price=discount_price,
        currency_code=currency_code,
        currency_decimals=decimals,
        fmt_original_price=fmt_original,
        start_date=start_date,
        end_date=end_date,
        promotion_type=promotion_type,
        is_current=promotion_type == C.PROMO_CURRENT,
        is_upcoming=promotion_type == C.PROMO_UPCOMING,
        is_mystery_game=is_mystery_game(element),
        offer_type=_str_or(element, "offerType", None),
        publisher=_publisher(element),
    )


def _parse_offer_bucket(
    element: dict[str, Any], bucket_key: str, promotion_type: str
) -> list[GamePromotion]:
    promotions = element.get("promotions")
    if not isinstance(promotions, dict):
        return []
    bucket = promotions.get(bucket_key)
    if not isinstance(bucket, list):
        return []
    results: list[GamePromotion] = []
    for wrapper in bucket:
        if not isinstance(wrapper, dict):
            continue
        inner_offers = wrapper.get("promotionalOffers")
        if not isinstance(inner_offers, list):
            continue
        for offer in inner_offers:
            if not isinstance(offer, dict) or not _offer_is_free(offer):
                continue  # scontato ma non gratis, oppure malformato: si ignora
            promotion = _build_promotion(element, offer, promotion_type)
            if promotion is not None:
                results.append(promotion)
    return results


def parse_current_promotions(element: dict[str, Any]) -> list[GamePromotion]:
    """Promozioni gratuite ATTIVE (bucket `promotionalOffers`)."""
    return _parse_offer_bucket(element, "promotionalOffers", C.PROMO_CURRENT)


def parse_upcoming_promotions(element: dict[str, Any]) -> list[GamePromotion]:
    """Promozioni gratuite FUTURE (bucket `upcomingPromotionalOffers`)."""
    return _parse_offer_bucket(element, "upcomingPromotionalOffers", C.PROMO_UPCOMING)


def _extract_elements(payload: dict[str, Any]) -> list[Any]:
    if not isinstance(payload, dict):
        return []
    data = payload.get("data")
    if not isinstance(data, dict):
        return []
    catalog = data.get("Catalog")
    if not isinstance(catalog, dict):
        return []
    search_store = catalog.get("searchStore")
    if not isinstance(search_store, dict):
        return []
    elements = search_store.get("elements")
    return elements if isinstance(elements, list) else []


def parse_promotions(payload: dict[str, Any]) -> list[GamePromotion]:
    """Estrae tutte le promozioni gratuite (attive e future) dal payload.

    Tollerante a campi mancanti, `promotions: null` e mappings nulli. Restituisce
    solo veri regali temporanei (100% di sconto), scartando sconti parziali e
    prodotti gratuiti permanenti.
    """
    elements = _extract_elements(payload)
    results: list[GamePromotion] = []
    for element in elements:
        if not isinstance(element, dict):
            continue
        results.extend(parse_current_promotions(element))
        results.extend(parse_upcoming_promotions(element))
    logger.info("Promozioni gratuite individuate nel payload: %d", len(results))
    return results