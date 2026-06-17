from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "20260616_v539_franchise_page_stability.sql"


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_v539_public_franchise_payload_is_lightweight():
    sql = MIGRATION.read_text(encoding="utf-8")
    detail = sql.split("create or replace function public.franchise_detail", 1)[1]
    detail = detail.split("create or replace function public.franchise_game_variants", 1)[0]
    assert "catalog_game_card_json(cg)" in detail
    assert "catalog_game_work_json" not in detail
    assert "'variants_lazy', true" in detail
    assert "set statement_timeout = '8s'" in detail


def test_v539_variants_are_loaded_one_game_at_a_time():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "create or replace function public.franchise_game_variants" in sql
    assert "public.catalog_game_work_json(v_key)" in sql
    assert "fg.game_key = v_key" in sql
    assert "grant execute on function public.franchise_game_variants(text, text) to anon, authenticated" in sql


def test_v539_frontend_clears_previous_franchise_before_loading():
    app = read("docs/app.js")
    block = app.split("async function renderFranchisePage()", 1)[1]
    block = block.split("function renderCollectionGameRow", 1)[0]
    assert "state.franchiseData = null;" in block
    assert 'ui.franchiseHeroImage.removeAttribute("src")' in block
    assert "ui.franchiseHeroImage.hidden = true" in block
    assert "ui.franchiseMeta.replaceChildren()" in block


def test_v539_frontend_loads_variants_lazily():
    client = read("docs/franchise.js")
    app = read("docs/app.js")
    assert "getFranchiseGameVariants" in client
    assert 'rpc("franchise_game_variants"' in client
    assert "window.VaultFranchises.getFranchiseGameVariants(slug, key)" in app
    assert "Caricamento versioni" in app


def test_v539_cache_name_is_current():
    worker = read("docs/service-worker.js")
    assert 'const CACHE_NAME = "ludograph-v5-5-6-profile-personalization"' in worker
