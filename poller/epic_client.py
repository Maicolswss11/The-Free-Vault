"""Client HTTP per l'endpoint pubblico dei giochi gratuiti Epic Games.

Tutta la logica di rete è confinata qui. L'endpoint non è ufficialmente
documentato: gli errori vengono gestiti e rilanciati come EpicClientError, così
che il chiamante possa registrarli senza far crashare il programma.
"""

from __future__ import annotations

import time
from typing import Any

import requests

from . import constants as C
from .logging_config import get_logger

logger = get_logger(__name__)


class EpicClientError(Exception):
    """Errore non recuperabile durante il recupero delle promozioni Epic."""


def fetch_promotions(
    *,
    url: str = C.EPIC_PROMOTIONS_URL,
    params: dict[str, str] | None = None,
    session: requests.Session | None = None,
) -> dict[str, Any]:
    """Recupera il payload JSON delle promozioni, con timeout e retry.

    Args:
        url: endpoint da interrogare (override utile nei test).
        params: parametri query (default: locale/country IT).
        session: sessione requests opzionale (iniettabile nei test).

    Returns:
        Il payload JSON deserializzato.

    Raises:
        EpicClientError: se il recupero fallisce dopo i tentativi previsti.
    """
    request_params = dict(C.EPIC_REQUEST_PARAMS if params is None else params)
    owns_session = session is None
    session = session or requests.Session()
    headers = {"User-Agent": C.HTTP_USER_AGENT, "Accept": "application/json"}
    timeout = (C.HTTP_CONNECT_TIMEOUT, C.HTTP_READ_TIMEOUT)
    last_error: Exception | None = None

    try:
        for attempt in range(1, C.HTTP_MAX_RETRIES + 1):
            try:
                logger.info(
                    "Richiesta promozioni Epic (tentativo %d/%d)",
                    attempt,
                    C.HTTP_MAX_RETRIES,
                )
                response = session.get(
                    url, params=request_params, headers=headers, timeout=timeout
                )
                response.raise_for_status()
                payload = response.json()
                if isinstance(payload, dict) and payload.get("errors"):
                    logger.warning(
                        "L'endpoint ha restituito errori parziali "
                        "(i dati restano utilizzabili): %s",
                        payload["errors"],
                    )
                return payload
            except (requests.Timeout, requests.ConnectionError) as exc:
                last_error = exc
                logger.warning("Errore di rete al tentativo %d: %s", attempt, exc)
            except requests.HTTPError as exc:
                last_error = exc
                status = exc.response.status_code if exc.response is not None else None
                if status is not None and 400 <= status < 500 and status != 429:
                    raise EpicClientError(
                        f"Risposta HTTP {status} dall'endpoint Epic"
                    ) from exc
                logger.warning("HTTP %s al tentativo %d", status, attempt)
            except ValueError as exc:  # JSON non valido
                last_error = exc
                logger.warning("JSON non valido al tentativo %d: %s", attempt, exc)

            if attempt < C.HTTP_MAX_RETRIES:
                time.sleep(C.HTTP_RETRY_BACKOFF * attempt)

        raise EpicClientError(
            "Impossibile recuperare le promozioni Epic dopo i tentativi previsti"
        ) from last_error
    finally:
        if owns_session:
            session.close()