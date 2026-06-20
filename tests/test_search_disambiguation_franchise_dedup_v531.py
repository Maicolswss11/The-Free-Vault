from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_v531_migration_defines_editorial_identity_and_grouped_search():
    sql = read("supabase/migrations/20260615_v531_search_disambiguation_franchise_dedup.sql")

    assert "catalog_editorial_identity" in sql
    assert "admin_search_franchise_candidates" in sql
    assert "admin_consolidate_franchise_variants" in sql
    assert "consolidate_franchise_variants_internal" in sql
    assert "same title" not in sql.lower()  # implementation is SQL, not an unsafe title-only merge
    assert "p_image_url" in sql
    assert "perform public.consolidate_franchise_variants_internal(p_franchise_id)" in sql
    assert "notify pgrst, 'reload schema'" in sql.lower()


def test_v531_catalog_cards_expose_disambiguation_metadata():
    sql = read("supabase/migrations/20260615_v531_search_disambiguation_franchise_dedup.sql")

    for field in (
        "'game_type'",
        "'game_status'",
        "'variant_parent_id'",
        "'editorial_identity'",
        "'igdb_id'",
    ):
        assert field in sql


def test_v531_frontend_groups_variants_and_expands_franchise_candidates():
    app = read("docs/app.js")
    franchise = read("docs/franchise.js")
    styles = read("docs/styles.css")

    assert "groupGameVariants" in app
    assert "editorialIdentityForGame" in app
    assert "gameDisambiguationMarkup" in app
    assert "varianti catalogo unite in un’opera canonica" in app
    assert "Mostra ${variantCount} varianti" in app
    assert "searchAdminFranchiseCandidates(query, 50)" in app
    assert "consolidateAdminFranchiseVariants" in app
    assert 'rpc("admin_search_franchise_candidates"' in franchise
    assert 'rpc("admin_consolidate_franchise_variants"' in franchise
    assert ".admin-variant-list" in styles
    assert ".admin-result-group" in styles


def test_v531_cache_name_is_current():
    worker = read("docs/service-worker.js")
    assert 'const CACHE_NAME = "ludograph-v5-5-15-canonical-franchise-editor-selection"' in worker
