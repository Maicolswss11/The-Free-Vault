"""Client paginato per il catalogo pubblico dello storefront Epic.

L'endpoint GraphQL è usato dallo storefront ma non è una API consumer
formalmente documentata. È isolato in questo modulo per poterlo sostituire.
"""

from __future__ import annotations

import time
from typing import Any, Iterator

import requests

from . import constants as C
from .logging_config import get_logger

logger = get_logger(__name__)

CATALOG_GRAPHQL_URLS: tuple[str, ...] = (
    "https://graphql.epicgames.com/ue/graphql",
    "https://graphql.epicgames.com/graphql",
)

SEARCH_STORE_QUERY = r"""
query searchStoreQuery(
  $allowCountries: String
  $category: String
  $count: Int
  $country: String!
  $keywords: String
  $locale: String
  $sortBy: String
  $sortDir: String
  $start: Int
  $withPrice: Boolean = true
) {
  Catalog {
    searchStore(
      allowCountries: $allowCountries
      category: $category
      count: $count
      country: $country
      keywords: $keywords
      locale: $locale
      sortBy: $sortBy
      sortDir: $sortDir
      start: $start
    ) {
      elements {
        title
        id
        namespace
        description
        effectiveDate
        releaseDate
        keyImages { type url }
        seller { id name }
        productSlug
        urlSlug
        offerMappings { pageSlug pageType }
        catalogNs {
          mappings(pageType: "productHome") { pageSlug pageType }
        }
        developerDisplayName
        publisherDisplayName
        offerType
        tags { id }
        categories { path }
        price(country: $country) @include(if: $withPrice) {
          totalPrice {
            discountPrice
            originalPrice
            currencyCode
            currencyInfo { decimals }
            fmtPrice(locale: $locale) {
              originalPrice
              discountPrice
            }
          }
        }
      }
      paging { count total }
    }
  }
}
"""


class CatalogClientError(RuntimeError):
    """Errore durante la sincronizzazione del catalogo."""


def fetch_catalog_page(
    *,
    start: int,
    count: int = 100,
    category: str = "games/edition/base|bundles/games",
    locale: str = "it-IT",
    country: str = "IT",
    session: requests.Session | None = None,
) -> dict[str, Any]:
    """Scarica una pagina del catalogo Epic."""
    owns_session = session is None
    session = session or requests.Session()
    payload = {
        "query": SEARCH_STORE_QUERY,
        "variables": {
            "allowCountries": country,
            "category": category,
            "count": count,
            "country": country,
            "keywords": "",
            "locale": locale,
            "sortBy": "title",
            "sortDir": "ASC",
            "start": start,
            "withPrice": True,
        },
    }
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "User-Agent": C.HTTP_USER_AGENT,
    }

    last_error: Exception | None = None

    try:
        for endpoint in CATALOG_GRAPHQL_URLS:
            try:
                response = session.post(
                    endpoint,
                    json=payload,
                    headers=headers,
                    timeout=(C.HTTP_CONNECT_TIMEOUT, C.HTTP_READ_TIMEOUT),
                )

                if response.status_code == 404:
                    logger.warning("Endpoint GraphQL non disponibile: %s", endpoint)
                    continue

                response.raise_for_status()
                data = response.json()

                if not isinstance(data, dict):
                    raise CatalogClientError(
                        f"Risposta GraphQL non valida da {endpoint}"
                    )
                if data.get("errors"):
                    raise CatalogClientError(
                        f"Epic GraphQL errors da {endpoint}: {data['errors']}"
                    )

                logger.info("Endpoint catalogo attivo: %s", endpoint)
                return data

            except (requests.RequestException, ValueError, CatalogClientError) as exc:
                last_error = exc
                logger.warning("Tentativo catalogo fallito su %s: %s", endpoint, exc)

        raise CatalogClientError(
            f"Nessun endpoint catalogo Epic disponibile allo start={start}"
        ) from last_error
    finally:
        if owns_session:
            session.close()


def iter_catalog_pages(
    *,
    page_size: int = 100,
    max_pages: int = 200,
    category: str = "games/edition/base|bundles/games",
    delay_seconds: float = 0.25,
    session: requests.Session | None = None,
) -> Iterator[dict[str, Any]]:
    """Itera tutte le pagine fino al totale dichiarato dal server."""
    owns_session = session is None
    session = session or requests.Session()
    start = 0

    try:
        for page_number in range(max_pages):
            payload = fetch_catalog_page(
                start=start,
                count=page_size,
                category=category,
                session=session,
            )
            yield payload

            search = (
                payload.get("data", {})
                .get("Catalog", {})
                .get("searchStore", {})
            )
            paging = search.get("paging") or {}
            elements = search.get("elements") or []
            total = int(paging.get("total") or 0)
            received = len(elements)

            logger.info(
                "Catalogo: pagina %d, start=%d, ricevuti=%d, totale=%d",
                page_number + 1,
                start,
                received,
                total,
            )

            if received == 0 or start + received >= total:
                break
            start += received
            if delay_seconds:
                time.sleep(delay_seconds)
        else:
            raise CatalogClientError(
                f"Raggiunto il limite di sicurezza di {max_pages} pagine"
            )
    finally:
        if owns_session:
            session.close()
