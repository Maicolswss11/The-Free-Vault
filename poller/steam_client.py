"""Client Steam Web API per la sincronizzazione del catalogo.

Usa l'interfaccia ufficiale IStoreService/GetAppList. La chiave Web API resta
nei secret di GitHub Actions e non viene mai pubblicata nella PWA.
"""

from __future__ import annotations

import json
import os
import time
from typing import Any, Iterator

import requests

from . import constants as C
from .logging_config import get_logger

logger = get_logger(__name__)

STEAM_APP_LIST_URL = (
    "https://api.steampowered.com/IStoreService/GetAppList/v1/"
)
ENV_STEAM_WEB_API_KEY = "STEAM_WEB_API_KEY"


class SteamClientError(RuntimeError):
    """Errore durante il recupero del catalogo Steam."""


def _api_key(explicit: str | None = None) -> str:
    key = (explicit or os.environ.get(ENV_STEAM_WEB_API_KEY, "")).strip()
    if not key:
        raise SteamClientError(
            f"Manca il secret {ENV_STEAM_WEB_API_KEY}"
        )
    return key


def fetch_app_list_page(
    *,
    api_key: str | None = None,
    last_appid: int = 0,
    max_results: int = 50_000,
    if_modified_since: int | None = None,
    include_dlc: bool = False,
    session: requests.Session | None = None,
) -> dict[str, Any]:
    """Recupera una pagina da IStoreService/GetAppList.

    Steam richiede i parametri dei Service interface dentro ``input_json``.
    """
    key = _api_key(api_key)
    input_payload: dict[str, object] = {
        "include_games": True,
        "include_dlc": include_dlc,
        "include_software": False,
        "include_videos": False,
        "include_hardware": False,
        "last_appid": max(0, int(last_appid)),
        "max_results": max(1, min(int(max_results), 50_000)),
    }
    if if_modified_since is not None:
        input_payload["if_modified_since"] = max(0, int(if_modified_since))

    owns_session = session is None
    session = session or requests.Session()
    logger.info("Endpoint Steam catalogo: %s", STEAM_APP_LIST_URL)
    try:
        response = session.get(
            STEAM_APP_LIST_URL,
            params={
                "key": key,
                "input_json": json.dumps(input_payload, separators=(",", ":")),
            },
            headers={
                "Accept": "application/json",
                "User-Agent": C.HTTP_USER_AGENT,
            },
            timeout=(C.HTTP_CONNECT_TIMEOUT, max(C.HTTP_READ_TIMEOUT, 60.0)),
        )
        response.raise_for_status()
        payload = response.json()
    except (requests.RequestException, ValueError) as exc:
        raise SteamClientError(
            f"Fetch Steam fallito dopo appid={last_appid}: {exc}"
        ) from exc
    finally:
        if owns_session:
            session.close()

    if not isinstance(payload, dict):
        raise SteamClientError("Risposta Steam non valida")
    return payload


def _response_object(payload: dict[str, Any]) -> dict[str, Any]:
    response = payload.get("response")
    if isinstance(response, dict):
        return response
    # Tolleranza per fixture o eventuali wrapper differenti.
    return payload


def iter_app_list_pages(
    *,
    api_key: str | None = None,
    max_results: int = 50_000,
    max_pages: int = 20,
    include_dlc: bool = False,
    delay_seconds: float = 0.35,
    session: requests.Session | None = None,
) -> Iterator[dict[str, Any]]:
    """Itera il catalogo Steam usando ``last_appid`` per la continuazione."""
    owns_session = session is None
    session = session or requests.Session()
    last_appid = 0

    try:
        for page_number in range(1, max_pages + 1):
            payload = fetch_app_list_page(
                api_key=api_key,
                last_appid=last_appid,
                max_results=max_results,
                include_dlc=include_dlc,
                session=session,
            )
            yield payload

            response = _response_object(payload)
            apps = response.get("apps") or []
            if not isinstance(apps, list):
                raise SteamClientError("Campo response.apps non valido")

            have_more = bool(
                response.get("have_more_results")
                or response.get("have_more")
            )
            returned_last = response.get("last_appid")
            if returned_last is None and apps:
                returned_last = apps[-1].get("appid") if isinstance(apps[-1], dict) else None

            logger.info(
                "Steam catalogo: pagina %d, ricevuti=%d, ultimo appid=%s, altri=%s",
                page_number,
                len(apps),
                returned_last,
                have_more,
            )

            if not apps or not have_more:
                break

            try:
                next_last = int(returned_last)
            except (TypeError, ValueError) as exc:
                raise SteamClientError(
                    "Steam indica altre pagine ma non restituisce last_appid"
                ) from exc

            if next_last <= last_appid:
                raise SteamClientError(
                    f"Continuazione Steam non avanzata: {next_last}"
                )
            last_appid = next_last
            if delay_seconds:
                time.sleep(delay_seconds)
        else:
            raise SteamClientError(
                f"Raggiunto il limite di sicurezza di {max_pages} pagine"
            )
    finally:
        if owns_session:
            session.close()
