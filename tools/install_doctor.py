#!/usr/bin/env python3
"""Post-install diagnostic checks for ZoneMinder Event Notification Server.

Parses the installed objectconfig.yml and zmeventnotification.yml and
cross-references with system capabilities to catch common misconfigurations.

Usage:
    python3 tools/install_doctor.py \
        --hook-config /etc/zm/objectconfig.yml \
        --es-config /etc/zm/zmeventnotification.yml \
        --web-owner www-data --web-group www-data \
        --base-data /var/lib/zmeventnotification
"""

import argparse
import importlib
import os
import pwd
import shutil
import stat
import sys

COLOR_WARN = "\033[0;33m"
COLOR_RESET = "\033[0m"


def load_yaml(path):
    """Load a YAML file, returning None on failure."""
    if not path or not os.path.isfile(path):
        return None
    try:
        import yaml
        with open(path) as f:
            return yaml.safe_load(f)
    except Exception:
        return None


def resolve_path(raw, base_data_path):
    """Expand ${base_data_path} and {{base_data_path}} in a config path."""
    if not raw:
        return raw
    s = str(raw)
    s = s.replace("${base_data_path}", base_data_path)
    s = s.replace("{{base_data_path}}", base_data_path)
    return s


def uid_for_user(username):
    """Return the UID for a username, or None."""
    try:
        return pwd.getpwnam(username).pw_uid
    except KeyError:
        return None


# ---------------------------------------------------------------------------
# Model / hook-config checks
# ---------------------------------------------------------------------------

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
    """Warn if OpenCV is too old for enabled ONNX YOLOv11/YOLOv26 or YOLOv4 models."""
    try:
        import cv2
        cv_ver = tuple(int(x) for x in cv2.__version__.split(".")[:2])
    except Exception:
        cv_ver = (0, 0)
    cv_ver_str = ".".join(str(x) for x in cv_ver) if cv_ver != (0, 0) else "not installed"

    onnx_v26_models = []
    onnx_v11_models = []
    v4_models = []
    for s, m in enabled_models:
        weights = str(m.get("object_weights", ""))
        name_lower = str(m.get("name", "")).lower()
        if "yolo26" in weights or "yolov26" in name_lower:
            onnx_v26_models.append((s, m))
        elif weights.endswith(".onnx") or "yolo11" in weights or "yolov11" in name_lower:
            onnx_v11_models.append((s, m))
        elif "yolov4" in name_lower:
            v4_models.append((s, m))

    warnings = []
    if onnx_v26_models and cv_ver < (4, 13):
        names = ", ".join(m.get("name", "unknown") for _, m in onnx_v26_models)
        warnings.append(
            f"OpenCV {cv_ver_str} detected but 4.13+ is required for ONNX YOLOv26 models.\n"
            f"    Affected models: {names}\n"
            f"    Upgrade OpenCV, or switch to YOLOv11 (requires 4.13+) or YOLOv4 (requires 4.4+)."
        )

    if onnx_v11_models and cv_ver < (4, 13):
        names = ", ".join(m.get("name", "unknown") for _, m in onnx_v11_models)
        warnings.append(
            f"OpenCV {cv_ver_str} detected but 4.13+ is required for ONNX YOLOv11 models.\n"
            f"    Affected models: {names}\n"
            f"    Upgrade OpenCV, or switch to YOLOv4 (requires 4.4+)."
        )

    if v4_models and cv_ver < (4, 4):
        names = ", ".join(m.get("name", "unknown") for _, m in v4_models)
        warnings.append(
            f"OpenCV {cv_ver_str} detected but 4.4+ is required for YOLOv4 models.\n"
            f"    Affected models: {names}\n"
            f"    Upgrade OpenCV or disable these models."
        )

    return warnings


def check_model_files(enabled_models, base_data_path):
    """Warn if weight/config/label files referenced by enabled models are missing."""
    file_keys = (
        "object_weights", "object_config", "object_labels",
        "face_weights",
    )
    warnings = []
    for _, m in enabled_models:
        name = m.get("name", "unknown")
        for key in file_keys:
            raw = m.get(key)
            if not raw:
                continue
            path = resolve_path(raw, base_data_path)
            if not os.path.isfile(path):
                warnings.append(
                    f"Model '{name}' references {key}={raw}\n"
                    f"    but {path} does not exist.\n"
                    f"    Re-run install.sh with DOWNLOAD_MODELS=yes or disable this model."
                )
    return warnings


def check_known_faces_empty(enabled_models, base_data_path):
    """Warn if face recognition is enabled but known_faces dir is empty."""
    for s, m in enabled_models:
        if s != "face":
            continue
        raw = m.get("known_images_path")
        if not raw:
            continue
        path = resolve_path(raw, base_data_path)
        if not os.path.isdir(path):
            continue
        # known_faces should have at least one subdirectory (one person)
        subdirs = [d for d in os.listdir(path)
                    if os.path.isdir(os.path.join(path, d))]
        if not subdirs:
            return (
                f"Face recognition is enabled (model '{m.get('name', 'unknown')}') but\n"
                f"    {path} has no subdirectories.\n"
                f"    Add face image directories (one per person) or face recognition will always return 'unknown'."
            )
    return None


def check_animation_deps(hook_cfg):
    """Warn if animation is enabled but gifsicle is not installed."""
    anim = hook_cfg.get("animation", {}) if hook_cfg else {}
    if not isinstance(anim, dict):
        return None
    if str(anim.get("create_animation", "no")).lower() not in ("yes", "true", "1"):
        return None
    if shutil.which("gifsicle") is None:
        return (
            "Animation is enabled (animation.create_animation: yes) but gifsicle is not in PATH.\n"
            "    Install it with: apt-get install gifsicle"
        )
    return None


# ---------------------------------------------------------------------------
# ES config checks
# ---------------------------------------------------------------------------

def check_secrets_file(es_cfg, web_owner):
    """Warn if the secrets file is missing or unreadable by the web user."""
    if not es_cfg:
        return None
    general = es_cfg.get("general", {})
    if not isinstance(general, dict):
        return None
    secrets_path = general.get("secrets")
    if not secrets_path:
        return None

    if not os.path.isfile(secrets_path):
        return (
            f"Secrets file not found: {secrets_path}\n"
            f"    Referenced by general.secrets in zmeventnotification.yml.\n"
            f"    Create it or update the path."
        )

    uid = uid_for_user(web_owner)
    if uid is not None:
        st = os.stat(secrets_path)
        world_readable = st.st_mode & stat.S_IROTH
        owner_match = st.st_uid == uid
        if not owner_match and not world_readable:
            return (
                f"Secrets file {secrets_path} may not be readable by '{web_owner}'.\n"
                f"    Run: chown {web_owner} {secrets_path}"
            )
    return None


def check_ssl_files(es_cfg):
    """Warn if SSL is enabled but cert/key files are missing."""
    if not es_cfg:
        return None
    ssl = es_cfg.get("ssl", {})
    if not isinstance(ssl, dict):
        return None
    if str(ssl.get("enable", "no")).lower() not in ("yes", "true", "1"):
        return None

    warnings = []
    for key, label in (("cert", "certificate"), ("key", "private key")):
        val = ssl.get(key, "")
        # skip secret token references like !ES_CERT_FILE
        if not val or str(val).startswith("!"):
            continue
        if not os.path.isfile(val):
            warnings.append(
                f"SSL is enabled but {label} file not found: {val}\n"
                f"    Update ssl.{key} in zmeventnotification.yml or disable SSL."
            )
    return warnings


def check_mqtt_deps(es_cfg):
    """Warn if MQTT is enabled but Perl module is missing."""
    if not es_cfg:
        return None
    mqtt = es_cfg.get("mqtt", {})
    if not isinstance(mqtt, dict):
        return None
    if str(mqtt.get("enable", "no")).lower() not in ("yes", "true", "1"):
        return None

    import subprocess
    result = subprocess.run(
        ["perl", "-MNet::MQTT::Simple", "-e1"],
        capture_output=True,
    )
    if result.returncode != 0:
        return (
            "MQTT is enabled but Net::MQTT::Simple Perl module is not installed.\n"
            "    Install it with: sudo cpanm Net::MQTT::Simple"
        )
    return None


def check_fcm_deps(es_cfg):
    """Warn if FCM is enabled but LWP::Protocol::https is missing."""
    if not es_cfg:
        return None
    fcm = es_cfg.get("fcm", {})
    if not isinstance(fcm, dict):
        return None
    if str(fcm.get("enable", "no")).lower() not in ("yes", "true", "1"):
        return None

    import subprocess
    result = subprocess.run(
        ["perl", "-MLWP::Protocol::https", "-e1"],
        capture_output=True,
    )
    if result.returncode != 0:
        return (
            "FCM push notifications are enabled but LWP::Protocol::https Perl module is not installed.\n"
            "    Install it with: sudo apt-get install liblwp-protocol-https-perl"
        )
    return None


# ---------------------------------------------------------------------------
# File permission checks
# ---------------------------------------------------------------------------

def check_file_permissions(paths, web_owner, need_write=False):
    """Warn if files/dirs are not accessible by the web user."""
    uid = uid_for_user(web_owner)
    if uid is None:
        return []

    warnings = []
    for path, description in paths:
        if not os.path.exists(path):
            continue
        st = os.stat(path)
        owner_match = st.st_uid == uid

        # Check read
        if owner_match:
            readable = st.st_mode & stat.S_IRUSR
        else:
            readable = st.st_mode & stat.S_IROTH
        if not readable:
            warnings.append(
                f"{description} ({path}) is not readable by '{web_owner}'.\n"
                f"    Run: chown {web_owner} {path}"
            )
            continue

        # Check write if needed
        if need_write:
            if owner_match:
                writable = st.st_mode & stat.S_IWUSR
            else:
                writable = st.st_mode & stat.S_IWOTH
            if not writable:
                warnings.append(
                    f"{description} ({path}) is not writable by '{web_owner}'.\n"
                    f"    Run: chown {web_owner} {path}"
                )
    return warnings


# ---------------------------------------------------------------------------
# Python dependency checks
# ---------------------------------------------------------------------------

def check_pyzm():
    """Warn if pyzm is not installed or too old."""
    try:
        import pyzm  # noqa: F401
    except ImportError:
        return (
            "pyzm package is not installed. Detection hooks will not work.\n"
            "    Install it with: pip3 install pyzm"
        )

    try:
        from importlib.metadata import version as pkg_version
        ver = pkg_version("pyzm")
        parts = [int(x) for x in ver.split(".")[:2]]
        if parts < [0, 4]:
            return (
                f"pyzm {ver} is installed but >= 0.4.0 is required.\n"
                f"    Upgrade with: pip3 install --upgrade pyzm"
            )
    except Exception:
        pass
    return None


def check_python_deps():
    """Warn if core Python packages required by hooks are missing."""
    deps = {
        "numpy": "numpy",
        "requests": "requests",
        "shapely": "Shapely",
        "imutils": "imutils",
    }
    missing = []
    for module, pip_name in deps.items():
        try:
            importlib.import_module(module)
        except ImportError:
            missing.append(pip_name)
    if missing:
        return (
            f"Missing Python packages required by hooks: {', '.join(missing)}\n"
            f"    Install with: pip3 install {' '.join(missing)}"
        )
    return None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Post-install doctor checks")
    parser.add_argument("--hook-config", default="")
    parser.add_argument("--es-config", default="")
    parser.add_argument("--web-owner", default="www-data")
    parser.add_argument("--web-group", default="www-data")
    parser.add_argument("--base-data", default="/var/lib/zmeventnotification")
    args = parser.parse_args()

    try:
        import yaml  # noqa: F401
    except ImportError:
        print("  Skipping doctor checks (pyyaml not installed)")
        return

    hook_cfg = load_yaml(args.hook_config)
    es_cfg = load_yaml(args.es_config)

    if not hook_cfg and not es_cfg:
        print("  Skipping doctor checks (no config files found)")
        return

    warnings = []

    # --- Hook config checks ---
    if hook_cfg:
        enabled_models = collect_enabled_models(hook_cfg)
        base = hook_cfg.get("general", {}).get("base_data_path", args.base_data)

        w = check_gpu_cuda(enabled_models, args.hook_config)
        if w:
            warnings.append(w)

        w = check_face_recognition(enabled_models)
        if w:
            warnings.append(w)

        warnings.extend(check_opencv_version(enabled_models))
        warnings.extend(check_model_files(enabled_models, base))

        w = check_known_faces_empty(enabled_models, base)
        if w:
            warnings.append(w)

        w = check_animation_deps(hook_cfg)
        if w:
            warnings.append(w)

        # Config file permissions
        perm_paths = []
        if os.path.isfile(args.hook_config):
            perm_paths.append((args.hook_config, "Hook config"))
        warnings.extend(check_file_permissions(perm_paths, args.web_owner))

        # Writable directories
        write_dirs = []
        for d, desc in (
            (os.path.join(base, "images"), "Images directory"),
            (os.path.join(base, "unknown_faces"), "Unknown faces directory"),
        ):
            if os.path.isdir(d):
                write_dirs.append((d, desc))
        warnings.extend(
            check_file_permissions(write_dirs, args.web_owner, need_write=True)
        )

    # --- ES config checks ---
    if es_cfg:
        w = check_secrets_file(es_cfg, args.web_owner)
        if w:
            warnings.append(w)

        ws = check_ssl_files(es_cfg)
        if ws:
            warnings.extend(ws)

        w = check_mqtt_deps(es_cfg)
        if w:
            warnings.append(w)

        w = check_fcm_deps(es_cfg)
        if w:
            warnings.append(w)

        if os.path.isfile(args.es_config):
            warnings.extend(check_file_permissions(
                [(args.es_config, "ES config")], args.web_owner,
            ))

    # --- Python dependency checks ---
    w = check_pyzm()
    if w:
        warnings.append(w)

    w = check_python_deps()
    if w:
        warnings.append(w)

    # --- Results ---
    if warnings:
        for w in warnings:
            print(f"{COLOR_WARN}WARNING:{COLOR_RESET} {w}")
    else:
        print("  All checks passed.")


if __name__ == "__main__":
    main()
