"""Tests for config_upgrade_yaml.py — resolve_dotted and apply_managed_defaults."""

import importlib.util
import os

spec = importlib.util.spec_from_file_location(
    "config_upgrade_yaml",
    os.path.join(os.path.dirname(__file__), "..", "config_upgrade_yaml.py"),
)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

resolve_dotted = mod.resolve_dotted
apply_managed_defaults = mod.apply_managed_defaults


# ── resolve_dotted ──────────────────────────────────────────────────────

class TestResolveDotted:
    def test_simple_resolution(self):
        d = {"fcm": {"fcm_v1_key": "abc"}}
        assert resolve_dotted(d, "fcm.fcm_v1_key") == "abc"

    def test_missing_key_returns_none(self):
        d = {"fcm": {"fcm_v1_key": "abc"}}
        assert resolve_dotted(d, "fcm.no_such_key") is None

    def test_missing_parent_returns_none(self):
        d = {"fcm": {"fcm_v1_key": "abc"}}
        assert resolve_dotted(d, "no_parent.fcm_v1_key") is None


# ── apply_managed_defaults ──────────────────────────────────────────────

class TestApplyManagedDefaults:
    def test_old_default_replaced(self):
        user = {"fcm": {"fcm_v1_key": "old-key"}}
        example = {"fcm": {"fcm_v1_key": "new-key"}}
        managed = {"fcm.fcm_v1_key": ["old-key"]}
        updated = apply_managed_defaults(user, example, managed)
        assert updated == ["fcm.fcm_v1_key"]
        assert user["fcm"]["fcm_v1_key"] == "new-key"

    def test_custom_value_preserved(self):
        user = {"fcm": {"fcm_v1_key": "my-custom-key"}}
        example = {"fcm": {"fcm_v1_key": "new-key"}}
        managed = {"fcm.fcm_v1_key": ["old-key"]}
        updated = apply_managed_defaults(user, example, managed)
        assert updated == []
        assert user["fcm"]["fcm_v1_key"] == "my-custom-key"

    def test_mixed_old_key_custom_url(self):
        user = {"fcm": {"fcm_v1_key": "old-key", "url": "https://custom.example.com"}}
        example = {"fcm": {"fcm_v1_key": "new-key", "url": "https://default.example.com"}}
        managed = {
            "fcm.fcm_v1_key": ["old-key"],
            "fcm.url": ["https://old-default.example.com"],
        }
        updated = apply_managed_defaults(user, example, managed)
        assert updated == ["fcm.fcm_v1_key"]
        assert user["fcm"]["fcm_v1_key"] == "new-key"
        assert user["fcm"]["url"] == "https://custom.example.com"

    def test_missing_key_in_user_skipped(self):
        user = {"fcm": {}}
        example = {"fcm": {"fcm_v1_key": "new-key"}}
        managed = {"fcm.fcm_v1_key": ["old-key"]}
        updated = apply_managed_defaults(user, example, managed)
        assert updated == []
        assert "fcm_v1_key" not in user["fcm"]

    def test_user_already_has_current_default(self):
        user = {"fcm": {"fcm_v1_key": "new-key"}}
        example = {"fcm": {"fcm_v1_key": "new-key"}}
        managed = {"fcm.fcm_v1_key": ["old-key"]}
        updated = apply_managed_defaults(user, example, managed)
        assert updated == []
        assert user["fcm"]["fcm_v1_key"] == "new-key"

    def test_multiple_old_defaults_any_match(self):
        user = {"fcm": {"fcm_v1_key": "old-key-v2"}}
        example = {"fcm": {"fcm_v1_key": "new-key"}}
        managed = {"fcm.fcm_v1_key": ["old-key-v1", "old-key-v2", "old-key-v3"]}
        updated = apply_managed_defaults(user, example, managed)
        assert updated == ["fcm.fcm_v1_key"]
        assert user["fcm"]["fcm_v1_key"] == "new-key"
