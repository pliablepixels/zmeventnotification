## Key Changes: ES 7.x (ongoing)

### Remote ML: pyzm.serve replaces mlapi
- **`pyzm.serve` is the new built-in remote ML server** — replaces the separate `mlapi` package
- Server: `pip install pyzm[serve]` then `python -m pyzm.serve --models yolov4 --port 5000`
- Client: set `ml_gateway` in `objectconfig.yml` `remote:` section to server URL
- No more `mlapiconfig.ini` — all config stays in `objectconfig.yml`
- Optional JWT authentication (`--auth` flag on server)
- `zm_detect.py` simplified: `remote_detect()` function removed, `Detector` handles remote mode transparently
- **NEW: URL-mode remote detection** (`ml_gateway_mode: "url"`) — the server fetches frames
  directly from ZoneMinder instead of having the client upload JPEG data. More efficient when
  the GPU box has direct network access to ZM. Falls back gracefully to image mode.

## Key Changes: ES 7.0 vs ES 6.x

### Configuration: Full migration from INI/JSON to YAML
- **All config files migrated to YAML** — `zmeventnotification.ini`, `secrets.ini`, `es_rules.json`, and `objectconfig.ini` are replaced by `.yml` equivalents
- Legacy INI/JSON files moved to `legacy/` directory for reference
- Migration tools provided: `config_migrate_yaml.py`, `es_config_migrate_yaml.py`, `config_upgrade_yaml.py`
- The `{{}}` templating system in objectconfig is removed; `ml_sequence` is now inlined directly in YAML

### Object Detection: YOLOv26 ONNX via OpenCV DNN
- **Added support for YOLOv26 ONNX models** — supposed to be accuracy improvement. You will need to upgrade OpenCV 
- Installer (`install.sh`) can download ONNX models automatically (`INSTALL_YOLOV11` flag)

### Architecture: Modular Perl codebase
- **Monolithic `zmeventnotification.pl` broken into 10 modules** under `ZmEventNotification/` (Config, DB, Rules, FCM, MQTT, HookProcessor, WebSocketHandler, etc.)
- ~60 individual config variables replaced with 10 grouped hashes
- Logging switched from custom `printDebug/printInfo/printError` to ZoneMinder's native logging

### New Features
- **Detected objects are now tagged in the ZoneMinder database** (Tags table with CreateDate)
- `fcm_service_account_file` config option added for FCM auth (if you are compiling zmNg from source, you don't need a central push server)

### Installer Improvements
- Dependency checks and Perl module auto-install added

### Testing
- Comprehensive Perl test suite added (`t/`) covering constants, config parsing, rules, hook processor logic, and contract formatting
- Test fixtures with sample YAML configs
