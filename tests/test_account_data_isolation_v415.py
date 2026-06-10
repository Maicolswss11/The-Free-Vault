from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_personal_storage_is_scoped_by_user():
    app = (ROOT / "docs" / "app.js").read_text(encoding="utf-8")
    for value in (
        'const GUEST_LIBRARY_KEY = "tfv:guest:library:v1"',
        'const USER_STORAGE_PREFIX = "tfv:user:"',
        "function personalStorageKeys",
        "function switchPersonalStorage",
        "activeStorageUserId",
        "canSyncActiveAccount",
    ):
        assert value in app

    assert 'const LIBRARY_KEY = "the-free-vault-library-v3"' not in app
    assert 'const LISTS_KEY = "the-free-vault-lists-v1"' not in app


def test_auth_switch_cancels_old_push_and_reloads_scoped_state():
    app = (ROOT / "docs" / "app.js").read_text(encoding="utf-8")
    cloud = (ROOT / "docs" / "cloud-sync.js").read_text(encoding="utf-8")

    assert "window.VaultCloud?.cancelScheduledPush()" in app
    assert "switchPersonalStorage(nextUserId)" in app
    assert "personalStorageGeneration" in app
    assert "expectedUserId" in cloud
    assert "assertCurrentUser" in cloud
    assert "librarySnapshot" in cloud
    assert "listsSnapshot" in cloud
    assert "cancelScheduledPush" in cloud


def test_imported_lists_are_rekeyed_to_avoid_cross_account_pk_collisions():
    app = (ROOT / "docs" / "app.js").read_text(encoding="utf-8")
    assert "const id = crypto.randomUUID()" in app
    assert "result[id]" in app


def test_service_worker_does_not_intercept_external_cdn_requests():
    worker = (ROOT / "docs" / "service-worker.js").read_text(encoding="utf-8")
    assert "if (url.origin !== self.location.origin)" in worker

    assert 'the-free-vault-v4-2-game-journal' in worker
