from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "20260618_v5515_canonical_franchise_editor_selection.sql"
APP = ROOT / "docs" / "app.js"
WORKER = ROOT / "docs" / "service-worker.js"


def test_v5515_admin_search_groups_catalog_records_as_canonical_works():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "admin_search_franchise_candidates" in sql
    assert "canonical_year_anchor" in sql
    assert "'canonical:' || cd.normalized_title || ':' || cd.canonical_year_anchor::text" in sql
    assert "stesso titolo normalizzato + anno vicino" in sql
    assert "variant_keys" in sql
    assert "variant_count" in sql
    assert "varianti espandibili" in sql


def test_v5515_admin_search_prefers_rich_representative_inside_canonical_group():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "k.review_count desc" in sql
    assert "k.library_count desc" in sql
    assert "k.media_count desc" in sql
    assert "case k.source_kind when 'master' then 0" in sql
    assert "catalog_review_anchor_count" in sql
    assert "catalog_library_anchor_count" in sql
    assert "catalog_detail_media_count" in sql


def test_v5515_frontend_preserves_backend_canonical_groups_for_franchise_editor():
    app = APP.read_text(encoding="utf-8")
    assert "normalizeAdminFranchiseCandidateGroups" in app
    assert "Seleziona opere canoniche" in app
    assert "Deseleziona opere visibili" in app
    assert "varianti catalogo unite in un’opera canonica" in app
    assert "Mostra ${variantCount} varianti" in app
    assert "canonical_route_key" in app


def test_v5515_cache_name_is_updated():
    worker = WORKER.read_text(encoding="utf-8")
    assert 'const CACHE_NAME = "ludograph-v5-5-17-editorial-canonical-variants"' in worker
