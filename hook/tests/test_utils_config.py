"""Tests for process_config and its internal helpers in zmes_hook_helpers.utils."""
import os
import ssl
import tempfile

import pytest
import yaml

import zmes_hook_helpers.common_params as g
from zmes_hook_helpers.utils import process_config


@pytest.fixture
def fixtures_dir():
    return os.path.join(os.path.dirname(__file__), "fixtures")


@pytest.fixture
def config_path(fixtures_dir):
    return os.path.join(fixtures_dir, "test_objectconfig.yml")


@pytest.fixture
def secrets_path(fixtures_dir):
    return os.path.join(fixtures_dir, "test_secrets.yml")


@pytest.fixture
def patched_config(config_path, secrets_path):
    """Return a temp config file with the secrets path rewritten."""
    with open(config_path) as f:
        data = yaml.safe_load(f)
    data["general"]["secrets"] = secrets_path
    tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".yml", delete=False)
    yaml.dump(data, tmp)
    tmp.close()
    yield tmp.name
    os.unlink(tmp.name)


@pytest.fixture
def ctx():
    return ssl.create_default_context()


class TestProcessConfig:
    def test_loads_config(self, patched_config, ctx):
        process_config({"config": patched_config}, ctx)
        assert g.config.get("portal") == "https://zm.example.com/zm"

    def test_secret_resolution(self, patched_config, ctx):
        process_config({"config": patched_config}, ctx)
        assert g.config.get("user") == "testuser"
        assert g.config.get("password") == "testpass"

    def test_type_conversion_int(self, patched_config, ctx):
        process_config({"config": patched_config}, ctx)
        assert isinstance(g.config.get("cpu_max_processes"), int)
        assert g.config["cpu_max_processes"] == 3

    def test_type_conversion_string(self, patched_config, ctx):
        process_config({"config": patched_config}, ctx)
        assert isinstance(g.config.get("show_percent"), str)
        assert g.config["show_percent"] == "no"

    def test_defaults_applied(self, patched_config, ctx):
        process_config({"config": patched_config}, ctx)
        # base_data_path has a default in config_vals
        assert g.config.get("base_data_path") == "/var/lib/zmeventnotification"

    def test_path_substitution(self, patched_config, ctx):
        process_config({"config": patched_config}, ctx)
        img_path = g.config.get("image_path", "")
        assert "${base_data_path}" not in img_path
        assert img_path == "/var/lib/zmeventnotification/images"

    def test_ml_sequence_loaded(self, patched_config, ctx):
        process_config({"config": patched_config}, ctx)
        ml_seq = g.config.get("ml_sequence")
        assert ml_seq is not None
        assert "general" in ml_seq

    def test_stream_sequence_loaded(self, patched_config, ctx):
        process_config({"config": patched_config}, ctx)
        ss = g.config.get("stream_sequence")
        assert ss is not None
        assert ss.get("resize") == 800

    def test_monitor_override(self, patched_config, ctx):
        process_config({"config": patched_config, "monitorid": "1"}, ctx)
        # monitor 1 overrides cpu_max_processes to 2
        assert g.config["cpu_max_processes"] == 2

    def test_monitor_zones(self, patched_config, ctx):
        process_config({"config": patched_config, "monitorid": "1"}, ctx)
        assert len(g.polygons) >= 1
        names = [p["name"] for p in g.polygons]
        assert "front_yard" in names

    def test_monitor_zone_coords(self, patched_config, ctx):
        process_config({"config": patched_config, "monitorid": "1"}, ctx)
        front = [p for p in g.polygons if p["name"] == "front_yard"][0]
        assert front["value"] == [(0, 0), (640, 0), (640, 480), (0, 480)]
        assert front["pattern"] == "person"

    def test_monitor_zone_ignore_pattern(self, patched_config, ctx):
        """Ref: ZoneMinder/pyzm#37 -- ignore_pattern parsed from zone config."""
        process_config({"config": patched_config, "monitorid": "2"}, ctx)
        driveway = [p for p in g.polygons if p["name"] == "driveway"][0]
        assert driveway["pattern"] == "(person|car)"
        assert driveway["ignore_pattern"] == "(car|truck)"

    def test_monitor_zone_no_ignore_pattern(self, patched_config, ctx):
        """Zones without ignore_pattern default to None."""
        process_config({"config": patched_config, "monitorid": "1"}, ctx)
        front = [p for p in g.polygons if p["name"] == "front_yard"][0]
        assert front.get("ignore_pattern") is None

    def test_no_monitor_id(self, patched_config, ctx):
        process_config({"config": patched_config}, ctx)
        assert g.polygons == []

    def test_missing_config_exits(self, ctx):
        with pytest.raises(SystemExit):
            process_config({"config": "/nonexistent/path.yml"}, ctx)

    def test_remote_secret_resolution(self, patched_config, ctx):
        process_config({"config": patched_config}, ctx)
        assert g.config.get("ml_user") == "mluser"
        assert g.config.get("ml_password") == "mlpass"


class TestCorrectType:
    """Test the _correct_type helper indirectly through process_config."""

    def test_int_conversion(self, patched_config, ctx):
        process_config({"config": patched_config}, ctx)
        assert g.config["wait"] == 0
        assert isinstance(g.config["wait"], int)

    def test_string_type(self, patched_config, ctx):
        process_config({"config": patched_config}, ctx)
        assert isinstance(g.config["allow_self_signed"], str)
