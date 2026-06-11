from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_journal_routes_and_pages_exist():
    html = read("docs/index.html")
    app = read("docs/app.js")
    assert 'href="#/diary"' in html
    assert 'href="#/stats"' in html
    assert 'id="diary-page"' in html
    assert 'id="stats-page"' in html
    assert 'id="game-session-form"' in html
    assert 'id="game-page-save-progress"' in html
    assert 'diary: "diary"' in app
    assert 'stats: "stats"' in app
    assert 'renderDiaryPage' in app
    assert 'renderStatsPage' in app


def test_journal_module_scopes_data_and_supports_cloud():
    journal = read("docs/journal.js")
    assert 'tfv:${scope}:journal:v${STORAGE_VERSION}' in journal
    assert '.from("user_game_progress")' in journal
    assert '.from("game_diary_entries")' in journal
    assert 'user.id === expectedUserId' in journal
    assert 'saveProgress' in journal
    assert 'addEntry' in journal
    assert 'getPublicEntries' in journal
    assert 'summarize' in journal


def test_journal_schema_has_rls_and_privacy():
    sql = read("supabase/migrations/20260610_v42_game_journal.sql")
    assert "create table if not exists public.user_game_progress" in sql
    assert "create table if not exists public.game_diary_entries" in sql
    assert "add column if not exists show_diary" in sql
    assert "enable row level security" in sql
    assert 'visibility = \'public\'' in sql
    assert "coalesce(s.show_diary, true) = true" in sql
    assert "Users manage own progress" in sql
    assert "Users insert own diary entries" in sql


def test_privacy_and_backup_include_journal():
    auth = read("docs/auth.js")
    app = read("docs/app.js")
    assert "show_diary: true" in auth
    assert "show_diary: Boolean(nextSettings.show_diary)" in auth
    assert "journal: window.VaultJournal?.snapshot()" in app
    assert "window.VaultJournal?.importData(payload.journal)" in app


def test_service_worker_caches_journal_module():
    service_worker = read("docs/service-worker.js")
    assert 'the-free-vault-v4-3-mobile-navigation' in service_worker
    assert '"./journal.js"' in service_worker
