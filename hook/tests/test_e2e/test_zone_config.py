"""E2E: Zone/polygon filtering through detection chain."""

from __future__ import annotations

import os

import pytest

from tests.test_e2e.conftest import (
    basic_ml_sequence,
    make_config,
    run_detect_chain,
)


class TestZoneConfig:

    def test_full_image_zone_keeps_detections(self):
        """A zone covering the entire image keeps all detections."""
        ml_seq = basic_ml_sequence()
        config_path, _ = make_config(ml_seq)
        # Full-image polygon (large enough to cover any bird.jpg resolution)
        polygons = [{
            "name": "full_image",
            "value": [(0, 0), (2000, 0), (2000, 2000), (0, 2000)],
            "pattern": None,
        }]
        try:
            matched_data, output, _ = run_detect_chain(
                config_path, inject_polygons=polygons
            )
            assert len(matched_data["labels"]) > 0
            assert output != ""
        finally:
            os.unlink(config_path)

    def test_tiny_zone_filters_detections(self):
        """A zone covering 1x1 pixel filters out all detections."""
        ml_seq = basic_ml_sequence()
        config_path, _ = make_config(ml_seq)
        # Tiny polygon that no detection bbox can intersect
        polygons = [{
            "name": "tiny",
            "value": [(0, 0), (1, 0), (1, 1), (0, 1)],
            "pattern": None,
        }]
        try:
            matched_data, output, _ = run_detect_chain(
                config_path, inject_polygons=polygons
            )
            assert len(matched_data["labels"]) == 0
            assert output == ""
        finally:
            os.unlink(config_path)

    def test_zone_with_pattern(self):
        """A zone with a restrictive pattern filters non-matching labels."""
        ml_seq = basic_ml_sequence(pattern=".*")
        config_path, _ = make_config(ml_seq)
        polygons = [{
            "name": "selective_zone",
            "value": [(0, 0), (2000, 0), (2000, 2000), (0, 2000)],
            "pattern": "^zzz_nonexistent$",
        }]
        try:
            matched_data, output, _ = run_detect_chain(
                config_path, inject_polygons=polygons
            )
            assert len(matched_data["labels"]) == 0
        finally:
            os.unlink(config_path)
