"""Modelli normalizzati del catalogo multi-store."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime


@dataclass(slots=True)
class StoreGame:
    """Una listing di store collegabile a un gioco canonico."""

    store: str
    external_id: str
    namespace: str | None
    title: str
    canonical_title: str
    canonical_id: str
    match_key: str
    listing_id: str
    description: str
    developer: str | None
    publisher: str | None
    image_url: str | None
    store_url: str
    product_slug: str | None
    offer_type: str | None
    category_group: str
    edition_name: str | None
    market_segment: str
    market_segment_source: str
    release_date: datetime | None
    release_year: int | None
    original_price: int | None
    discount_price: int | None
    currency_code: str | None
    currency_decimals: int
    fmt_original_price: str | None
    fmt_discount_price: str | None
    platforms: list[str] = field(default_factory=lambda: ["pc"])
    genres: list[str] = field(default_factory=list)
    tags: list[str] = field(default_factory=list)
    categories: list[str] = field(default_factory=list)

    @property
    def internal_id(self) -> str:
        """Alias storico della listing, mantenuto per compatibilità."""
        return self.listing_id

    def to_json_dict(self) -> dict[str, object]:
        return {
            "canonical_id": self.canonical_id,
            "canonical_title": self.canonical_title,
            "match_key": self.match_key,
            "listing_id": self.listing_id,
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
            "category_group": self.category_group,
            "edition_name": self.edition_name,
            "market_segment": self.market_segment,
            "market_segment_source": self.market_segment_source,
            "release_date": self.release_date.isoformat() if self.release_date else None,
            "release_year": self.release_year,
            "original_price": self.original_price,
            "discount_price": self.discount_price,
            "currency_code": self.currency_code,
            "currency_decimals": self.currency_decimals,
            "fmt_original_price": self.fmt_original_price,
            "fmt_discount_price": self.fmt_discount_price,
            "platforms": self.platforms,
            "genres": self.genres,
            "tags": self.tags,
            "categories": self.categories,
        }
