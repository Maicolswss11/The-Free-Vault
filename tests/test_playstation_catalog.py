from __future__ import annotations

import json
from datetime import datetime, timezone
from unittest.mock import Mock

from poller.playstation_catalog_main import run
from poller.playstation_catalog_store import (
    merge_playstation_catalog,
    parse_playstation_page,
    parse_playstation_product,
)
from poller.playstation_client import (
    PLAYSTATION_GRAPHQL_URL,
    PLAYSTATION_PS4_CATEGORY_ID,
    PLAYSTATION_PS5_CATEGORY_ID,
    fetch_category_page,
    iter_category_pages,
)


def _product(**overrides):
    base = {
        "id": "EP9000-PPSA07412_00-GOWRAGNAROK00000",
        "name": "God of War Ragnarök Digital Deluxe Edition (PS4 & PS5)",
        "platforms": ["PS4", "PS5"],
        "storeDisplayClassification": "PREMIUM_EDITION",
        "publisherName": "Sony Interactive Entertainment",
        "releaseDate": "2022-11-09T00:00:00Z",
        "media": [
            {"role": "BACKGROUND", "url": "https://example.test/background.jpg"},
            {"role": "MASTER", "url": "https://example.test/master.jpg"},
        ],
        "price": {
            "basePrice": "€89,99",
            "discountedPrice": "€69,99",
            "currencyCode": "EUR",
        },
    }
    base.update(overrides)
    return base


def _page(products, *, offset=0, size=None, total=None):
    size = len(products) if size is None else size
    total = len(products) if total is None else total
    return {
        "data": {
            "categoryGridRetrieve": {
                "products": products,
                "pageInfo": {
                    "offset": offset,
                    "size": size,
                    "totalCount": total,
                },
            }
        }
    }


def test_parse_playstation_product_creates_multistore_listing():
    game = parse_playstation_product(_product())

    assert game is not None
    assert game.store == "playstation"
    assert game.listing_id == "playstation:EP9000-PPSA07412_00-GOWRAGNAROK00000"
    assert game.external_id == "EP9000-PPSA07412_00-GOWRAGNAROK00000"
    assert game.canonical_title == "God of War Ragnarök"
    assert game.edition_name == "Digital Deluxe Edition"
    assert game.category_group == "edition"
    assert game.platforms == ["ps4", "ps5"]
    assert game.release_year == 2022
    assert game.original_price == 8999
    assert game.discount_price == 6999
    assert game.currency_code == "EUR"
    assert game.image_url == "https://example.test/master.jpg"
    assert game.store_url.endswith("/it-it/product/EP9000-PPSA07412_00-GOWRAGNAROK00000")


def test_italian_edition_prefix_is_canonicalized():
    game = parse_playstation_product(_product(
        id="UP6312-PPSA31381_00-0202050640964065",
        name="Edizione Premium di Fable",
        platforms=["PS5"],
        storeDisplayClassification="PREMIUM_EDITION",
    ))

    assert game is not None
    assert game.canonical_title == "Fable"
    assert game.edition_name == "Premium Edition"
    assert game.match_key.startswith("title:")


def test_add_ons_are_excluded_by_default_and_can_be_enabled():
    product = _product(
        id="EP9000-DLC000000000001",
        name="God of War Ragnarök: Valhalla",
        storeDisplayClassification="ADD_ON",
    )

    assert parse_playstation_product(product) is None
    included = parse_playstation_product(product, include_add_ons=True)
    assert included is not None
    assert included.category_group == "dlc"
    assert included.offer_type == "DLC"


def test_parse_page_and_merge_deduplicate_ps4_ps5_overlap():
    product = _product()
    games = parse_playstation_page(_page([product, product]))
    merged = merge_playstation_catalog(games)

    assert len(games) == 2
    assert len(merged) == 1


def test_client_uses_graphql_persisted_query_and_locale_header():
    response = Mock()
    response.status_code = 200
    response.json.return_value = _page([])
    response.text = ""
    session = Mock()
    session.get.return_value = response

    payload = fetch_category_page(
        PLAYSTATION_PS5_CATEGORY_ID,
        offset=1000,
        size=1000,
        locale="it-IT",
        query_hash="abc123",
        session=session,
    )

    assert payload["data"]["categoryGridRetrieve"]["products"] == []
    call = session.get.call_args
    assert call.args[0] == PLAYSTATION_GRAPHQL_URL
    assert call.kwargs["headers"]["x-psn-store-locale-override"] == "it-IT"
    variables = json.loads(call.kwargs["params"]["variables"])
    extensions = json.loads(call.kwargs["params"]["extensions"])
    assert variables["id"] == PLAYSTATION_PS5_CATEGORY_ID
    assert variables["pageArgs"] == {"size": 1000, "offset": 1000}
    assert extensions["persistedQuery"]["sha256Hash"] == "abc123"


def test_client_falls_back_to_next_query_hash():
    failed = Mock()
    failed.status_code = 400
    failed.json.return_value = {"errors": [{"message": "PersistedQueryNotFound"}]}
    failed.text = "PersistedQueryNotFound"
    success = Mock()
    success.status_code = 200
    success.json.return_value = _page([])
    success.text = ""
    session = Mock()
    session.get.side_effect = [failed, success]

    payload = fetch_category_page(
        PLAYSTATION_PS4_CATEGORY_ID,
        query_hash="bad-hash,good-hash",
        session=session,
    )

    assert payload["data"]["categoryGridRetrieve"]["products"] == []
    assert session.get.call_count == 2


def test_iter_category_pages_advances_with_page_info():
    first = Mock()
    first.status_code = 200
    first.json.return_value = _page([_product(id="A")], offset=0, size=1, total=2)
    first.text = ""
    second = Mock()
    second.status_code = 200
    second.json.return_value = _page([_product(id="B")], offset=1, size=1, total=2)
    second.text = ""
    session = Mock()
    session.get.side_effect = [first, second]

    pages = list(iter_category_pages(
        category_ids=[PLAYSTATION_PS5_CATEGORY_ID],
        page_size=1,
        query_hash="hash",
        delay_seconds=0,
        session=session,
    ))

    assert len(pages) == 2
    second_variables = json.loads(session.get.call_args_list[1].kwargs["params"]["variables"])
    assert second_variables["pageArgs"]["offset"] == 1


def test_playstation_catalog_run_writes_file(tmp_path):
    output = tmp_path / "playstation-catalog.json"
    code = run(
        output_path=output,
        pages=[_page([_product()])],
        now=datetime(2026, 6, 14, tzinfo=timezone.utc),
    )

    assert code == 0
    payload = json.loads(output.read_text(encoding="utf-8"))
    assert payload["store"] == "playstation"
    assert payload["total"] == 1
    assert payload["games"][0]["store"] == "playstation"


def test_empty_playstation_catalog_preserves_existing_file(tmp_path):
    output = tmp_path / "playstation-catalog.json"
    output.write_text('{"old":true}', encoding="utf-8")

    code = run(output_path=output, pages=[])

    assert code == 1
    assert output.read_text(encoding="utf-8") == '{"old":true}'
