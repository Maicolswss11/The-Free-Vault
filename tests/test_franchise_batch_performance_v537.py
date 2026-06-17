from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "20260616_v537_franchise_batch_write_performance.sql"


def test_v537_uses_set_based_franchise_batch_write():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "jsonb_to_recordset(p_games)" in sql
    assert "insert into public.franchise_games" in sql
    assert "on conflict (franchise_id, game_key) do update" in sql
    assert "v_requested > 250" in sql
    batch_section = sql.split("create or replace function public.admin_save_franchise_games_batch", 1)[1]
    batch_section = batch_section.split("create or replace function public.admin_save_franchise_game", 1)[0]
    assert "for v_item" not in batch_section
    assert "consolidate_franchise_variants_internal" not in batch_section
    assert "return public.admin_get_franchise" not in batch_section
    assert "'write_strategy', 'set_based'" in batch_section


def test_v537_admin_read_model_skips_expensive_variant_graph():
    sql = MIGRATION.read_text(encoding="utf-8")
    get_section = sql.split("create or replace function public.admin_get_franchise", 1)[1]
    get_section = get_section.split("create or replace function public.admin_save_franchise_games_batch", 1)[0]
    assert "catalog_game_card_json(cg)" in get_section
    assert "catalog_game_work_json" not in get_section


def test_v537_frontend_chunks_large_batches_and_refreshes_once():
    client = (ROOT / "docs" / "franchise.js").read_text(encoding="utf-8")
    app = (ROOT / "docs" / "app.js").read_text(encoding="utf-8")
    assert "offset += 250" in client
    assert "payload.slice(offset, offset + 250)" in client
    assert "return getAdminFranchise(franchiseId);" in client
    open_section = app.split("async function openAdminFranchise", 1)[1]
    open_section = open_section.split("function renderAdminCollectionGames", 1)[0]
    assert "consolidateAdminFranchiseVariants" not in open_section


def test_v537_updates_pwa_cache():
    worker = (ROOT / "docs" / "service-worker.js").read_text(encoding="utf-8")
    assert 'const CACHE_NAME = "ludograph-v5-5-2-home-topbar-fidelity"' in worker
