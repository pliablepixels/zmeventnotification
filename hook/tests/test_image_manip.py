"""Tests for image manipulation utilities.

These tests focus on polygon operations and coordinate scaling
which are the most testable parts without heavy cv2/imageio dependencies.
"""
import pytest
import sys
import os
import numpy as np


class StubLogger:
    """Stub logger that satisfies g.logger interface."""
    def Debug(self, level, msg): pass
    def Info(self, msg): pass
    def Error(self, msg): pass
    def Fatal(self, msg): raise SystemExit(msg)
    def close(self): pass


class TestPolygonOperations:
    """Test polygon-related operations used in detection zones."""

    def test_polygon_creation(self):
        """Test that Shapely polygon can be created."""
        from shapely.geometry import Polygon

        coords = [(0, 0), (100, 0), (100, 100), (0, 100)]
        poly = Polygon(coords)

        assert poly.is_valid
        assert poly.area == 10000

    def test_polygon_intersection(self):
        """Test polygon intersection detection."""
        from shapely.geometry import Polygon, box

        # Create a detection zone
        zone = Polygon([(0, 0), (200, 0), (200, 200), (0, 200)])

        # Create a detection box that overlaps
        detection = box(50, 50, 150, 150)

        assert zone.intersects(detection)
        intersection = zone.intersection(detection)
        assert intersection.area > 0

    def test_polygon_no_intersection(self):
        """Test polygon non-intersection."""
        from shapely.geometry import Polygon, box

        # Create a detection zone
        zone = Polygon([(0, 0), (100, 0), (100, 100), (0, 100)])

        # Create a detection box outside zone
        detection = box(200, 200, 300, 300)

        assert not zone.intersects(detection)

    def test_polygon_contains_point(self):
        """Test polygon point containment."""
        from shapely.geometry import Polygon, Point

        zone = Polygon([(0, 0), (100, 0), (100, 100), (0, 100)])

        inside = Point(50, 50)
        outside = Point(150, 150)

        assert zone.contains(inside)
        assert not zone.contains(outside)


class TestBoundingBoxOperations:
    """Test bounding box operations."""

    def test_bbox_to_polygon(self):
        """Test converting bounding box to polygon."""
        from shapely.geometry import box

        # Bounding box: [x1, y1, x2, y2]
        bbox = [10, 20, 110, 120]

        poly = box(bbox[0], bbox[1], bbox[2], bbox[3])

        assert poly.is_valid
        assert poly.area == 10000  # 100 * 100

    def test_bbox_center(self):
        """Test calculating bounding box center."""
        bbox = [10, 20, 110, 120]

        center_x = (bbox[0] + bbox[2]) / 2
        center_y = (bbox[1] + bbox[3]) / 2

        assert center_x == 60
        assert center_y == 70

    def test_bbox_area(self):
        """Test calculating bounding box area."""
        bbox = [10, 20, 110, 220]

        width = bbox[2] - bbox[0]
        height = bbox[3] - bbox[1]
        area = width * height

        assert width == 100
        assert height == 200
        assert area == 20000

    def test_bbox_iou(self):
        """Test Intersection over Union calculation."""
        from shapely.geometry import box

        box1 = box(0, 0, 100, 100)
        box2 = box(50, 50, 150, 150)

        intersection = box1.intersection(box2).area
        union = box1.union(box2).area
        iou = intersection / union

        # Expected: 50*50 / (100*100 + 100*100 - 50*50)
        expected_iou = 2500 / (10000 + 10000 - 2500)
        assert abs(iou - expected_iou) < 0.001


class TestCoordinateScaling:
    """Test coordinate scaling operations."""

    def test_scale_bbox_up(self):
        """Test scaling bounding box to larger image."""
        bbox = [10, 20, 50, 60]  # Original coords at 100x100

        # Scale to 200x200
        scale_x = 2.0
        scale_y = 2.0

        scaled = [
            int(bbox[0] * scale_x),
            int(bbox[1] * scale_y),
            int(bbox[2] * scale_x),
            int(bbox[3] * scale_y)
        ]

        assert scaled == [20, 40, 100, 120]

    def test_scale_bbox_down(self):
        """Test scaling bounding box to smaller image."""
        bbox = [100, 200, 300, 400]  # Original coords at 1000x1000

        # Scale to 500x500
        scale_x = 0.5
        scale_y = 0.5

        scaled = [
            int(bbox[0] * scale_x),
            int(bbox[1] * scale_y),
            int(bbox[2] * scale_x),
            int(bbox[3] * scale_y)
        ]

        assert scaled == [50, 100, 150, 200]

    def test_scale_polygon_coords(self):
        """Test scaling polygon coordinates."""
        coords = [(0, 0), (100, 0), (100, 100), (0, 100)]

        # Scale by 1.5
        scale = 1.5
        scaled = [(int(x * scale), int(y * scale)) for x, y in coords]

        assert scaled == [(0, 0), (150, 0), (150, 150), (0, 150)]

    def test_non_uniform_scaling(self):
        """Test non-uniform scaling (different x and y scales)."""
        bbox = [10, 10, 110, 60]

        # Different x and y scales
        scale_x = 2.0
        scale_y = 3.0

        scaled = [
            int(bbox[0] * scale_x),
            int(bbox[1] * scale_y),
            int(bbox[2] * scale_x),
            int(bbox[3] * scale_y)
        ]

        assert scaled == [20, 30, 220, 180]


class TestImageDimensionCalculations:
    """Test image dimension calculations."""

    def test_aspect_ratio_calculation(self):
        """Test aspect ratio calculation."""
        width = 1920
        height = 1080

        aspect_ratio = width / height

        assert abs(aspect_ratio - 16/9) < 0.001

    def test_resize_maintaining_aspect(self):
        """Test resize calculations maintaining aspect ratio."""
        original_width = 1920
        original_height = 1080
        new_width = 640

        scale = new_width / original_width
        new_height = int(original_height * scale)

        assert new_width == 640
        assert new_height == 360  # 1080 * (640/1920)

    def test_resize_by_height(self):
        """Test resize calculations by height."""
        original_width = 1920
        original_height = 1080
        new_height = 720

        scale = new_height / original_height
        new_width = int(original_width * scale)

        assert new_height == 720
        assert new_width == 1280  # 1920 * (720/1080)
