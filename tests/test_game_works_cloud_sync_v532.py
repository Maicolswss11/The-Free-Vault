from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "20260616_v532_game_works_cloud_sync.sql"


def test_v532_migration_defines_canonical_works_and_fast_cloud_sync():
    sql = MIGRATION.read_text(encoding="utf-8").lower()
    assert "create or replace function public.catalog_game_work_key" in sql
    assert "create or replace function public.catalog_game_work_members" in sql
    assert "create or replace function public.catalog_game_work_json" in sql
    assert "create or replace function public.catalog_is_subordinate_game_type" in sql
    assert "'port', 'fork', 'expanded_game'" in sql
    assert "create index if not exists catalog_games_normalized_title_idx" in sql
    assert "create or replace function public.sync_user_library_batch" in sql
    assert "on conflict (user_id, game_key) do update" in sql
    assert "new.game_key is not distinct from old.game_key" in sql
    assert "create index if not exists catalog_games_canonical_id_idx" in sql


def test_v532_franchise_payloads_include_subordinate_variants():
    sql = MIGRATION.read_text(encoding="utf-8").lower()
    assert "public.catalog_game_work_json(fg.game_key)" in sql
    assert "'editorial_work_key'" in sql
    assert "'variant_count'" in sql
    assert "'variants'" in sql
    assert "perform public.consolidate_franchise_variants_internal" in sql
    assert "'deduplication', 'canonical_work'" in sql


def test_v532_frontend_groups_ports_and_renders_them_as_subgames():
    app = (ROOT / "docs" / "app.js").read_text(encoding="utf-8")
    css = (ROOT / "docs" / "styles.css").read_text(encoding="utf-8")
    assert "SUBORDINATE_GAME_TYPES" in app
    assert 'new Set(["port", "fork", "expanded_game"])' in app
    assert "flattenedUniqueVariants" in app
    assert "franchiseWorkVariants" in app
    assert "franchise-variants-toggle" in app
    assert "versioni e porting" in app
    assert ".franchise-variant-list" in css
    assert ".franchise-variant-item" in css


def test_v532_cloud_sync_only_pushes_deltas_in_bounded_rpc_batches():
    cloud = (ROOT / "docs" / "cloud-sync.js").read_text(encoding="utf-8")
    app = (ROOT / "docs" / "app.js").read_text(encoding="utf-8")
    assert "LIBRARY_BATCH_SIZE = 75" in cloud
    assert 'client.rpc("sync_user_library_batch"' in cloud
    assert "pendingLibraryChanges" in cloud
    assert "changedLibraryEntries" in cloud
    assert "syncedLibrary" in cloud
    assert '.from("user_library").upsert' not in cloud
    assert "merged.pendingLibrary || {}" in app
    assert "merged.pendingLists || {}" in app


def test_v532_cache_name_is_updated():
    worker = (ROOT / "docs" / "service-worker.js").read_text(encoding="utf-8")
    assert 'const CACHE_NAME = "ludograph-v5-5-9-franchise-fidelity"' in worker
