from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def test_metadata_enrichment_fetches_each_steam_app_and_infers_original_year():
    source = read("supabase/functions/admin-enrich-catalog-games/index.ts")
    assert "STEAM_CONCURRENCY = 3" in source
    assert 'endpoint.searchParams.set("appids", appId)' in source
    assert 'appIds.join(",")' not in source
    assert "Promise.allSettled" in source
    assert "MAX_ATTEMPTS = 3" in source
    assert "releaseYearFromTitle" in source
    assert "canonical_title" in source
    assert 'source = "title"' in source
    assert "release.year === inferredYear" in source
    assert "updated_from_steam" in source
    assert "inferred_from_title" in source
    assert "steam_details_found" in source
    assert "unresolved_year" in source


def test_catalog_override_exposes_visible_loading_state():
    html = read("docs/index.html")
    app = read("docs/app.js")
    css = read("docs/styles.css")
    assert 'id="admin-override-submit"' in html
    assert 'adminOverrideSubmit: $("#admin-override-submit")' in app
    assert 'setButtonLoading(ui.adminOverrideSubmit, true, "Salvataggio…")' in app
    assert "Salvataggio override in corso…" in app
    assert "ui.adminClearOverride.disabled = true" in app
    assert ".button.is-loading::before" in css
    assert "button-loading-spin" in css


def test_v473_cache_is_bumped():
    worker = read("docs/service-worker.js")
    assert "the-free-vault-v4-7-3-metadata-and-admin-loading" in worker
