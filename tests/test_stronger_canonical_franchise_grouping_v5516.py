from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "20260620_v5516_stronger_canonical_franchise_grouping.sql"
APP = ROOT / "docs" / "app.js"
WORKER = ROOT / "docs" / "service-worker.js"


def test_v5516_backend_merges_same_title_groups_with_compatible_years_even_if_types_differ():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "admin_search_franchise_candidates" in sql
    assert "title_year_stats" in sql
    assert "abs(tys.max_year - tys.min_year) <= 2" in sql
    assert "and cd.canonical_year_anchor is not null" in sql
    assert "then 'canonical:' || cd.normalized_title || ':' || cd.canonical_year_anchor::text" in sql
    # The canonical title+year branch must be evaluated before the separate-type
    # branch, otherwise records tagged as remake/remaster can remain split from
    # unknown/catalog duplicates of the same work.
    assert sql.index("and cd.canonical_year_anchor is not null") < sql.index("when public.catalog_is_separate_game_type(cd.game_type)")


def test_v5516_frontend_second_pass_merges_backend_canonical_groups():
    app = APP.read_text(encoding="utf-8")
    assert "mergeAdminFranchiseCanonicalGroups" in app
    assert "candidateGroupsYearCompatible" in app
    assert "candidateGroupTitleKey(candidate) === titleKey" in app
    assert "return mergeAdminFranchiseCanonicalGroups(normalizedGroups);" in app


def test_v5516_cache_name_is_updated():
    worker = WORKER.read_text(encoding="utf-8")
    assert 'const CACHE_NAME = "ludograph-v5-6-0-canonical-catalog-foundation"' in worker
