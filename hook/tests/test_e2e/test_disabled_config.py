"""E2E: Disabled models in objectconfig."""

from __future__ import annotations

import os

import pytest

from tests.test_e2e.conftest import (
    find_one_model_path,
    make_config,
    run_detect_chain,
)


class TestDisabledConfig:

    def test_disabled_model_produces_no_detections(self):
        """A model with enabled='no' produces no detections."""
        weights, config, labels = find_one_model_path()
        ml_seq = {
            "general": {"model_sequence": "object"},
            "object": {
                "general": {"pattern": ".*"},
                "sequence": [{
                    "name": "disabled-model",
                    "enabled": "no",
                    "object_weights": weights,
                    "object_config": config,
                    "object_labels": labels,
                    "object_framework": "opencv",
                    "object_processor": "cpu",
                    "object_min_confidence": 0.3,
                }],
            },
        }
        config_path, _ = make_config(ml_seq)
        try:
            matched_data, output, _ = run_detect_chain(config_path)
            assert len(matched_data["labels"]) == 0
            assert output == ""
        finally:
            os.unlink(config_path)

    def test_mixed_enabled_disabled(self):
        """Only the enabled model produces detections."""
        weights, config, labels = find_one_model_path()
        ml_seq = {
            "general": {"model_sequence": "object"},
            "object": {
                "general": {"pattern": ".*"},
                "sequence": [
                    {
                        "name": "disabled-model",
                        "enabled": "no",
                        "object_weights": weights,
                        "object_config": config,
                        "object_labels": labels,
                        "object_framework": "opencv",
                        "object_processor": "cpu",
                    },
                    {
                        "name": "enabled-model",
                        "enabled": "yes",
                        "object_weights": weights,
                        "object_config": config,
                        "object_labels": labels,
                        "object_framework": "opencv",
                        "object_processor": "cpu",
                        "object_min_confidence": 0.3,
                    },
                ],
            },
        }
        config_path, _ = make_config(ml_seq)
        try:
            matched_data, output, _ = run_detect_chain(config_path)
            assert len(matched_data["labels"]) > 0
            # All detections should come from the enabled model
            for mn in matched_data.get("model_names", []):
                assert mn == "enabled-model"
        finally:
            os.unlink(config_path)
