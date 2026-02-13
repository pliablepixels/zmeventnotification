"""E2E: Pattern filtering through objectconfig -> detection chain."""

from __future__ import annotations

import os

import pytest

from tests.test_e2e.conftest import (
    basic_ml_sequence,
    make_config,
    run_detect_chain,
)


class TestPatternConfig:

    def test_restrictive_pattern_no_matches(self):
        """A pattern that matches nothing produces no output."""
        ml_seq = basic_ml_sequence(pattern="^zzz_nonexistent$")
        config_path, _ = make_config(ml_seq)
        try:
            matched_data, output, _ = run_detect_chain(config_path)
            assert len(matched_data["labels"]) == 0
            assert output == ""
        finally:
            os.unlink(config_path)

    def test_matching_pattern_produces_detections(self):
        """A broad pattern that matches common objects produces detections."""
        ml_seq = basic_ml_sequence(pattern=".*")
        config_path, _ = make_config(ml_seq)
        try:
            matched_data, output, _ = run_detect_chain(config_path)
            assert len(matched_data["labels"]) > 0
            assert output != ""
        finally:
            os.unlink(config_path)

    def test_specific_label_pattern(self):
        """Pattern restricting to 'bird' only keeps bird detections."""
        ml_seq = basic_ml_sequence(pattern="^bird$")
        config_path, _ = make_config(ml_seq)
        try:
            matched_data, _, _ = run_detect_chain(config_path)
            for label in matched_data["labels"]:
                assert label == "bird", f"Unexpected label: {label}"
        finally:
            os.unlink(config_path)
