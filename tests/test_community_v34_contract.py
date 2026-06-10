from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_community_routes_and_pages_exist():
    html = (ROOT / "docs" / "index.html").read_text(encoding="utf-8")
    app = (ROOT / "docs" / "app.js").read_text(encoding="utf-8")

    for page_id in (
        "feed-page",
        "explore-page",
        "notifications-page",
        "notification-button",
        "public-profile-follow",
        "shared-list-like",
        "shared-list-comments",
    ):
        assert f'id="{page_id}"' in html

    for route_name in ("feed", "explore", "notifications"):
        assert f'{route_name}: "{route_name}"' in app

    for function_name in (
        "renderFeedPage",
        "renderExplorePage",
        "renderNotificationsPage",
        "renderSharedListSocial",
        "refreshNotificationCount",
    ):
        assert function_name in app


def test_social_client_exposes_v34_features():
    social = (ROOT / "docs" / "social.js").read_text(encoding="utf-8")

    for function_name in (
        "followUser",
        "unfollowUser",
        "getActivityFeed",
        "exploreUsers",
        "toggleReviewLike",
        "toggleListLike",
        "getComments",
        "addComment",
        "getNotifications",
        "markAllNotificationsRead",
    ):
        assert function_name in social

    for table_name in (
        "user_follows",
        "review_likes",
        "list_likes",
        "content_comments",
        "activities",
        "user_notifications",
    ):
        assert table_name in social


def test_v34_migration_has_rls_triggers_and_notifications():
    sql = (
        ROOT
        / "supabase"
        / "migrations"
        / "20260610160000_community_v34.sql"
    ).read_text(encoding="utf-8").lower()

    for table_name in (
        "public.user_follows",
        "public.review_likes",
        "public.list_likes",
        "public.content_comments",
        "public.activities",
        "public.user_notifications",
    ):
        assert f"create table if not exists {table_name}" in sql
        assert f"alter table {table_name} enable row level security" in sql

    assert "create trigger user_follows_after_insert_v34" in sql
    assert "create trigger review_likes_after_insert_v34" in sql
    assert "create trigger list_likes_after_insert_v34" in sql
    assert "create trigger content_comments_after_insert_v34" in sql
    assert "get_follow_counts" in sql
    assert "can_view_social_target" in sql


def test_v34_service_worker_cache_name():
    worker = (ROOT / "docs" / "service-worker.js").read_text(encoding="utf-8")
    assert 'the-free-vault-v4-1-catalog-performance' in worker
