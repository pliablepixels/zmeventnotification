"""E2E: Full config -> detection -> output chain."""

from __future__ import annotations

import json
import os

import pytest

from tests.test_e2e.conftest import (
    BIRD_IMAGE,
    basic_ml_sequence,
    make_config,
    run_detect_chain,
)


class TestConfigToDetect:

    def test_basic_detection_produces_output(self):
        """Config with one model detects objects in bird.jpg and produces output."""
        ml_seq = basic_ml_sequence()
        config_path, _ = make_config(ml_seq)
        try:
            matched_data, output, _ = run_detect_chain(config_path)
            assert len(matched_data["labels"]) > 0, "Expected at least one detection"
            assert output, "Expected non-empty output string"
            assert "--SPLIT--" in output
        finally:
            os.unlink(config_path)

    def test_output_has_prefix_and_json(self):
        """Output follows the [x] detected:labels--SPLIT--JSON format."""
        ml_seq = basic_ml_sequence()
        config_path, _ = make_config(ml_seq)
        try:
            matched_data, output, _ = run_detect_chain(config_path)
            if not output:
                pytest.skip("No detections to validate format")
            pred, json_str = output.split("--SPLIT--", 1)
            # --file mode uses frame_id from result (typically 'snapshot' or None)
            assert "detected:" in pred
            parsed = json.loads(json_str)
            for key in ("labels", "boxes", "frame_id", "confidences", "image_dimensions"):
                assert key in parsed, f"Missing key: {key}"
        finally:
            os.unlink(config_path)

    def test_show_percent_yes(self):
        """When show_percent=yes, output contains percentage values."""
        ml_seq = basic_ml_sequence()
        config_path, _ = make_config(
            ml_seq, general_overrides={"show_percent": "yes"}
        )
        try:
            _, output, _ = run_detect_chain(config_path)
            if not output:
                pytest.skip("No detections")
            pred, _ = output.split("--SPLIT--", 1)
            assert "%" in pred
        finally:
            os.unlink(config_path)

    def test_matched_data_has_image(self):
        """matched_data['image'] is a numpy array (the detected frame)."""
        import numpy as np

        ml_seq = basic_ml_sequence()
        config_path, _ = make_config(ml_seq)
        try:
            matched_data, _, _ = run_detect_chain(config_path)
            if not matched_data.get("labels"):
                pytest.skip("No detections")
            assert matched_data.get("image") is not None
            assert isinstance(matched_data["image"], np.ndarray)
        finally:
            os.unlink(config_path)

    def test_base_data_path_substitution(self):
        """${base_data_path} in model paths gets substituted correctly."""
        from tests.test_e2e.conftest import find_one_model_path, BASE_PATH

        weights, config, labels = find_one_model_path()
        # Use ${base_data_path} placeholder in paths
        rel_weights = weights.replace(BASE_PATH, "${base_data_path}")
        rel_config = config.replace(BASE_PATH, "${base_data_path}") if config else ""
        rel_labels = labels.replace(BASE_PATH, "${base_data_path}")

        ml_seq = {
            "general": {"model_sequence": "object"},
            "object": {
                "general": {"pattern": ".*"},
                "sequence": [{
                    "name": "path-sub-test",
                    "object_weights": rel_weights,
                    "object_config": rel_config,
                    "object_labels": rel_labels,
                    "object_framework": "opencv",
                    "object_processor": "cpu",
                    "object_min_confidence": 0.3,
                }],
            },
        }
        config_path, _ = make_config(ml_seq)
        try:
            matched_data, output, g_config = run_detect_chain(config_path)
            # process_config should have substituted ${base_data_path}
            seq = g_config["ml_sequence"]["object"]["sequence"][0]
            assert "${base_data_path}" not in seq["object_weights"]
            assert BASE_PATH in seq["object_weights"]
            assert len(matched_data["labels"]) > 0
        finally:
            os.unlink(config_path)
