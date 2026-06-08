from poller.promotion_parser import is_mystery_game


def test_revealed_title_overrides_stale_vault_markers():
    element = {
        "title": "Rogue Waters",
        "seller": {"name": "Epic Dev Test Account"},
        "keyImages": [{"type": "VaultClosed", "url": "https://example.com/x.jpg"}],
        "categories": [{"path": "freegames/vaulted"}],
    }
    assert is_mystery_game(element) is False


def test_generic_mystery_title_is_detected():
    element = {
        "title": "Mystery Game",
        "seller": {"name": "Epic Dev Test Account"},
        "keyImages": [{"type": "VaultClosed", "url": "https://example.com/x.jpg"}],
    }
    assert is_mystery_game(element) is True
