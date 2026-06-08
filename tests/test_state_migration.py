from __future__ import annotations

import json

from poller.state_store import load_state


def test_legacy_notification_keys_are_migrated(tmp_path):
    path = tmp_path / "state.json"
    legacy = "game|2026-06-01T00:00:00+00:00|2026-06-08T00:00:00+00:00"
    path.write_text(
        json.dumps(
            {
                "notified_ids": [legacy],
                "expiry_reminded_ids": [legacy],
                "last_run": None,
            }
        ),
        encoding="utf-8",
    )

    state = load_state(path)

    assert f"upcoming|{legacy}" in state.notified_ids
    assert f"expiry|{legacy}" in state.expiry_reminded_ids
