from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INDEX = (ROOT / "docs" / "index.html").read_text(encoding="utf-8")
APP = (ROOT / "docs" / "app.js").read_text(encoding="utf-8")
CSS = (ROOT / "docs" / "interface-rebuild.css").read_text(encoding="utf-8")
WORKER = (ROOT / "docs" / "service-worker.js").read_text(encoding="utf-8")


def test_profile_hero_contains_truthful_identity_and_summary():
    assert 'class="profile-avatar-shell"' in INDEX
    assert 'id="profile-level-chip"' not in INDEX
    assert 'Collezionista' not in INDEX
    assert 'id="profile-verified-badge"' in INDEX
    assert 'class="profile-hero-summary"' in INDEX
    assert 'id="profile-hero-hours"' in INDEX
    assert 'id="profile-member-since-text"' in INDEX


def test_profile_metrics_match_mockup_information_architecture():
    for element_id in (
        "profile-stat-library",
        "profile-stat-completed",
        "profile-stat-hours",
        "profile-stat-streak",
        "profile-stat-rating",
        "profile-stat-played",
    ):
        assert f'id="{element_id}"' in INDEX
    assert "function profileStreakDays" in APP
    assert "averageRating" in APP
    assert "playedPercent" in APP


def test_profile_dashboard_uses_real_icons_and_responsive_layouts():
    assert 'profile-activity-row is-' in APP
    assert 'class="profile-genre-icon"' in APP
    assert 'class="profile-hub-icon"' in INDEX
    assert 'body[data-route="profile"] .profile-dashboard-grid' in CSS
    assert '@media (max-width: 820px)' in CSS
    assert '@media (max-width: 560px)' in CSS
    assert 'grid-template-columns: repeat(2, minmax(0, 1fr));' in CSS


def test_profile_patch_updates_pwa_cache():
    assert 'const CACHE_NAME = "ludograph-v5-5-17-editorial-canonical-variants"' in WORKER
