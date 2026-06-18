from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HTML = (ROOT / "docs/index.html").read_text(encoding="utf-8")
APP = (ROOT / "docs/app.js").read_text(encoding="utf-8")
CSS = (ROOT / "docs/interface-rebuild.css").read_text(encoding="utf-8")
WORKER = (ROOT / "docs/service-worker.js").read_text(encoding="utf-8")


def test_game_page_has_cinematic_hero_and_truthful_summaries():
    for marker in (
        'id="game-community-rating-panel"',
        'id="game-community-rating-distribution"',
        'id="game-summary-progress-ring"',
        'id="game-summary-session-count"',
        'id="game-summary-list-count"',
        'id="game-summary-rating-stars"',
        'class="game-detail-side-rail"',
    ):
        assert marker in HTML


def test_game_page_uses_real_personal_and_community_data():
    for marker in (
        "journalEntries.length.toLocaleString",
        "Object.values(state.lists || {})",
        "renderCommunityGameRating(reviews)",
        "updatePersonalGameRatingSummary(entry?.rating || 0)",
        "gameDetailArtwork(game)",
    ):
        assert marker in APP


def test_game_page_has_dedicated_desktop_and_mobile_layouts():
    assert "v5.5.7 — Game page fidelity" in CSS
    assert 'body[data-route="game"] .game-detail-shell' in CSS
    assert '@media (max-width: 720px)' in CSS
    assert 'body[data-route="game"] .game-detail-content { display: contents; }' in CSS


def test_v557_cache_name_is_updated():
    assert 'const CACHE_NAME = "ludograph-v5-5-11-franchise-final-polish"' in WORKER
