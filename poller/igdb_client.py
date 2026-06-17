"""Client minimale per IGDB API v4 con OAuth Twitch e rate limiting."""

from __future__ import annotations

import os
import time
from dataclasses import dataclass, field
from typing import Any

import requests

from .logging_config import get_logger

logger = get_logger(__name__)

TOKEN_URL = "https://id.twitch.tv/oauth2/token"
API_BASE_URL = "https://api.igdb.com/v4"
DEFAULT_PAGE_SIZE = 250
MAX_PAGE_SIZE = 500
MIN_REQUEST_INTERVAL = 0.27  # IGDB: 4 richieste al secondo.

GAME_FIELDS = ",".join((
    "id",
    "name",
    "slug",
    "summary",
    "storyline",
    "first_release_date",
    "updated_at",
    "checksum",
    "url",
    "rating",
    "rating_count",
    "parent_game",
    "version_parent",
    "game_type",
    "game_type.type",
    "game_status",
    "game_status.status",
    "cover.image_id",
    "artworks.image_id",
    "artworks.width",
    "artworks.height",
    "screenshots.image_id",
    "screenshots.width",
    "screenshots.height",
    "videos.name",
    "videos.video_id",
    "genres.name",
    "alternative_names.id",
    "alternative_names.name",
    "platforms.id",
    "platforms.name",
    "platforms.slug",
    "platforms.abbreviation",
    "platforms.generation",
    "platforms.checksum",
    "platforms.url",
    "involved_companies.developer",
    "involved_companies.publisher",
    "involved_companies.company.name",
    "release_dates.id",
    "release_dates.date",
    "release_dates.human",
    "release_dates.y",
    "release_dates.m",
    "release_dates.d",
    "release_dates.date_format",
    "release_dates.category",
    "release_dates.release_region",
    "release_dates.region",
    "release_dates.status.name",
    "release_dates.checksum",
    "release_dates.platform.id",
    "release_dates.platform.name",
    "release_dates.platform.slug",
    "release_dates.platform.abbreviation",
    "release_dates.platform.generation",
    "external_games.id",
    "external_games.uid",
    "external_games.url",
    "external_games.external_game_source",
    "external_games.external_game_source.name",
    "external_games.category",
    "external_games.platform.id",
))


class IGDBClientError(RuntimeError):
    """Errore di autenticazione o lettura da IGDB."""


class IGDBRequestRejected(IGDBClientError):
    """Richiesta rifiutata definitivamente per sintassi o parametri non validi."""


@dataclass(slots=True)
class IGDBClient:
    client_id: str
    client_secret: str
    session: requests.Session | None = None
    request_interval: float = MIN_REQUEST_INTERVAL
    _access_token: str | None = field(init=False, default=None, repr=False)
    _token_expires_at: float = field(init=False, default=0.0, repr=False)
    _last_request_at: float = field(init=False, default=0.0, repr=False)

    def __post_init__(self) -> None:
        self.client_id = self.client_id.strip()
        self.client_secret = self.client_secret.strip()
        if not self.client_id or not self.client_secret:
            raise IGDBClientError("Mancano IGDB_CLIENT_ID e IGDB_CLIENT_SECRET")
        self.session = self.session or requests.Session()

    @classmethod
    def from_env(cls) -> "IGDBClient":
        return cls(
            os.environ.get("IGDB_CLIENT_ID", ""),
            os.environ.get("IGDB_CLIENT_SECRET", ""),
        )

    def _authenticate(self) -> str:
        now = time.monotonic()
        if self._access_token and now < self._token_expires_at - 60:
            return self._access_token

        try:
            response = self.session.post(
                TOKEN_URL,
                params={
                    "client_id": self.client_id,
                    "client_secret": self.client_secret,
                    "grant_type": "client_credentials",
                },
                timeout=(15, 60),
            )
            response.raise_for_status()
            payload = response.json()
        except (requests.RequestException, ValueError) as exc:
            raise IGDBClientError(f"Autenticazione Twitch/IGDB fallita: {exc}") from exc

        token = payload.get("access_token") if isinstance(payload, dict) else None
        if not isinstance(token, str) or not token:
            raise IGDBClientError("La risposta OAuth non contiene access_token")
        expires_in = int(payload.get("expires_in") or 3600)
        self._access_token = token
        self._token_expires_at = time.monotonic() + max(60, expires_in)
        return token

    def _throttle(self) -> None:
        elapsed = time.monotonic() - self._last_request_at
        delay = self.request_interval - elapsed
        if delay > 0:
            time.sleep(delay)

    def query(self, endpoint: str, body: str, *, attempts: int = 5) -> list[dict[str, Any]]:
        token = self._authenticate()
        last_error: Exception | None = None
        for attempt in range(1, attempts + 1):
            self._throttle()
            try:
                response = self.session.post(
                    f"{API_BASE_URL}/{endpoint.strip('/')}",
                    data=body.encode("utf-8"),
                    headers={
                        "Client-ID": self.client_id,
                        "Authorization": f"Bearer {token}",
                        "Accept": "application/json",
                        "Content-Type": "text/plain",
                    },
                    timeout=(20, 120),
                )
                self._last_request_at = time.monotonic()
                if response.status_code == 401 and attempt == 1:
                    self._access_token = None
                    token = self._authenticate()
                    continue
                if response.status_code == 429 or response.status_code >= 500:
                    raise requests.HTTPError(
                        f"HTTP {response.status_code}: {response.text[:1000]}",
                        response=response,
                    )
                if 400 <= response.status_code < 500:
                    detail = (response.text or "").strip()[:1000]
                    raise IGDBRequestRejected(
                        f"IGDB HTTP {response.status_code} su {endpoint}: "
                        f"{detail or 'richiesta rifiutata senza dettagli'}"
                    )
                response.raise_for_status()
                payload = response.json()
                if not isinstance(payload, list):
                    raise IGDBClientError("IGDB ha restituito un payload non-array")
                return [item for item in payload if isinstance(item, dict)]
            except (requests.RequestException, ValueError, IGDBClientError) as exc:
                last_error = exc
                if isinstance(exc, IGDBRequestRejected) or attempt >= attempts:
                    break
                delay = min(20, 2 ** (attempt - 1))
                logger.warning(
                    "IGDB tentativo %d/%d fallito; nuovo tentativo tra %ds: %s",
                    attempt,
                    attempts,
                    delay,
                    exc,
                )
                time.sleep(delay)
        raise IGDBClientError(f"Richiesta IGDB fallita: {last_error}") from last_error

    def fetch_games_after(self, after_id: int, *, limit: int = DEFAULT_PAGE_SIZE) -> list[dict[str, Any]]:
        page_size = max(1, min(int(limit), MAX_PAGE_SIZE))
        cursor = max(0, int(after_id))
        body = (
            f"fields {GAME_FIELDS}; "
            f"where id > {cursor} & version_parent = null; "
            "sort id asc; "
            f"limit {page_size};"
        )
        return self.query("games", body)
