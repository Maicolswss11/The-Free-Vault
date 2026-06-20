from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")

def test_admin_franchise_has_true_bulk_selection_controls():
    html = read("docs/index.html")
    app = read("docs/app.js")
    styles = read("docs/styles.css")

    for element_id in (
        "admin-franchise-select-all",
        "admin-franchise-deselect-results",
        "admin-franchise-selected-list",
        "admin-franchise-sort-release",
    ):
        assert f'id="{element_id}"' in html

    assert "franchiseSearchResults" in app
    assert "setAdminFranchiseGameSelection" in app
    assert "renderAdminFranchiseSelectedList" in app
    assert "Seleziona opere canoniche" in app
    assert "searchAdminFranchiseCandidates(query, 50)" in app
    assert "admin-result-checkbox" in styles
    assert "admin-selected-game" in styles

def test_v471_only_requires_frontend_cache_refresh():
    worker = read("docs/service-worker.js")
    assert 'the-free-vault-v4-7-1-franchise-bulk-selection' in worker
