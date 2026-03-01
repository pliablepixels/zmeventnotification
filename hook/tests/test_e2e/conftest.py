"""Shared fixtures for zmeventnotification e2e tests.

These tests exercise the full config -> pyzm detection -> output chain
using real YOLO models and the bird.jpg test image.  They do NOT need a
running ZoneMinder instance (ZMClient is bypassed).

Requirements:
  - pyzm installed (real, not mocked)
  - ML models at /var/lib/zmeventnotification/models/ (at minimum one YOLO)
  - opencv-python, numpy
  - bird.jpg in this directory (included in the repo)

Run:
    python -m pytest tests/test_e2e/ -v
"""

from __future__ import annotations

import os
import ssl
import sys
import tempfile
from pathlib import Path

import pytest
import yaml

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

BIRD_IMAGE = str(Path(__file__).parent / "bird.jpg")
BASE_PATH = "/var/lib/zmeventnotification"
MODELS_DIR = os.path.join(BASE_PATH, "models")


# ---------------------------------------------------------------------------
# Markers & auto-skip
# ---------------------------------------------------------------------------

def pytest_configure(config: pytest.Config) -> None:
    config.addinivalue_line(
        "markers",
        "e2e: end-to-end tests requiring real models, images, and pyzm installed",
    )


def pytest_collection_modifyitems(config, items):
    """Auto-skip e2e tests when models or test image are missing."""
    skip_models = pytest.mark.skip(reason=f"Model dir {MODELS_DIR} not found")
    skip_image = pytest.mark.skip(reason=f"Test image {BIRD_IMAGE} not found")
    for item in items:
        if "test_e2e" in str(item.fspath):
            item.add_marker(pytest.mark.e2e)
            if not os.path.isdir(MODELS_DIR):
                item.add_marker(skip_models)
            if not os.path.isfile(BIRD_IMAGE):
                item.add_marker(skip_image)


# ---------------------------------------------------------------------------
# Fixture: swap mock pyzm with real pyzm per-test
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def use_real_pyzm():
    """Remove mock pyzm modules (set by parent conftest) and import real pyzm.

    Restores mock modules after the test so unit tests are unaffected.
    """
    saved = {}
    for key in list(sys.modules.keys()):
        if key.startswith("pyzm"):
            saved[key] = sys.modules.pop(key)
    yield
    # Restore mocks
    for key in list(sys.modules.keys()):
        if key.startswith("pyzm"):
            del sys.modules[key]
    sys.modules.update(saved)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_config(
    ml_sequence: dict,
    *,
    stream_sequence: dict | None = None,
    secrets: dict | None = None,
    general_overrides: dict | None = None,
    monitors: dict | None = None,
) -> tuple[str, str | None]:
    """Write a temp objectconfig.yml (and optional secrets.yml).

    Returns (config_path, secrets_path_or_None).
    """
    general = {
        "base_data_path": BASE_PATH,
        "allow_self_signed": "yes",
        "show_percent": "no",
        "write_image_to_zm": "no",
        "write_debug_image": "no",
        "import_zm_zones": "no",
        "only_triggered_zm_zones": "no",
    }
    if general_overrides:
        general.update(general_overrides)

    if stream_sequence is None:
        stream_sequence = {"resize": 800, "strategy": "first"}

    cfg = {
        "general": general,
        "ml": {
            "ml_sequence": ml_sequence,
            "stream_sequence": stream_sequence,
        },
    }
    if monitors:
        cfg["monitors"] = monitors

    secrets_path = None
    if secrets:
        sf = tempfile.NamedTemporaryFile(
            mode="w", suffix="_secrets.yml", delete=False
        )
        yaml.dump({"secrets": secrets}, sf)
        sf.close()
        secrets_path = sf.name
        cfg["general"]["secrets"] = secrets_path

    cf = tempfile.NamedTemporaryFile(
        mode="w", suffix="_objectconfig.yml", delete=False
    )
    yaml.dump(cfg, cf)
    cf.close()
    return cf.name, secrets_path


def run_detect_chain(
    config_path: str,
    image_path: str = BIRD_IMAGE,
    *,
    monitor_id: str | None = None,
    secrets_path: str | None = None,
    inject_polygons: list[dict] | None = None,
) -> tuple[dict, str, dict]:
    """Run the full config -> detect -> output chain.

    Returns (matched_data, output_string, g_config).
    """
    import zmes_hook_helpers.common_params as g
    import zmes_hook_helpers.utils as utils

    # Must be imported AFTER use_real_pyzm has cleared mock modules
    from pyzm import Detector

    ctx = ssl.create_default_context()

    args = {
        "config": config_path,
        "file": image_path,
        "monitorid": monitor_id,
        "debug": False,
        "output_path": None,
    }

    # Step 1: parse config
    utils.get_pyzm_config(args)
    utils.process_config(args, ctx)

    assert g.config.get("ml_sequence"), "ml_sequence missing after process_config"
    assert g.config.get("stream_sequence"), "stream_sequence missing after process_config"

    # Secrets are now resolved recursively in process_config
    ml_options = g.config["ml_sequence"]

    # Step 2: build Detector from parsed config
    detector = Detector.from_dict(ml_options)

    # Optionally inject zones (--file clears g.polygons, so inject manually)
    zones = None
    if inject_polygons:
        from pyzm.models.zm import Zone

        g.polygons = inject_polygons
        zones = [
            Zone(name=p["name"], points=p["value"], pattern=p.get("pattern"))
            for p in inject_polygons
        ]

    # Step 4: detect
    result = detector.detect(image_path, zones=zones)

    # Step 5: format output
    matched_data = result.to_dict()
    matched_data["polygons"] = g.polygons
    output = ""
    if matched_data.get("labels"):
        output = utils.format_detection_output(matched_data, g.config)

    return matched_data, output, dict(g.config)


def find_one_model_path() -> tuple[str, str, str]:
    """Find one available YOLO model.

    Returns (weights_path, config_path, labels_path).
    config_path is "" for ONNX models (no config needed).
    """
    models_dir = Path(MODELS_DIR)

    # First, build a labels lookup (some dirs have labels, others don't)
    all_labels: str | None = None
    for subdir in models_dir.iterdir():
        if not subdir.is_dir():
            continue
        for f in sorted(subdir.iterdir()):
            if f.suffix in (".names", ".txt", ".labels"):
                all_labels = str(f)
                break
        if all_labels:
            break

    # Prefer ONNX models (no config file needed), then Darknet
    for subdir in ["ultralytics", "yolov4", "yolov3", "tinyyolov4", "tinyyolov3"]:
        d = models_dir / subdir
        if not d.is_dir():
            continue
        weights = None
        config = None
        labels = None
        for f in sorted(d.iterdir()):
            if f.suffix == ".onnx" and weights is None:
                weights = str(f)
            if f.suffix == ".weights" and weights is None:
                weights = str(f)
            if f.suffix == ".cfg" and config is None:
                config = str(f)
            if f.suffix in (".names", ".txt", ".labels") and labels is None:
                labels = str(f)

        # Use labels from another directory if not found locally
        if not labels:
            labels = all_labels

        if weights and labels:
            # ONNX models don't need a config file
            if weights.endswith(".onnx"):
                return weights, "", labels
            # Darknet models need a .cfg file
            if config:
                return weights, config, labels

    pytest.skip("No YOLO model found in " + str(models_dir))


def basic_ml_sequence(
    *,
    pattern: str = "(bird|person|car|truck|dog|cat)",
    min_confidence: float = 0.3,
    extra_model_keys: dict | None = None,
    extra_general_keys: dict | None = None,
) -> dict:
    """Build a minimal ml_sequence dict using an auto-discovered model."""
    weights, config, labels = find_one_model_path()
    model = {
        "name": "e2e-yolo",
        "enabled": "yes",
        "object_weights": weights,
        "object_config": config,
        "object_labels": labels,
        "object_framework": "opencv",
        "object_processor": "cpu",
        "object_min_confidence": min_confidence,
    }
    if extra_model_keys:
        model.update(extra_model_keys)

    obj_general = {"pattern": pattern}
    if extra_general_keys:
        obj_general.update(extra_general_keys)

    return {
        "general": {"model_sequence": "object"},
        "object": {
            "general": obj_general,
            "sequence": [model],
        },
    }
