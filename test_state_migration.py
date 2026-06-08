"""Download e cache locale delle copertine usate dalla PWA."""

from __future__ import annotations

import hashlib
import mimetypes
import os
from pathlib import Path
from urllib.parse import urlparse

import requests

from . import constants as C
from .free_games_selector import FreeGamesSelection
from .logging_config import get_logger

logger = get_logger(__name__)

_CONTENT_TYPE_EXTENSIONS = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/gif": ".gif",
    "image/avif": ".avif",
}


def _extension_for(url: str, content_type: str | None) -> str:
    normalized = (content_type or "").split(";", 1)[0].strip().lower()
    if normalized in _CONTENT_TYPE_EXTENSIONS:
        return _CONTENT_TYPE_EXTENSIONS[normalized]

    suffix = Path(urlparse(url).path).suffix.lower()
    if suffix in {".jpg", ".jpeg", ".png", ".webp", ".gif", ".avif"}:
        return ".jpg" if suffix == ".jpeg" else suffix

    guessed = mimetypes.guess_extension(normalized) if normalized else None
    return guessed or ".jpg"


def _cover_name(url: str, extension: str) -> str:
    digest = hashlib.sha256(url.encode("utf-8")).hexdigest()[:24]
    return f"{digest}{extension}"


def download_cover(
    url: str,
    *,
    output_dir: Path = C.COVERS_DIR,
    session: requests.Session | None = None,
) -> str | None:
    """Scarica una copertina e restituisce il percorso pubblico relativo."""
    if not url.startswith(("https://", "http://")):
        return None

    owns_session = session is None
    session = session or requests.Session()
    headers = {"User-Agent": C.HTTP_USER_AGENT, "Accept": "image/*"}

    try:
        response = session.get(
            url,
            headers=headers,
            timeout=(C.HTTP_CONNECT_TIMEOUT, C.HTTP_READ_TIMEOUT),
            stream=True,
        )
        response.raise_for_status()

        content_type = response.headers.get("Content-Type")
        if content_type and not content_type.lower().startswith("image/"):
            raise ValueError(f"Content-Type non immagine: {content_type}")

        extension = _extension_for(url, content_type)
        filename = _cover_name(url, extension)
        output_dir.mkdir(parents=True, exist_ok=True)
        destination = output_dir / filename

        if destination.exists() and destination.stat().st_size > 0:
            return f"{C.PUBLIC_COVER_PREFIX}/{filename}"

        temp = destination.with_name(f".{destination.name}.{os.getpid()}.tmp")
        total = 0
        try:
            with temp.open("wb") as handle:
                for chunk in response.iter_content(chunk_size=64 * 1024):
                    if not chunk:
                        continue
                    total += len(chunk)
                    if total > C.MAX_COVER_BYTES:
                        raise ValueError("Copertina oltre il limite massimo")
                    handle.write(chunk)
            if total == 0:
                raise ValueError("Copertina vuota")
            os.replace(temp, destination)
        finally:
            temp.unlink(missing_ok=True)

        return f"{C.PUBLIC_COVER_PREFIX}/{filename}"
    except (requests.RequestException, OSError, ValueError) as exc:
        logger.warning("Download copertina fallito (%s): %s", url, exc)
        return None
    finally:
        if owns_session:
            session.close()


def cache_selection_images(
    selection: FreeGamesSelection,
    *,
    output_dir: Path = C.COVERS_DIR,
    session: requests.Session | None = None,
) -> None:
    """Sostituisce gli URL remoti con copie locali quando il download riesce."""
    promotions = [*selection.current, *selection.upcoming]
    resolved: dict[str, str | None] = {}

    for promo in promotions:
        source = promo.image_url
        if not source:
            continue
        if source.startswith(("./", "/")):
            continue
        if source not in resolved:
            resolved[source] = download_cover(source, output_dir=output_dir, session=session)
        local_path = resolved[source]
        if local_path:
            promo.image_url = local_path
