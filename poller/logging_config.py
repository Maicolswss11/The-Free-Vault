"""Configurazione del logging per il poller.

Su GitHub Actions l'output su stdout viene già raccolto nel log del workflow,
quindi non serve un file rotante: basta uno StreamHandler ben formattato e
idempotente.
"""

from __future__ import annotations

import logging
import sys

_LOG_FORMAT: str = "%(asctime)s [%(levelname)s] %(name)s: %(message)s"
_DATE_FORMAT: str = "%Y-%m-%d %H:%M:%S"
_HANDLER_MARKER: str = "_efg_tracker_handler"


def configure_logging(level: int = logging.INFO) -> None:
    """Configura il logger radice in modo idempotente.

    Richiamarla più volte non aggiunge handler duplicati.

    Args:
        level: livello minimo dei messaggi (default INFO).
    """
    root = logging.getLogger()
    root.setLevel(level)

    # Se il nostro handler è già presente, non ne aggiungiamo un altro.
    for existing in root.handlers:
        if getattr(existing, _HANDLER_MARKER, False):
            existing.setLevel(level)
            return

    handler = logging.StreamHandler(stream=sys.stdout)
    handler.setLevel(level)
    handler.setFormatter(logging.Formatter(fmt=_LOG_FORMAT, datefmt=_DATE_FORMAT))
    setattr(handler, _HANDLER_MARKER, True)  # marcatore anti-duplicati
    root.addHandler(handler)


def get_logger(name: str) -> logging.Logger:
    """Restituisce un logger con il nome dato (di norma `__name__`)."""
    return logging.getLogger(name)