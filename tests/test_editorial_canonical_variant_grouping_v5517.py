from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "20260621_v5517_editorial_canonical_variant_grouping.sql"
APP = ROOT / "docs" / "app.js"
WORKER = ROOT / "docs" / "service-worker.js"


def test_v5517_backend_strips_parenthetical_years_for_editorial_grouping():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "catalog_editorial_base_title" in sql
    assert "catalog_title_year_hint" in sql
    assert "public.catalog_editorial_base_title(cg.title) as normalized_title" in sql
    assert "public.catalog_title_year_hint(cg.title)" in sql
    assert "(1998)" in sql


def test_v5517_frontend_merges_same_title_when_one_group_has_no_year():
    app = APP.read_text(encoding="utf-8")
    assert "candidateGroupHasSeparateEditorialMarker" in app
    assert "(?:19|20)\\d{2}" in app
    assert "return !candidateGroupHasSeparateEditorialMarker(left) && !candidateGroupHasSeparateEditorialMarker(right);" in app
    assert "game?.title || game?.canonical_title" in app


def test_v5517_cache_name_is_updated():
    worker = WORKER.read_text(encoding="utf-8")
    assert 'const CACHE_NAME = "ludograph-v5-6-4-catalog-density-and-canonical-offers"' in worker
