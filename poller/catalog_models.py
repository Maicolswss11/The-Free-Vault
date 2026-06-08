"""Modelli normalizzati del catalogo Epic Games Store."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime


@dataclass(slots=True)
class StoreGame:
    """Una voce del catalogo, separata dalle promozioni gratuite."""

    store: str
    external_id: str
    namespace: str | None
    title: str
    description: str
    developer: str | None
    publisher: str | None
    image_url: str | None
    store_url: str
    product_slug: str | None
    offer_type: str | None
    release_date: datetime | None
    original_price: int | None
    discount_price: int | None
    currency_code: str | None
    currency_decimals: int
    fmt_original_price: str | None
    fmt_discount_price: str | None
    tags: list[str] = field(default_factory=list)
    categories: list[str] = field(default_factory=list)

    @property
    def internal_id(self) -> str:
        """Identificatore multi-store stabile per questa specifica listing."""
        return f"{self.store}:{self.namespace or 'unknown'}:{self.external_id}"

    def to_json_dict(self) -> dict[str, object]:
        return {
            "internal_id": self.internal_id,
            "store": self.store,
            "external_id": self.external_id,
            "namespace": self.namespace,
            "title": self.title,
            "description": self.description,
            "developer": self.developer,
            "publisher": self.publisher,
            "image_url": self.image_url,
            "store_url": self.store_url,
            "product_slug": self.product_slug,
            "offer_type": self.offer_type,
            "release_date": self.release_date.isoformat() if self.release_date else None,
            "original_price": self.original_price,
            "discount_price": self.discount_price,
            "currency_code": self.currency_code,
            "currency_decimals": self.currency_decimals,
            "fmt_original_price": self.fmt_original_price,
            "fmt_discount_price": self.fmt_discount_price,
            "tags": self.tags,
            "categories": self.categories,
        }
