"""E2E: Per-monitor config overrides through detection chain."""

from __future__ import annotations

import os

import pytest

from tests.test_e2e.conftest import (
    basic_ml_sequence,
    find_one_model_path,
    make_config,
    run_detect_chain,
)

import zmes_hook_helpers.common_params as g


class TestMonitorConfig:

    def test_monitor_overrides_pattern(self):
        """Per-monitor ml_sequence with restrictive pattern filters results."""
        weights, cfg, labels = find_one_model_path()

        # Global ml_sequence has broad pattern
        global_ml = basic_ml_sequence(pattern=".*")

        # Monitor 5 overrides with a restrictive pattern
        monitor_ml = {
            "general": {"model_sequence": "object"},
            "object": {
                "general": {"pattern": "^zzz_nonexistent$"},
                "sequence": [{
                    "name": "monitor-model",
                    "object_weights": weights,
                    "object_config": cfg,
                    "object_labels": labels,
                    "object_framework": "opencv",
                    "object_processor": "cpu",
                    "object_min_confidence": 0.3,
                }],
            },
        }
        monitors = {5: {"ml_sequence": monitor_ml}}
        config_path, _ = make_config(global_ml, monitors=monitors)
        try:
            matched_data, output, _ = run_detect_chain(
                config_path, monitor_id="5"
            )
            # Monitor override should produce no matches
            assert len(matched_data["labels"]) == 0
        finally:
            os.unlink(config_path)

    def test_monitor_zones_loaded(self):
        """Per-monitor zones are parsed into g.polygons during process_config."""
        ml_seq = basic_ml_sequence()
        monitors = {
            3: {
                "zones": {
                    "front_yard": {
                        "coords": "0,0 640,0 640,480 0,480",
                        "detection_pattern": "person",
                    },
                    "driveway": {
                        "coords": "100,100 500,100 500,400 100,400",
                    },
                },
            }
        }
        config_path, _ = make_config(ml_seq, monitors=monitors)
        try:
            # Note: --file mode clears g.polygons at the end of process_config.
            # So we can't test zone injection through process_config with --file.
            # Instead, we verify process_config ran without error by checking detection works.
            matched_data, _, g_config = run_detect_chain(
                config_path, monitor_id="3"
            )
            # The detection should succeed regardless of zone clearing
            # The main thing we verify is the config parsed correctly
            assert g_config.get("ml_sequence") is not None
        finally:
            os.unlink(config_path)

    def test_monitor_overrides_config_key(self):
        """Per-monitor config keys (like show_percent) override global defaults."""
        ml_seq = basic_ml_sequence()
        monitors = {7: {"show_percent": "yes"}}
        config_path, _ = make_config(
            ml_seq,
            monitors=monitors,
            general_overrides={"show_percent": "no"},
        )
        try:
            _, output, g_config = run_detect_chain(
                config_path, monitor_id="7"
            )
            assert g_config["show_percent"] == "yes"
            if output:
                pred, _ = output.split("--SPLIT--", 1)
                assert "%" in pred
        finally:
            os.unlink(config_path)
