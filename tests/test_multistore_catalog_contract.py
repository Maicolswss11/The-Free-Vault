from __future__ import annotations

from poller.catalog_store import parse_catalog_element


def _element(**overrides):
    base = {
        "id": "offer-1",
        "namespace": "sandbox-1",
        "title": "Example Game Deluxe Edition",
        "description": "Description",
        "developerDisplayName": "Example Studio",
        "publisherDisplayName": "Example Studio",
        "offerType": "BASE_GAME",
        "productSlug": "example-game-deluxe",
        "releaseDate": "2026-01-01T00:00:00Z",
        "keyImages": [],
        "categories": [{"path": "games/edition/base"}],
        "tags": [],
        "price": {
            "totalPrice": {
                "originalPrice": 2999,
                "discountPrice": 2999,
                "currencyCode": "EUR",
                "currencyInfo": {"decimals": 2},
                "fmtPrice": {
                    "originalPrice": "29,99 €",
                    "discountPrice": "29,99 €",
                },
            }
        },
    }
    base.update(overrides)
    return base


def test_catalog_listing_has_canonical_and_store_ids():
    game = parse_catalog_element(_element())
    assert game is not None
    assert game.listing_id == "epic:sandbox-1:offer-1"
    assert game.internal_id == game.listing_id
    assert game.canonical_id.startswith("game:")
    assert game.canonical_title == "Example Game"
    assert game.edition_name == "Deluxe Edition"
    assert game.category_group == "base_game"
    assert game.release_year == 2026


def test_self_published_base_game_gets_conservative_indie_estimate():
    game = parse_catalog_element(_element())
    assert game is not None
    assert game.market_segment == "indie"
    assert game.market_segment_source == "self_published_estimate"
