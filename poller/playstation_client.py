"""Client del catalogo pubblico PlayStation Store.

Il sito web PlayStation usa una query GraphQL persistita per le griglie delle
categorie. L'hash della query non è una credenziale, ma può cambiare quando
Sony aggiorna il frontend: per questo il valore può essere sovrascritto tramite
``PLAYSTATION_CATEGORY_QUERY_HASH`` senza modificare il codice.
"""

from __future__ import annotations

import json
import os
import time
from typing import Any, Iterable, Iterator

import requests

from . import constants as C
from .logging_config import get_logger

logger = get_logger(__name__)

PLAYSTATION_GRAPHQL_URL = "https://web.np.playstation.com/api/graphql/v1/op"
PLAYSTATION_PS4_CATEGORY_ID = "44d8bb20-653e-431e-8ad0-c0a365f68d2f"
PLAYSTATION_PS5_CATEGORY_ID = "4cbf39e2-5749-4970-ba81-93a489e4570c"
DEFAULT_CATEGORY_IDS: tuple[str, ...] = (
    PLAYSTATION_PS4_CATEGORY_ID,
    PLAYSTATION_PS5_CATEGORY_ID,
)

# Hash osservati per categoryGridRetrieve. Il primo è quello predefinito più
# recente; i successivi permettono un fallback trasparente durante i rollout.
DEFAULT_CATEGORY_QUERY_HASHES: tuple[str, ...] = (
    "9845afc0dbaab4965f6563fffc703f588c8e76792000e8610843b8d3ee9c4c09",
    "4ce7d410a4db2c8b635a48c1dcec375906ff63b19dadd87e073f8fd0c0481d35",
    "45ca7c832b785ad8455869e92f9f40a8bdbf04cb7a87a215455649ebf0c884b0",
)
ENV_PLAYSTATION_QUERY_HASH = "PLAYSTATION_CATEGORY_QUERY_HASH"
ENV_PLAYSTATION_LOCALE = "PLAYSTATION_LOCALE"
ENV_PLAYSTATION_CATEGORY_IDS = "PLAYSTATION_CATEGORY_IDS"


class PlayStationClientError(RuntimeError):
    """Errore durante il recupero del catalogo PlayStation."""


def configured_locale() -> str:
    return os.environ.get(ENV_PLAYSTATION_LOCALE, "it-IT").strip() or "it-IT"


def configured_category_ids() -> tuple[str, ...]:
    raw = os.environ.get(ENV_PLAYSTATION_CATEGORY_IDS, "")
    values = tuple(value.strip() for value in raw.split(",") if value.strip())
    return values or DEFAULT_CATEGORY_IDS


def _query_hashes(explicit: str | None = None) -> tuple[str, ...]:
    raw = explicit if explicit is not None else os.environ.get(ENV_PLAYSTATION_QUERY_HASH, "")
    configured = tuple(value.strip() for value in raw.split(",") if value.strip())
    if configured:
        return configured
    return DEFAULT_CATEGORY_QUERY_HASHES


def _graphql_error_text(payload: object) -> str:
    if not isinstance(payload, dict):
        return "risposta JSON non valida"
    errors = payload.get("errors")
    if not isinstance(errors, list):
        return ""
    messages: list[str] = []
    for error in errors:
        if isinstance(error, dict) and error.get("message"):
            messages.append(str(error["message"]))
        elif error:
            messages.append(str(error))
    return "; ".join(messages)


def _category_payload(payload: object) -> dict[str, Any] | None:
    if not isinstance(payload, dict):
        return None
    data = payload.get("data")
    if not isinstance(data, dict):
        return None
    category = data.get("categoryGridRetrieve")
    return category if isinstance(category, dict) else None


def fetch_category_page(
    category_id: str,
    *,
    offset: int = 0,
    size: int = 1_000,
    locale: str | None = None,
    query_hash: str | None = None,
    session: requests.Session | None = None,
) -> dict[str, Any]:
    """Recupera una pagina della griglia PlayStation Store.

    Prova in ordine l'hash configurato e i fallback incorporati. Un hash
    esplicito limita invece la richiesta al solo valore fornito.
    """
    category_id = category_id.strip()
    if not category_id:
        raise PlayStationClientError("Category ID PlayStation vuoto")

    offset = max(0, int(offset))
    size = max(1, min(int(size), 1_000))
    locale = (locale or configured_locale()).strip() or "it-IT"
    variables = {
        "id": category_id,
        "pageArgs": {"size": size, "offset": offset},
        "sortBy": None,
        "filterBy": [],
        "facetOptions": [],
    }

    owns_session = session is None
    session = session or requests.Session()
    failures: list[str] = []

    try:
        for candidate_hash in _query_hashes(query_hash):
            params = {
                "operationName": "categoryGridRetrieve",
                "variables": json.dumps(variables, separators=(",", ":")),
                "extensions": json.dumps(
                    {
                        "persistedQuery": {
                            "version": 1,
                            "sha256Hash": candidate_hash,
                        }
                    },
                    separators=(",", ":"),
                ),
            }
            try:
                response = session.get(
                    PLAYSTATION_GRAPHQL_URL,
                    params=params,
                    headers={
                        "Accept": "application/json",
                        "Content-Type": "application/json",
                        "Origin": "https://store.playstation.com",
                        "Referer": "https://store.playstation.com/",
                        "User-Agent": C.HTTP_USER_AGENT,
                        "x-psn-store-locale-override": locale,
                    },
                    timeout=(C.HTTP_CONNECT_TIMEOUT, max(C.HTTP_READ_TIMEOUT, 60.0)),
                )
                payload = response.json()
                if response.status_code >= 400:
                    failures.append(
                        f"{candidate_hash[:10]}… HTTP {response.status_code}: "
                        f"{_graphql_error_text(payload) or response.text[:180]}"
                    )
                    continue

                category = _category_payload(payload)
                if category is not None:
                    logger.info(
                        "PlayStation categoria=%s offset=%d size=%d hash=%s…",
                        category_id,
                        offset,
                        size,
                        candidate_hash[:10],
                    )
                    return payload

                failures.append(
                    f"{candidate_hash[:10]}…: "
                    f"{_graphql_error_text(payload) or 'categoryGridRetrieve assente'}"
                )
            except (requests.RequestException, ValueError) as exc:
                failures.append(f"{candidate_hash[:10]}…: {exc}")
    finally:
        if owns_session:
            session.close()

    detail = " | ".join(failures[-3:]) or "nessuna risposta valida"
    raise PlayStationClientError(
        "Fetch PlayStation fallito. La query persistita potrebbe essere cambiata; "
        f"aggiornare {ENV_PLAYSTATION_QUERY_HASH}. Dettagli: {detail}"
    )


def iter_category_pages(
    *,
    category_ids: Iterable[str] | None = None,
    page_size: int = 1_000,
    max_pages_per_category: int = 50,
    locale: str | None = None,
    query_hash: str | None = None,
    delay_seconds: float = 0.2,
    session: requests.Session | None = None,
) -> Iterator[dict[str, Any]]:
    """Itera PS4 e PS5 usando offset e pageInfo della risposta GraphQL."""
    ids = tuple(category_ids or configured_category_ids())
    if not ids:
        raise PlayStationClientError("Nessuna categoria PlayStation configurata")

    owns_session = session is None
    session = session or requests.Session()

    try:
        for category_id in ids:
            offset = 0
            for page_number in range(1, max_pages_per_category + 1):
                payload = fetch_category_page(
                    category_id,
                    offset=offset,
                    size=page_size,
                    locale=locale,
                    query_hash=query_hash,
                    session=session,
                )
                yield payload

                category = _category_payload(payload)
                if category is None:
                    raise PlayStationClientError(
                        f"Risposta categoria {category_id} priva di dati"
                    )
                products = category.get("products") or []
                if not isinstance(products, list):
                    raise PlayStationClientError(
                        f"Campo products non valido per {category_id}"
                    )

                page_info = category.get("pageInfo") or {}
                if not isinstance(page_info, dict):
                    page_info = {}
                current_offset = int(page_info.get("offset") or offset)
                returned_size = int(page_info.get("size") or len(products))
                total_count = int(page_info.get("totalCount") or 0)
                next_offset = current_offset + max(returned_size, len(products))

                logger.info(
                    "PlayStation categoria=%s pagina=%d ricevuti=%d progresso=%d/%s",
                    category_id,
                    page_number,
                    len(products),
                    next_offset,
                    total_count or "?",
                )

                if not products:
                    if total_count and current_offset < total_count:
                        raise PlayStationClientError(
                            f"Pagina vuota prematura per {category_id} a offset {offset}"
                        )
                    break
                if total_count and next_offset >= total_count:
                    break
                if next_offset <= offset:
                    raise PlayStationClientError(
                        f"Paginazione PlayStation non avanzata per {category_id}: {next_offset}"
                    )

                offset = next_offset
                if delay_seconds:
                    time.sleep(delay_seconds)
            else:
                raise PlayStationClientError(
                    f"Raggiunto il limite di {max_pages_per_category} pagine "
                    f"per la categoria {category_id}"
                )
    finally:
        if owns_session:
            session.close()
