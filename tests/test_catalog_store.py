from __future__ import annotations

from poller.catalog_store import merge_catalog, parse_catalog_element, parse_catalog_page


def element(**overrides):
    base = {
        "id": "offer-1",
        "namespace": "sandbox-1",
        "title": "Game One",
        "description": "Description",
        "developerDisplayName": "Studio",
        "publisherDisplayName": "Publisher",
        "offerType": "BASE_GAME",
        "productSlug": "game-one",
        "releaseDate": "2026-01-01T00:00:00Z",
        "keyImages": [{"type": "OfferImageWide", "url": "https://example.com/a.jpg"}],
        "categories": [{"path": "games/edition/base"}],
        "tags": [{"id": "123"}],
        "price": {
            "totalPrice": {
                "originalPrice": 1999,
                "discountPrice": 999,
                "currencyCode": "EUR",
                "currencyInfo": {"decimals": 2},
                "fmtPrice": {
                    "originalPrice": "19,99 €",
                    "discountPrice": "9,99 €",
                },
            }
        },
    }
    base.update(overrides)
    return base


def test_parse_catalog_element():
    game = parse_catalog_element(element())
    assert game is not None
    assert game.internal_id == "epic:sandbox-1:offer-1"
    assert game.title == "Game One"
    assert game.developer == "Studio"
    assert game.discount_price == 999
    assert game.store_url.endswith("/it/p/game-one")


def test_parse_catalog_page_ignores_invalid_elements():
    payload = {
        "data": {
            "Catalog": {
                "searchStore": {
                    "elements": [element(), {"id": "bad"}]
                }
            }
        }
    }
    games = parse_catalog_page(payload)
    assert len(games) == 1


def test_merge_catalog_deduplicates():
    first = parse_catalog_element(element(description=""))
    richer = parse_catalog_element(element(description="Full", publisherDisplayName="Pub"))
    merged = merge_catalog([first, richer])
    assert len(merged) == 1
    assert merged[0].description == "Full"
