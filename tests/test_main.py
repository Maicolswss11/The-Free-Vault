from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

from poller.main import run
from poller.models import GamePromotion
from poller.state_store import load_state


NOW = datetime(2026, 6, 8, 12, 0, tzinfo=timezone.utc)


def make_payload(*, upcoming: bool = False, end_hours: int = 168) -> dict:
    bucket = "upcomingPromotionalOffers" if upcoming else "promotionalOffers"
    start = NOW + timedelta(hours=1) if upcoming else NOW - timedelta(hours=1)
    end = NOW + timedelta(hours=end_hours)
    return {
        "data": {
            "Catalog": {
                "searchStore": {
                    "elements": [
                        {
                            "id": "game-1",
                            "namespace": "ns",
                            "title": "Test Game",
                            "description": "Description",
                            "offerType": "BASE_GAME",
                            "productSlug": "test-game",
                            "keyImages": [
                                {"type": "OfferImageWide", "url": "https://example.com/game.jpg"}
                            ],
                            "price": {
                                "totalPrice": {
                                    "originalPrice": 1999,
                                    "discountPrice": 0,
                                    "currencyCode": "EUR",
                                    "currencyInfo": {"decimals": 2},
                                    "fmtPrice": {"originalPrice": "19,99 €"},
                                }
                            },
                            "promotions": {
                                "promotionalOffers": [],
                                "upcomingPromotionalOffers": [],
                                bucket: [
                                    {
                                        "promotionalOffers": [
                                            {
                                                "startDate": start.isoformat(),
                                                "endDate": end.isoformat(),
                                                "discountSetting": {"discountPercentage": 0},
                                            }
                                        ]
                                    }
                                ],
                            },
                        }
                    ]
                }
            }
        }
    }


class FakeNotifier:
    def __init__(self, *, enabled: bool = True, result: bool = True) -> None:
        self.enabled = enabled
        self.result = result
        self.calls: list[dict] = []

    def send(self, **kwargs) -> bool:
        self.calls.append(kwargs)
        return self.result


def test_new_current_notification_success(tmp_path):
    notifier = FakeNotifier()
    state_path = tmp_path / "state.json"
    games_path = tmp_path / "games.json"

    code = run(
        now=NOW,
        fetcher=lambda: make_payload(),
        notifier=notifier,
        state_path=state_path,
        games_path=games_path,
    )

    assert code == 0
    assert len(notifier.calls) == 1
    state = load_state(state_path)
    assert any(key.startswith("current|") for key in state.notified_ids)


def test_new_upcoming_notification(tmp_path):
    notifier = FakeNotifier()

    code = run(
        now=NOW,
        fetcher=lambda: make_payload(upcoming=True),
        notifier=notifier,
        state_path=tmp_path / "state.json",
        games_path=tmp_path / "games.json",
    )

    assert code == 0
    assert len(notifier.calls) == 1
    state = load_state(tmp_path / "state.json")
    assert any(key.startswith("upcoming|") for key in state.notified_ids)


def test_failed_notification_is_not_marked(tmp_path):
    notifier = FakeNotifier(enabled=True, result=False)

    code = run(
        now=NOW,
        fetcher=lambda: make_payload(),
        notifier=notifier,
        state_path=tmp_path / "state.json",
        games_path=tmp_path / "games.json",
    )

    assert code == 0
    assert load_state(tmp_path / "state.json").notified_ids == set()


def test_disabled_notifier_marks_event_handled(tmp_path):
    notifier = FakeNotifier(enabled=False, result=False)

    code = run(
        now=NOW,
        fetcher=lambda: make_payload(),
        notifier=notifier,
        state_path=tmp_path / "state.json",
        games_path=tmp_path / "games.json",
    )

    assert code == 0
    assert any(
        key.startswith("current|")
        for key in load_state(tmp_path / "state.json").notified_ids
    )


def test_expiry_reminder_within_24_hours(tmp_path):
    notifier = FakeNotifier()
    state_path = tmp_path / "state.json"

    code = run(
        now=NOW,
        fetcher=lambda: make_payload(end_hours=12),
        notifier=notifier,
        state_path=state_path,
        games_path=tmp_path / "games.json",
    )

    assert code == 0
    assert len(notifier.calls) == 2
    assert any(
        key.startswith("expiry|")
        for key in load_state(state_path).expiry_reminded_ids
    )


def test_expiry_reminder_not_duplicated(tmp_path):
    notifier = FakeNotifier()
    state_path = tmp_path / "state.json"
    games_path = tmp_path / "games.json"

    assert run(
        now=NOW,
        fetcher=lambda: make_payload(end_hours=12),
        notifier=notifier,
        state_path=state_path,
        games_path=games_path,
    ) == 0

    notifier.calls.clear()

    assert run(
        now=NOW + timedelta(minutes=10),
        fetcher=lambda: make_payload(end_hours=12),
        notifier=notifier,
        state_path=state_path,
        games_path=games_path,
    ) == 0

    assert notifier.calls == []


def test_fetch_failure_does_not_overwrite_games_json(tmp_path):
    games_path = tmp_path / "games.json"
    games_path.write_text('{"preserve": true}', encoding="utf-8")

    def broken_fetcher():
        raise RuntimeError("network down")

    code = run(
        now=NOW,
        fetcher=broken_fetcher,
        notifier=FakeNotifier(),
        state_path=tmp_path / "state.json",
        games_path=games_path,
    )

    assert code == 1
    assert games_path.read_text(encoding="utf-8") == '{"preserve": true}'


def test_already_notified_is_skipped(tmp_path):
    notifier = FakeNotifier()
    state_path = tmp_path / "state.json"
    games_path = tmp_path / "games.json"

    assert run(
        now=NOW,
        fetcher=lambda: make_payload(),
        notifier=notifier,
        state_path=state_path,
        games_path=games_path,
    ) == 0

    notifier.calls.clear()

    assert run(
        now=NOW + timedelta(minutes=5),
        fetcher=lambda: make_payload(),
        notifier=notifier,
        state_path=state_path,
        games_path=games_path,
    ) == 0

    assert notifier.calls == []


def test_last_run_is_updated(tmp_path):
    state_path = tmp_path / "state.json"

    assert run(
        now=NOW,
        fetcher=lambda: make_payload(),
        notifier=FakeNotifier(enabled=False),
        state_path=state_path,
        games_path=tmp_path / "games.json",
    ) == 0

    assert load_state(state_path).last_run == NOW.isoformat()


def test_invalid_payload_returns_nonzero(tmp_path):
    def invalid_fetcher():
        raise ValueError("bad payload")

    assert run(
        now=NOW,
        fetcher=invalid_fetcher,
        notifier=FakeNotifier(),
        state_path=tmp_path / "state.json",
        games_path=tmp_path / "games.json",
    ) == 1
