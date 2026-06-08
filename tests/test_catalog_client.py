from __future__ import annotations

from unittest.mock import Mock

from poller.catalog_client import fetch_catalog_page


def test_catalog_client_falls_back_after_404():
    first = Mock()
    first.status_code = 404

    second = Mock()
    second.status_code = 200
    second.raise_for_status.return_value = None
    second.json.return_value = {
        "data": {
            "Catalog": {
                "searchStore": {
                    "elements": [],
                    "paging": {"count": 0, "total": 0},
                }
            }
        }
    }

    session = Mock()
    session.post.side_effect = [first, second]

    payload = fetch_catalog_page(start=0, count=1, session=session)

    assert payload["data"]["Catalog"]["searchStore"]["paging"]["total"] == 0
    assert session.post.call_count == 2
