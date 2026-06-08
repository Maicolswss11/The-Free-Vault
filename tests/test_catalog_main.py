from __future__ import annotations

import json
from datetime import datetime, timezone

from poller.catalog_main import run


def payload():
    return {
        "data": {
            "Catalog": {
                "searchStore": {
                    "elements": [{
                        "id": "id-1",
                        "namespace": "ns",
                        "title": "Catalog Game",
                        "description": "",
                        "productSlug": "catalog-game",
                        "keyImages": [],
                        "categories": [],
                        "tags": [],
                        "price": {"totalPrice": {
                            "originalPrice": 1000,
                            "discountPrice": 1000,
                            "currencyCode": "EUR",
                            "currencyInfo": {"decimals": 2},
                            "fmtPrice": {"originalPrice": "10 €", "discountPrice": "10 €"},
                        }},
                    }],
                    "paging": {"count": 1, "total": 1},
                }
            }
        }
    }


def test_catalog_run_writes_output(tmp_path):
    output = tmp_path / "catalog.json"
    code = run(
        output_path=output,
        pages=[payload()],
        now=datetime(2026, 6, 8, tzinfo=timezone.utc),
    )
    assert code == 0
    data = json.loads(output.read_text(encoding="utf-8"))
    assert data["total"] == 1
    assert data["games"][0]["title"] == "Catalog Game"


def test_empty_catalog_preserves_existing_file(tmp_path):
    output = tmp_path / "catalog.json"
    output.write_text('{"old":true}', encoding="utf-8")
    code = run(output_path=output, pages=[])
    assert code == 1
    assert output.read_text(encoding="utf-8") == '{"old":true}'
