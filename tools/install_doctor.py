#!/usr/bin/env python3
"""Post-install diagnostic checks for objectconfig.yml.

Parses the installed config and checks for common mismatches between
enabled models and system capabilities (CUDA, face_recognition, OpenCV).

Usage: python3 tools/install_doctor.py <path-to-objectconfig.yml>
"""

import sys

COLOR_WARN = "\033[0;33m"
COLOR_RESET = "\033[0m"


def collect_enabled_models(cfg):
    """Return list of (section_key, model_dict) for all enabled models."""
    ml_section = cfg.get("ml", {}) if cfg else {}
    ml = ml_section.get("ml_sequence", {}) if isinstance(ml_section, dict) else {}

    enabled = []
    for section_key in ("object", "face", "alpr"):
        section = ml.get(section_key, {})
        if not isinstance(section, dict):
            continue
        for model in section.get("sequence", []):
            if not isinstance(model, dict):
                continue
            if str(model.get("enabled", "no")).lower() in ("yes", "true", "1"):
                enabled.append((section_key, model))
    return enabled


def check_gpu_cuda(enabled_models, config_path):
    """Warn if GPU processing is configured but no CUDA devices are available."""
    gpu_models = [
        (s, m) for s, m in enabled_models
        if str(m.get("object_processor", "")).lower() == "gpu"
    ]
    if not gpu_models:
        return None

    try:
        import cv2
        cuda_count = cv2.cuda.getCudaEnabledDeviceCount()
    except Exception:
        cuda_count = 0

    if cuda_count == 0:
        names = ", ".join(m.get("name", "unknown") for _, m in gpu_models)
        return (
            f"GPU processing configured but no CUDA devices found.\n"
            f"    Affected models: {names}\n"
            f"    Change object_processor to 'cpu' in {config_path} or install CUDA."
        )
    return None


def check_face_recognition(enabled_models):
    """Warn if DLIB face detection is enabled but face_recognition is missing."""
    face_dlib_models = [
        (s, m) for s, m in enabled_models
        if s == "face" and str(m.get("face_detection_framework", "")).lower() == "dlib"
    ]
    if not face_dlib_models:
        return None

    try:
        import face_recognition  # noqa: F401
        return None
    except ImportError:
        names = ", ".join(m.get("name", "unknown") for _, m in face_dlib_models)
        return (
            f"face_recognition package is not installed but DLIB face detection is enabled.\n"
            f"    Affected models: {names}\n"
            f"    Install it with: pip3 install face_recognition"
        )


def check_opencv_version(enabled_models):
    """Warn if OpenCV is too old for enabled ONNX/YOLOv26 or YOLOv4 models."""
    try:
        import cv2
        cv_ver = tuple(int(x) for x in cv2.__version__.split(".")[:2])
    except Exception:
        cv_ver = (0, 0)
    cv_ver_str = ".".join(str(x) for x in cv_ver) if cv_ver != (0, 0) else "not installed"

    onnx_models = []
    v4_models = []
    for s, m in enabled_models:
        weights = str(m.get("object_weights", ""))
        name_lower = str(m.get("name", "")).lower()
        if weights.endswith(".onnx") or "yolov26" in name_lower:
            onnx_models.append((s, m))
        elif "yolov4" in name_lower:
            v4_models.append((s, m))

    warnings = []
    if onnx_models and cv_ver < (4, 13):
        names = ", ".join(m.get("name", "unknown") for _, m in onnx_models)
        warnings.append(
            f"OpenCV {cv_ver_str} detected but 4.13+ is required for ONNX YOLOv26 models.\n"
            f"    Affected models: {names}\n"
            f"    Upgrade OpenCV, or disable YOLOv26 and enable YOLOv4 instead (works with OpenCV 4.4+)."
        )

    if v4_models and cv_ver < (4, 4):
        names = ", ".join(m.get("name", "unknown") for _, m in v4_models)
        warnings.append(
            f"OpenCV {cv_ver_str} detected but 4.4+ is required for YOLOv4 models.\n"
            f"    Affected models: {names}\n"
            f"    Upgrade OpenCV or disable these models."
        )

    return warnings


def main():
    config_path = sys.argv[1]

    try:
        import yaml
    except ImportError:
        print("  Skipping doctor checks (pyyaml not installed)")
        return

    try:
        with open(config_path) as f:
            cfg = yaml.safe_load(f)
    except Exception as e:
        print(f"  Skipping doctor checks (could not parse config: {e})")
        return

    enabled_models = collect_enabled_models(cfg)

    warnings = []
    w = check_gpu_cuda(enabled_models, config_path)
    if w:
        warnings.append(w)

    w = check_face_recognition(enabled_models)
    if w:
        warnings.append(w)

    warnings.extend(check_opencv_version(enabled_models))

    if warnings:
        for w in warnings:
            print(f"{COLOR_WARN}WARNING:{COLOR_RESET} {w}")
    else:
        print("  All checks passed.")


if __name__ == "__main__":
    main()
