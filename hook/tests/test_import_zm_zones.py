"""Tests for import_zm_zones using pyzm ZMClient. Ref: pliablepixels/zmeventnotification#18"""
import sys
import os
import pytest
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import zmes_hook_helpers.common_params as g
from pyzm.models.zm import Zone


class _FakeLogger:
    def Debug(self, *a, **kw): pass
    def Info(self, *a, **kw): pass
    def Error(self, *a, **kw): pass


def _make_zone(name, coords, zone_type="Active"):
    """Helper to create a Zone with _raw metadata."""
    points = [tuple(map(float, p.split(','))) for p in coords.split()]
    return Zone(
        name=name,
        points=points,
        _raw={"Zone": {"Name": name, "Type": zone_type, "Coords": coords}},
    )


class TestImportZmZones:
    def setup_method(self):
        g.polygons = []
        g.logger = _FakeLogger()
        g.config = {
            'only_triggered_zm_zones': 'no',
            'import_zm_zones': 'yes',
        }

    def test_basic_zone_import(self):
        """Zones are imported and names normalized."""
        from zmes_hook_helpers.utils import import_zm_zones

        mock_zm = MagicMock()
        mock_monitor = MagicMock()
        mock_monitor.get_zones.return_value = [
            _make_zone("Front Yard", "0,0 100,0 100,100 0,100"),
        ]
        mock_zm.monitor.return_value = mock_monitor

        import_zm_zones("1", None, mock_zm)
        assert len(g.polygons) == 1
        assert g.polygons[0]['name'] == 'front_yard'
        assert g.polygons[0]['value'] == [(0.0, 0.0), (100.0, 0.0), (100.0, 100.0), (0.0, 100.0)]
        assert g.polygons[0]['pattern'] is None

    def test_inactive_zones_skipped(self):
        """Inactive zones are not imported."""
        from zmes_hook_helpers.utils import import_zm_zones

        mock_zm = MagicMock()
        mock_monitor = MagicMock()
        mock_monitor.get_zones.return_value = [
            _make_zone("Active Zone", "0,0 100,0 100,100 0,100", "Active"),
            _make_zone("Disabled Zone", "50,50 150,50 150,150 50,150", "Inactive"),
        ]
        mock_zm.monitor.return_value = mock_monitor

        import_zm_zones("1", None, mock_zm)
        assert len(g.polygons) == 1
        assert g.polygons[0]['name'] == 'active_zone'

    def test_only_triggered_zm_zones_filters_by_reason(self):
        """When only_triggered_zm_zones is yes, only zones matching alarm reason are imported."""
        from zmes_hook_helpers.utils import import_zm_zones

        g.config['only_triggered_zm_zones'] = 'yes'

        mock_zm = MagicMock()
        mock_monitor = MagicMock()
        mock_monitor.get_zones.return_value = [
            _make_zone("Driveway", "0,0 100,0 100,100 0,100"),
            _make_zone("Backyard", "50,50 150,50 150,150 50,150"),
        ]
        mock_zm.monitor.return_value = mock_monitor

        import_zm_zones("1", "Motion: Driveway", mock_zm)
        assert len(g.polygons) == 1
        assert g.polygons[0]['name'] == 'driveway'

    def test_no_reason_match_imports_all_when_not_triggered(self):
        """When only_triggered_zm_zones is no, reason is ignored."""
        from zmes_hook_helpers.utils import import_zm_zones

        mock_zm = MagicMock()
        mock_monitor = MagicMock()
        mock_monitor.get_zones.return_value = [
            _make_zone("Driveway", "0,0 100,0 100,100 0,100"),
            _make_zone("Backyard", "50,50 150,50 150,150 50,150"),
        ]
        mock_zm.monitor.return_value = mock_monitor

        import_zm_zones("1", "Motion: Driveway", mock_zm)
        assert len(g.polygons) == 2

    def test_float_percentage_coords(self):
        """Float/percentage coordinates are preserved. Ref: pliablepixels/zmeventnotification#18"""
        from zmes_hook_helpers.utils import import_zm_zones

        mock_zm = MagicMock()
        mock_monitor = MagicMock()
        mock_monitor.get_zones.return_value = [
            _make_zone("Porch", "26.41,33.5 75.2,33.5 75.2,90.1 26.41,90.1"),
        ]
        mock_zm.monitor.return_value = mock_monitor

        import_zm_zones("1", None, mock_zm)
        assert len(g.polygons) == 1
        assert g.polygons[0]['value'] == [(26.41, 33.5), (75.2, 33.5), (75.2, 90.1), (26.41, 90.1)]

    def test_name_normalization(self):
        """Zone names: spaces to underscores, lowercased."""
        from zmes_hook_helpers.utils import import_zm_zones

        mock_zm = MagicMock()
        mock_monitor = MagicMock()
        mock_monitor.get_zones.return_value = [
            _make_zone("Front Yard Camera 1", "0,0 100,0 100,100 0,100"),
        ]
        mock_zm.monitor.return_value = mock_monitor

        import_zm_zones("1", None, mock_zm)
        assert g.polygons[0]['name'] == 'front_yard_camera_1'
