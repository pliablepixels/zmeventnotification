"""E2E: Output formatting with real detection results."""

from __future__ import annotations

import json
import os

import pytest

from tests.test_e2e.conftest import (
    basic_ml_sequence,
    make_config,
    run_detect_chain,
)


class TestFormatChain:

    def test_json_roundtrip(self):
        """JSON portion of output is valid and contains all required keys."""
        ml_seq = basic_ml_sequence()
        config_path, _ = make_config(ml_seq)
        try:
            _, output, _ = run_detect_chain(config_path)
            if not output:
                pytest.skip("No detections")
            _, json_str = output.split("--SPLIT--", 1)
            parsed = json.loads(json_str)
            assert isinstance(parsed["labels"], list)
            assert isinstance(parsed["boxes"], list)
            assert isinstance(parsed["confidences"], list)
            assert len(parsed["labels"]) == len(parsed["boxes"])
            assert len(parsed["labels"]) == len(parsed["confidences"])
        finally:
            os.unlink(config_path)

    def test_label_confidence_correlation(self):
        """Each detection label has a corresponding confidence > 0."""
        ml_seq = basic_ml_sequence()
        config_path, _ = make_config(ml_seq)
        try:
            matched_data, _, _ = run_detect_chain(config_path)
            if not matched_data.get("labels"):
                pytest.skip("No detections")
            assert len(matched_data["labels"]) == len(matched_data["confidences"])
            for conf in matched_data["confidences"]:
                assert conf > 0
        finally:
            os.unlink(config_path)

    def test_boxes_are_valid(self):
        """Each detection box has 4 coordinates with x2>x1 and y2>y1."""
        ml_seq = basic_ml_sequence()
        config_path, _ = make_config(ml_seq)
        try:
            matched_data, _, _ = run_detect_chain(config_path)
            if not matched_data.get("labels"):
                pytest.skip("No detections")
            for box in matched_data["boxes"]:
                assert len(box) == 4
                x1, y1, x2, y2 = box
                assert x2 > x1, f"Invalid box: x2={x2} <= x1={x1}"
                assert y2 > y1, f"Invalid box: y2={y2} <= y1={y1}"
        finally:
            os.unlink(config_path)
