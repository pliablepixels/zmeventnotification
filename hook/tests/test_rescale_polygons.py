"""Tests for rescale_polygons() from zmes_hook_helpers.utils."""
import sys
import os
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import zmes_hook_helpers.common_params as g


class _FakeLogger:
    def Debug(self, *a, **kw): pass
    def Info(self, *a, **kw): pass

g.logger = _FakeLogger()

from zmes_hook_helpers.utils import rescale_polygons


class TestRescalePolygons:
    def setup_method(self):
        g.polygons = []

    def test_scale_up_2x(self):
        g.polygons = [{'name': 'zone1', 'value': [(10, 20), (30, 40), (50, 60)], 'pattern': None}]
        rescale_polygons(2.0, 2.0)
        assert g.polygons[0]['value'] == [(20, 40), (60, 80), (100, 120)]

    def test_scale_down_half(self):
        g.polygons = [{'name': 'zone1', 'value': [(10, 20), (30, 40), (50, 60)], 'pattern': None}]
        rescale_polygons(0.5, 0.5)
        assert g.polygons[0]['value'] == [(5, 10), (15, 20), (25, 30)]

    def test_non_uniform_scaling(self):
        g.polygons = [{'name': 'zone1', 'value': [(10, 20), (30, 40)], 'pattern': None}]
        rescale_polygons(2.0, 0.5)
        assert g.polygons[0]['value'] == [(20, 10), (60, 20)]

    def test_multiple_polygons(self):
        g.polygons = [
            {'name': 'z1', 'value': [(10, 10), (20, 20), (30, 30)], 'pattern': 'person'},
            {'name': 'z2', 'value': [(5, 5), (15, 15), (25, 25)], 'pattern': 'car'},
        ]
        rescale_polygons(3.0, 3.0)
        assert g.polygons[0]['value'] == [(30, 30), (60, 60), (90, 90)]
        assert g.polygons[1]['value'] == [(15, 15), (45, 45), (75, 75)]

    def test_name_and_pattern_preserved(self):
        g.polygons = [{'name': 'myzone', 'value': [(1, 2), (3, 4), (5, 6)], 'pattern': 'dog|cat'}]
        rescale_polygons(1.5, 1.5)
        assert g.polygons[0]['name'] == 'myzone'
        assert g.polygons[0]['pattern'] == 'dog|cat'

    def test_identity_scale(self):
        original = [(100, 200), (300, 400), (500, 600)]
        g.polygons = [{'name': 'zone1', 'value': list(original), 'pattern': None}]
        rescale_polygons(1.0, 1.0)
        assert g.polygons[0]['value'] == original

    def test_ignore_pattern_preserved(self):
        """Ref: ZoneMinder/pyzm#37 -- ignore_pattern must survive rescaling."""
        g.polygons = [{'name': 'driveway', 'value': [(10, 10), (20, 20), (30, 30)],
                       'pattern': '(person|car)', 'ignore_pattern': '(car|truck)'}]
        rescale_polygons(2.0, 2.0)
        assert g.polygons[0]['ignore_pattern'] == '(car|truck)'
        assert g.polygons[0]['pattern'] == '(person|car)'

    def test_ignore_pattern_none_preserved(self):
        """When ignore_pattern is not set, it should default to None after rescale."""
        g.polygons = [{'name': 'zone1', 'value': [(10, 10), (20, 20), (30, 30)], 'pattern': None}]
        rescale_polygons(2.0, 2.0)
        assert g.polygons[0].get('ignore_pattern') is None
