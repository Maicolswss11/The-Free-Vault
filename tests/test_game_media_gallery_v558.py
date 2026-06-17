from pathlib import Path

from poller.igdb_models import normalize_igdb_page

ROOT = Path(__file__).resolve().parents[1]
HTML = (ROOT / "docs/index.html").read_text(encoding="utf-8")
APP = (ROOT / "docs/app.js").read_text(encoding="utf-8")
CSS = (ROOT / "docs/interface-rebuild.css").read_text(encoding="utf-8")
WORKER = (ROOT / "docs/service-worker.js").read_text(encoding="utf-8")
MIGRATION = (ROOT / "supabase/migrations/20260617_v558_game_media_gallery.sql").read_text(encoding="utf-8")
IGDB_CLIENT = (ROOT / "poller/igdb_client.py").read_text(encoding="utf-8")


def test_igdb_media_are_normalized_into_master_metadata():
    batch = normalize_igdb_page([{
        "id": 1,
        "name": "Media Test",
        "screenshots": [{"image_id": "sc123", "width": 1920, "height": 1080}],
        "artworks": [{"image_id": "ar123", "width": 1920, "height": 1080}],
        "videos": [{"name": "Launch Trailer", "video_id": "abcDEF12345"}],
    }])

    metadata = batch.games[0]["metadata"]
    assert metadata["screenshots"][0]["url"].endswith("/t_screenshot_huge/sc123.jpg")
    assert metadata["artworks"][0]["thumbnail_url"].endswith("/t_screenshot_med/ar123.jpg")
    assert metadata["videos"][0]["embed_url"].endswith("/embed/abcDEF12345")


def test_igdb_query_requests_screenshots_artworks_and_videos():
    for marker in (
        '"screenshots.image_id"',
        '"artworks.image_id"',
        '"videos.video_id"',
    ):
        assert marker in IGDB_CLIENT


def test_catalog_read_model_exposes_media_without_catalog_duplication():
    for marker in (
        "metadata -> 'screenshots'",
        "metadata -> 'artworks'",
        "metadata -> 'videos'",
        "'hero_image_url'",
        "'media_count'",
    ):
        assert marker in MIGRATION
    assert "alter table public.catalog_games" not in MIGRATION.lower()


def test_game_page_has_real_media_gallery_and_lightbox():
    for marker in (
        'id="game-media-panel"',
        'id="game-media-gallery"',
        'id="game-media-dialog"',
        'id="game-media-nav"',
    ):
        assert marker in HTML
    for marker in (
        "normalizedGameMedia(game)",
        "renderGameMedia(game)",
        "youtube-nocookie.com/embed",
        "ui.gameMediaDialog.showModal()",
        'window.VaultCatalog.getGame(state.route.params.key, { force: true })',
    ):
        assert marker in APP
    assert "v5.5.8 — Game media gallery" in CSS


def test_v558_cache_name_is_updated():
    assert 'const CACHE_NAME = "ludograph-v5-5-8-game-media-gallery"' in WORKER
