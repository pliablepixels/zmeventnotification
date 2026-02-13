"""E2E: Min confidence filtering through objectconfig."""

from __future__ import annotations

import os

import pytest

from tests.test_e2e.conftest import (
    basic_ml_sequence,
    make_config,
    run_detect_chain,
)


class TestConfidenceConfig:

    def test_high_min_confidence_filters_all(self):
        """A min_confidence of 0.99 should filter out most/all detections."""
        ml_seq = basic_ml_sequence(min_confidence=0.99)
        config_path, _ = make_config(ml_seq)
        try:
            matched_data, _, _ = run_detect_chain(config_path)
            # With 0.99 threshold, very few (if any) detections survive
            # We can't guarantee zero, but we can verify the chain doesn't crash
            for conf in matched_data.get("confidences", []):
                assert conf >= 0.99
        finally:
            os.unlink(config_path)

    def test_low_min_confidence_keeps_detections(self):
        """A min_confidence of 0.01 keeps all detections."""
        ml_seq = basic_ml_sequence(min_confidence=0.01)
        config_path, _ = make_config(ml_seq)
        try:
            matched_data, _, _ = run_detect_chain(config_path)
            assert len(matched_data["labels"]) > 0
        finally:
            os.unlink(config_path)

    def test_low_vs_high_confidence(self):
        """Lower min_confidence produces >= as many detections as higher."""
        ml_seq_low = basic_ml_sequence(min_confidence=0.1)
        ml_seq_high = basic_ml_sequence(min_confidence=0.8)
        config_low, _ = make_config(ml_seq_low)
        config_high, _ = make_config(ml_seq_high)
        try:
            low_data, _, _ = run_detect_chain(config_low)
            high_data, _, _ = run_detect_chain(config_high)
            assert len(low_data["labels"]) >= len(high_data["labels"])
        finally:
            os.unlink(config_low)
            os.unlink(config_high)
