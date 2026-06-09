from __future__ import annotations

import json
from datetime import datetime, timezone
from unittest.mock import Mock

from poller.steam_catalog_main import run
from poller.steam_catalog_store import parse_steam_app, parse_steam_page
from poller.steam_client import STEAM_APP_LIST_URL, fetch_app_list_page


def test_parse_steam_app_creates_multistore_listing():
    game = parse_steam_app({"appid": 123, "name": "Control Ultimate Edition"})
    assert game is not None
    assert game.store == "steam"
    assert game.external_id == "123"
    assert game.listing_id == "steam:123"
    assert game.canonical_title == "Control"
    assert game.edition_name == "Ultimate Edition"
    assert game.match_key.startswith("title:")
    assert game.store_url.endswith("/app/123/")


def test_parse_steam_page_reads_response_wrapper():
    games = parse_steam_page({
        "response": {
            "apps": [
                {"appid": 10, "name": "Game A"},
                {"appid": 0, "name": "Invalid"},
            ]
        }
    })
    assert [game.title for game in games] == ["Game A"]


def test_steam_client_uses_input_json():
    response = Mock()
    response.raise_for_status.return_value = None
    response.json.return_value = {"response": {"apps": [], "have_more_results": False}}
    session = Mock()
    session.get.return_value = response

    payload = fetch_app_list_page(
        api_key="test-key",
        last_appid=10,
        max_results=100,
        session=session,
    )

    assert payload["response"]["apps"] == []
    params = session.get.call_args.kwargs["params"]
    assert params["key"] == "test-key"
    decoded = json.loads(params["input_json"])
    assert decoded["last_appid"] == 10
    assert decoded["max_results"] == 100


def test_steam_catalog_run_writes_file(tmp_path):
    output = tmp_path / "steam-catalog.json"
    code = run(
        output_path=output,
        pages=[{
            "response": {
                "apps": [{"appid": 77, "name": "Steam Game"}],
                "have_more_results": False,
            }
        }],
        now=datetime(2026, 6, 10, tzinfo=timezone.utc),
    )
    assert code == 0
    payload = json.loads(output.read_text(encoding="utf-8"))
    assert payload["store"] == "steam"
    assert payload["games"][0]["listing_id"] == "steam:77"


def test_steam_catalog_uses_public_web_api_host():
    assert STEAM_APP_LIST_URL == (
        "https://api.steampowered.com/IStoreService/GetAppList/v1/"
    )
