from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_rating_buttons_do_not_rerender_game_page():
    app = (ROOT / "docs" / "app.js").read_text(encoding="utf-8")
    start = app.index("function renderRating(game, entry)")
    end = app.index("function renderPromotionTimeline", start)
    block = app[start:end]
    assert 'button.type = "button"' in block
    assert "renderRating(game, updatedEntry)" in block
    assert "renderGamePage()" not in block


def test_rating_click_updates_only_rating_state():
    app = (ROOT / "docs" / "app.js").read_text(encoding="utf-8")
    assert "const nextRating = selected === rating ? 0 : rating" in app
    assert "setLibraryEntry(game, { rating: nextRating })" in app


def test_v451_cache_is_versioned():
    worker = (ROOT / "docs" / "service-worker.js").read_text(encoding="utf-8")
    assert "the-free-vault-v4-5-1-progress-rating-hotfix" in worker
