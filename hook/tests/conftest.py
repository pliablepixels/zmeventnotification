"""Shared fixtures and mocks for hook tests.

Mock pyzm and pyzm.ZMLog before any hook helpers are imported so that
tests can run without a ZoneMinder installation.
"""
import sys
import os
import types
import tempfile

import pytest
import yaml

# ---------------------------------------------------------------------------
# Mock pyzm and its submodules before any hook code touches them
# ---------------------------------------------------------------------------

_mock_pyzm = types.ModuleType("pyzm")
_mock_pyzm.__version__ = "0.0.0_stub"

# Stub classes for pyzm v2 imports used by zm_detect.py
class _StubDetector:
    _gateway = None
    @classmethod
    def from_dict(cls, *a, **kw): return cls()
    def detect(self, *a, **kw): return type("R", (), {"to_dict": lambda s: {}})()
    def detect_event(self, *a, **kw): return type("R", (), {"to_dict": lambda s: {}})()

class _StubEvent:
    def __init__(self, **kw):
        self.notes = kw.get('notes', '')
    def path(self): return None
    def update_notes(self, notes): pass
    def tag(self, labels): pass

class _StubZMClient:
    api = None
    def __init__(self, *a, **kw): pass
    def event(self, eid): return _StubEvent()

class _StubStreamConfig:
    @classmethod
    def from_dict(cls, d): return cls()

class _StubZone:
    def __init__(self, name="", points=None, pattern=None, ignore_pattern=None, _raw=None):
        self.name = name
        self.points = points or []
        self.pattern = pattern
        self.ignore_pattern = ignore_pattern
        self._raw = _raw or {}

    def raw(self):
        return self._raw

    def as_dict(self):
        return {
            "name": self.name,
            "value": self.points,
            "pattern": self.pattern,
            "ignore_pattern": self.ignore_pattern,
        }

_mock_pyzm.Detector = _StubDetector
_mock_pyzm.ZMClient = _StubZMClient

_mock_log = types.ModuleType("pyzm.log")
_mock_log.setup_zm_logging = lambda *a, **kw: StubLogger()

_mock_helpers = types.ModuleType("pyzm.helpers")
_mock_helpers_utils = types.ModuleType("pyzm.helpers.utils")
_mock_helpers_utils.read_config = lambda f: yaml.safe_load(open(f)) if os.path.isfile(f) else {}
_mock_helpers_utils.template_fill = lambda input_str, config=None, secrets=None: input_str

_mock_models = types.ModuleType("pyzm.models")
_mock_models_config = types.ModuleType("pyzm.models.config")
_mock_models_config.StreamConfig = _StubStreamConfig
_mock_models_zm = types.ModuleType("pyzm.models.zm")
_mock_models_zm.Zone = _StubZone

sys.modules.setdefault("pyzm", _mock_pyzm)
sys.modules.setdefault("pyzm.log", _mock_log)
sys.modules.setdefault("pyzm.helpers", _mock_helpers)
sys.modules.setdefault("pyzm.helpers.utils", _mock_helpers_utils)
sys.modules.setdefault("pyzm.models", _mock_models)
sys.modules.setdefault("pyzm.models.config", _mock_models_config)
sys.modules.setdefault("pyzm.models.zm", _mock_models_zm)

# ---------------------------------------------------------------------------
# Ensure hook/ is on sys.path so `import zmes_hook_helpers` works
# ---------------------------------------------------------------------------
_hook_dir = os.path.join(os.path.dirname(__file__), os.pardir)
if os.path.abspath(_hook_dir) not in sys.path:
    sys.path.insert(0, os.path.abspath(_hook_dir))


# ---------------------------------------------------------------------------
# Stub logger that satisfies g.logger.Debug / Info / Error / Fatal
# ---------------------------------------------------------------------------
class StubLogger:
    def Debug(self, level, msg): pass
    def Info(self, msg): pass
    def Error(self, msg): pass
    def Fatal(self, msg): raise SystemExit(msg)
    def close(self): pass


@pytest.fixture(autouse=True)
def reset_common_params():
    """Reset global state in common_params before each test."""
    import zmes_hook_helpers.common_params as g
    g.config = {}
    g.polygons = []
    g.ctx = None
    g.logger = StubLogger()
    yield
    # teardown: nothing extra needed


@pytest.fixture
def fixtures_dir():
    return os.path.join(os.path.dirname(__file__), "fixtures")


@pytest.fixture
def test_objectconfig(fixtures_dir):
    path = os.path.join(fixtures_dir, "test_objectconfig.yml")
    with open(path) as f:
        return yaml.safe_load(f)


@pytest.fixture
def test_secrets(fixtures_dir):
    path = os.path.join(fixtures_dir, "test_secrets.yml")
    with open(path) as f:
        return yaml.safe_load(f)
