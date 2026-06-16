from __future__ import annotations

from pathlib import Path
from unittest.mock import Mock

from poller.igdb_client import API_BASE_URL, IGDBClient, IGDBClientError, TOKEN_URL
from poller.igdb_master_main import run
from poller.igdb_models import normalize_igdb_page

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def sample_game(game_id: int = 19560) -> dict:
    return {
        "id": game_id,
        "name": "God of War",
        "slug": "god-of-war",
        "summary": "Kratos affronta gli dèi dell'Olimpo.",
        "storyline": "Una storia di vendetta.",
        "first_release_date": 1112832000,
        "updated_at": 1710000000,
        "checksum": "game-checksum",
        "url": "https://www.igdb.com/games/god-of-war",
        "rating": 91.2,
        "rating_count": 500,
        "game_type": {"id": 0, "type": "Main Game"},
        "cover": {"image_id": "co1tmu"},
        "genres": [{"name": "Hack and slash/Beat 'em up"}, {"name": "Adventure"}],
        "alternative_names": [{"id": 77, "name": "God of War (2005)"}],
        "platforms": [
            {
                "id": 8,
                "name": "PlayStation 2",
                "slug": "ps2",
                "abbreviation": "PS2",
                "generation": 6,
                "checksum": "platform-checksum",
                "url": "https://www.igdb.com/platforms/ps2",
            }
        ],
        "involved_companies": [
            {"developer": True, "publisher": False, "company": {"name": "SCE Santa Monica Studio"}},
            {"developer": False, "publisher": True, "company": {"name": "Sony Computer Entertainment"}},
        ],
        "release_dates": [
            {
                "id": 501,
                "date": 1112832000,
                "human": "Apr 07, 2005",
                "y": 2005,
                "m": 4,
                "d": 7,
                "date_format": 0,
                "release_region": 8,
                "platform": {"id": 8, "name": "PlayStation 2", "slug": "ps2", "abbreviation": "PS2"},
                "checksum": "release-checksum",
            }
        ],
        "external_games": [
            {
                "id": 900,
                "uid": "SCES-53133",
                "url": "https://store.playstation.com/example",
                "external_game_source": {"id": 36, "name": "PlayStation Store US"},
                "platform": {"id": 8},
            }
        ],
    }


def test_igdb_normalization_creates_master_release_platform_and_projection():
    batch = normalize_igdb_page([sample_game()])

    assert len(batch.games) == 1
    game = batch.games[0]
    assert game["id"] == "igdb:19560"
    assert game["title"] == "God of War"
    assert game["first_release_date"] == "2005-04-07"
    assert game["developer"] == "SCE Santa Monica Studio"
    assert game["publisher"] == "Sony Computer Entertainment"
    assert game["cover_url"].endswith("/t_cover_big_2x/co1tmu.jpg")
    assert game["game_type"] == "main_game"

    assert batch.platforms[0]["id"] == "igdb:8"
    assert batch.platforms[0]["family"] == "playstation"
    assert batch.releases[0]["platform_id"] == "igdb:8"
    assert batch.releases[0]["region"] == "worldwide"
    assert batch.external_ids[0]["provider"] == "igdb"
    assert any(item["provider"] == "playstation" for item in batch.external_ids)

    projection = batch.projections[0]
    assert projection["match_key"] == "master:igdb:19560"
    assert projection["canonical_id"] == "igdb:19560"
    assert projection["platforms"] == ["ps2"]
    assert projection["offer_type"] == "IGDB_MASTER"


def test_igdb_client_authenticates_and_uses_cursor_query():
    auth_response = Mock()
    auth_response.raise_for_status.return_value = None
    auth_response.json.return_value = {"access_token": "token", "expires_in": 3600}

    games_response = Mock()
    games_response.status_code = 200
    games_response.raise_for_status.return_value = None
    games_response.json.return_value = [sample_game(20000)]

    session = Mock()
    session.post.side_effect = [auth_response, games_response]
    client = IGDBClient("client", "secret", session=session, request_interval=0)

    records = client.fetch_games_after(19999, limit=25)

    assert records[0]["id"] == 20000
    auth_call = session.post.call_args_list[0]
    assert auth_call.args[0] == TOKEN_URL
    assert auth_call.kwargs["params"]["grant_type"] == "client_credentials"

    games_call = session.post.call_args_list[1]
    assert games_call.args[0] == f"{API_BASE_URL}/games"
    assert games_call.kwargs["headers"]["Client-ID"] == "client"
    assert games_call.kwargs["headers"]["Authorization"] == "Bearer token"
    query = games_call.kwargs["data"].decode("utf-8")
    assert "where id > 19999 & version_parent = null" in query
    assert "sort id asc" in query
    assert "limit 25" in query
    assert "game_status.status" in query
    assert "game_status.name" not in query


def test_igdb_client_reports_400_body_without_retrying():
    auth_response = Mock()
    auth_response.raise_for_status.return_value = None
    auth_response.json.return_value = {"access_token": "token", "expires_in": 3600}

    games_response = Mock()
    games_response.status_code = 400
    games_response.text = 'Invalid field name "name" in game_status'

    session = Mock()
    session.post.side_effect = [auth_response, games_response]
    client = IGDBClient("client", "secret", session=session, request_interval=0)

    try:
        client.fetch_games_after(0, limit=25)
    except IGDBClientError as exc:
        message = str(exc)
    else:
        raise AssertionError("Il client avrebbe dovuto rifiutare la query non valida")

    assert 'Invalid field name "name" in game_status' in message
    assert session.post.call_count == 2


class FakeSource:
    def __init__(self):
        self.cursors: list[int] = []

    def fetch_games_after(self, after_id: int, *, limit: int) -> list[dict]:
        self.cursors.append(after_id)
        if after_id == 0:
            return [sample_game(10), sample_game(20)]
        if after_id == 20:
            return [sample_game(30)]
        return []


class FakeSink:
    def __init__(self):
        self.upserts: list[tuple[int, int]] = []
        self.finished: dict | None = None
        self.failed: str | None = None

    def begin(self, *, run_id: str, reset_cursor: bool = False) -> dict[str, object]:
        return {"cursor_id": 0}

    def upsert(self, batch, *, run_id: str, cursor_id: int) -> dict[str, object]:
        self.upserts.append((len(batch.games), cursor_id))
        return {"games": len(batch.games), "cursor_id": cursor_id}

    def finish(self, *, run_id: str, complete: bool, metadata=None) -> dict[str, object]:
        self.finished = {"complete": complete, "metadata": metadata}
        return self.finished

    def fail(self, *, run_id: str, error_message: str) -> None:
        self.failed = error_message


def test_master_import_is_cursor_based_and_finishes_on_short_page():
    source = FakeSource()
    sink = FakeSink()

    code = run(client=source, sink=sink, page_size=2, max_pages=5, reset_cursor=False)

    assert code == 0
    assert source.cursors == [0, 20]
    assert sink.upserts == [(2, 20), (1, 30)]
    assert sink.finished is not None
    assert sink.finished["complete"] is True
    assert sink.finished["metadata"]["normalized_games"] == 3
    assert sink.failed is None


def test_master_schema_is_store_independent_and_backward_compatible():
    migration = read("supabase/migrations/20260614_v50_universal_game_database.sql")

    assert "create table if not exists public.platforms" in migration
    assert "create table if not exists public.game_titles" in migration
    assert "create table if not exists public.game_key_aliases" in migration
    assert "create table if not exists public.master_sync_state" in migration
    assert "add column if not exists game_id text references public.games(id)" in migration
    assert "add column if not exists master_game_id text references public.games(id)" in migration
    assert "'master'," in migration
    assert "'[]'::jsonb" in migration
    assert "begin_master_catalog_sync" in migration
    assert "upsert_igdb_master_batch" in migration
    assert "create or replace function public.admin_system_status()" in migration
    assert "master_size_bytes" in migration


def test_legacy_rebuild_preserves_master_rows():
    migration = read("supabase/migrations/20260614_v50_universal_game_database.sql")

    assert "where source_kind <> 'master'" in migration
    assert "and index_run_id <> p_run_id" in migration
    assert "delete from public.catalog_games where index_run_id <> p_run_id" not in migration


def test_frontend_exposes_master_cards_and_attribution():
    app = read("docs/app.js")
    api = read("docs/catalog-api.js")
    html = read("docs/index.html")
    worker = read("docs/service-worker.js")

    assert 'if (["catalog", "store", "master", "hybrid"].includes(game.source_kind))' in app
    assert 'if (game.source_kind === "master") return "ENCICLOPEDIA"' in app
    assert 'priceLabel.textContent = "SCHEDA ENCICLOPEDICA"' in app
    assert "master_game_id: item?.master_game_id || null" in api
    assert 'href="https://www.igdb.com/"' in html
    assert 'const CACHE_NAME = "ludograph-v5-3-6-search-result-guards"' in worker
    assert "soglia operativa 40 GiB" in app
    assert "status.master_sync" in app


def test_igdb_workflow_is_manual_resumable_and_uses_secrets():
    workflow = read(".github/workflows/sync-igdb-master.yml")

    assert "workflow_dispatch:" in workflow
    assert "reset_cursor:" in workflow
    assert "IGDB_CLIENT_ID: ${{ secrets.IGDB_CLIENT_ID }}" in workflow
    assert "IGDB_CLIENT_SECRET: ${{ secrets.IGDB_CLIENT_SECRET }}" in workflow
    assert "python -m poller.igdb_master_main" in workflow
    assert "CATALOG_MAX_DATABASE_BYTES: \"42949672960\"" in workflow


def test_igdb_master_sink_uses_single_jsonb_wrapper_rpc():
    from poller.igdb_master_sink import SupabaseMasterSink
    from poller.igdb_models import MasterBatch

    class RpcRecorder:
        def __init__(self):
            self.calls = []

        def rpc(self, function, payload):
            self.calls.append((function, payload))
            return {"games": 1}

    recorder = RpcRecorder()
    sink = SupabaseMasterSink(recorder)
    batch = MasterBatch(games=[{"id": "igdb:1", "title": "Test"}])

    result = sink.upsert(
        batch,
        run_id="00000000-0000-0000-0000-000000000001",
        cursor_id=1,
    )

    assert result == {"games": 1}
    function, payload = recorder.calls[0]
    assert function == "upsert_igdb_master_payload"
    assert list(payload) == ["p_payload"]
    assert payload["p_payload"]["p_cursor_id"] == 1
    assert payload["p_payload"]["p_games"][0]["id"] == "igdb:1"


def test_v502_migration_adds_single_jsonb_rpc_wrapper():
    migration = read("supabase/migrations/20260614_v502_igdb_rpc_payload_wrapper.sql")

    assert "create or replace function public.upsert_igdb_master_payload" in migration
    assert "p_payload jsonb" in migration
    assert "return public.upsert_igdb_master_batch(" in migration
    assert "grant execute on function public.upsert_igdb_master_payload(jsonb) to service_role" in migration
    assert "notify pgrst, 'reload schema'" in migration.lower()


def test_supabase_client_reports_non_retryable_404_body():
    from poller.supabase_catalog_sink import SupabaseCatalogError, SupabaseCatalogSink

    response = Mock()
    response.status_code = 404
    response.text = '{"code":"PGRST202","message":"Could not find the function"}'

    session = Mock()
    session.request.return_value = response
    sink = SupabaseCatalogSink(
        "https://example.invalid",
        "service-role-key",
        session=session,
    )

    try:
        sink.rpc("missing_rpc", {"p_value": 1})
    except SupabaseCatalogError as exc:
        message = str(exc)
    else:
        raise AssertionError("La risposta 404 doveva interrompere subito la richiesta")

    assert "PGRST202" in message
    assert "Could not find the function" in message
    assert session.request.call_count == 1


def test_v503_restores_catalog_safe_date_dependency():
    migration = read("supabase/migrations/20260614_v503_restore_catalog_safe_date.sql")
    schema = read("supabase/schema.sql")

    for sql in (migration, schema):
        assert "create or replace function public.catalog_safe_date(p_value text)" in sql
        assert "returns date" in sql
        assert "grant execute on function public.catalog_safe_date(text) to service_role" in sql

    assert "notify pgrst, 'reload schema'" in migration.lower()
