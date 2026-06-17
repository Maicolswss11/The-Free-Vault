from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_v536_identity_helpers_accept_missing_results():
    app = read("docs/app.js")
    assert 'function gameKey(game) {\n  if (!game || typeof game !== "object") return "";' in app
    assert 'function gameAliases(game) {\n  if (!game || typeof game !== "object") return [];' in app
    assert 'function masterIdentityForGame(game) {\n  if (!game || typeof game !== "object") return "";' in app


def test_v536_variant_grouping_filters_invalid_entries():
    app = read("docs/app.js")
    assert 'if (!game || typeof game !== "object") continue;' in app
    assert 'if (!variant || typeof variant !== "object") continue;' in app
    assert 'const searchItems = Array.isArray(response?.items) ? response.items : [];' in app
    assert 'Array.isArray(groups) ? groups : []' in app
    assert 'Array.isArray(result?.items) ? result.items : []' in app


def test_v536_cache_name_is_current():
    worker = read("docs/service-worker.js")
    assert 'const CACHE_NAME = "ludograph-v5-5-7-game-page-fidelity"' in worker
