from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_app_has_no_standalone_async_token():
    app = (ROOT / "docs" / "app.js").read_text(encoding="utf-8")
    assert "async \nfunction renderDiscoveryCards" not in app
    assert "\nasync \nfunction" not in app


def test_hotfix_cache_name_is_present():
    sw = (ROOT / "docs" / "service-worker.js").read_text(encoding="utf-8")
    assert "the-free-vault-v4-5-1-progress-rating-hotfix" in sw
