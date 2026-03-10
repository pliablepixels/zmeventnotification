Breaking Changes
----------------

pyzm v2 and pyzm.serve (ES 7.x)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

pyzm has been rewritten as v2. This is the ML detection library used by ``zm_detect.py``.
The key changes that affect ES users:

**What changed:**

- ``mlapi`` **is replaced by** ``pyzm.serve`` — the remote ML detection server is now built
  into pyzm itself. No separate ``mlapi`` package or ``mlapiconfig.ini`` needed.
- **``Detector`` is the single entry point** — replaces ``DetectSequence``, ``ObjectDetect``,
  ``FaceDetect``, and other scattered classes. ``zm_detect.py`` now uses ``Detector.from_dict()``
  and ``Detector.detect_event()`` instead of calling ML backends directly.
- **Pydantic v2 configuration** — ``DetectorConfig``, ``ModelConfig``, ``StreamConfig`` replace
  the old dict-based config parsing. Your ``objectconfig.yml`` format is unchanged (``from_dict()``
  handles the conversion), but the underlying code is stricter about typos and invalid values.
- **Typed detection results** — ``DetectionResult`` with ``.labels``, ``.summary``,
  ``.annotate()`` replaces the old ``matched_data`` nested dicts.
- **Python 3.10+ required** — pyzm v2 uses ``match`` statements, union type syntax (``X | Y``),
  and other modern Python features.

**What you need to do:**

1. **Install pyzm v2**: ``pip install pyzm`` (or let ``install.sh`` handle it)
2. **If using remote ML**: Replace ``mlapi`` with ``pyzm.serve``:

   - On the GPU box: ``pip install pyzm[serve]`` then ``python -m pyzm.serve --models yolo11s --port 5000``
   - In ``objectconfig.yml``: use the ``remote:`` section with ``ml_gateway`` (see below)
   - Delete ``mlapiconfig.ini`` — it is no longer used

3. **New: URL-mode remote detection**: If your GPU box can reach ZoneMinder directly,
   set ``ml_gateway_mode: "url"`` in the ``remote:`` section. The server will fetch frames
   directly from ZM instead of having them uploaded by the ZM box. This is more efficient.

4. **No changes to objectconfig.yml format** — the ``ml_sequence`` and ``stream_sequence``
   YAML structures are fully backward compatible. ``Detector.from_dict()`` reads them
   identically.

**Remote ML config** — before (``mlapi``) vs. after (``pyzm.serve``):

Before (``objectconfig.yml`` with ``mlapi``):

.. code-block:: yaml

   remote:
     ml_gateway: "http://gpu-box:5000"
     # Also needed: mlapiconfig.ini on the GPU box

After (``objectconfig.yml`` with ``pyzm.serve``):

.. code-block:: yaml

   remote:
     ml_gateway: "http://gpu-box:5000"
     ml_gateway_mode: "url"          # NEW — "image" (default) or "url"
     ml_fallback_local: "yes"
     ml_user: "!ML_USER"
     ml_password: "!ML_PASSWORD"
     ml_timeout: 60

On the GPU box, start with::

   pip install pyzm[serve]
   python -m pyzm.serve --models yolo11s --port 5000 --auth --auth-user admin --auth-password secret


Frame Match Type Setting Moved (7.x)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The ``keep_frame_match_type`` setting has been **removed from the ES config**
(``zmeventnotification.yml``) and replaced by ``show_frame_match_type`` in
``objectconfig.yml`` under the ``general:`` section.

**What changed:**

- The ES no longer strips the ``[a]``/``[s]``/``[x]`` prefix from detection
  output. Instead, the hook itself decides whether to include it.
- ``show_frame_match_type: "yes"`` (default) includes the prefix — same
  behavior as the old ``keep_frame_match_type: "yes"``.
- ``show_frame_match_type: "no"`` suppresses the prefix entirely, both when
  running ``zm_detect.py`` directly and when the ES sends push notifications.

**What you need to do:**

Running ``install.sh`` handles most of this automatically:

- ``keep_frame_match_type`` is **automatically removed** from your
  ``zmeventnotification.yml`` during upgrade.
- ``show_frame_match_type`` is **automatically added** to your
  ``objectconfig.yml`` with the default value of ``"yes"``.

**Manual step (only if you had ``keep_frame_match_type: "no"``):**

If you previously set ``keep_frame_match_type: "no"`` in your ES config to
hide the prefix, you need to manually set ``show_frame_match_type: "no"`` in
the ``general:`` section of your ``objectconfig.yml`` after running
``install.sh``.


Config Cleanup (7.x)
~~~~~~~~~~~~~~~~~~~~~~

Several config keys have been moved, removed, or fixed. If you have a custom
``objectconfig.yml``, review the changes below. Running ``install.sh`` will
automatically merge new defaults from the example config.

**Keys removed:**

- ``general.version`` — was never read by any code
- ``general.delete_after_analyze`` — was never read by ``zm_detect.py``
- ``general.cpu_max_processes``, ``general.tpu_max_processes``, ``general.gpu_max_processes`` — pyzm
  reads these per-model from ``ml_sequence`` items, not from flat config
- ``general.cpu_max_lock_wait``, ``general.tpu_max_lock_wait``, ``general.gpu_max_lock_wait`` — same reason
- ``animation`` section (``create_animation``, ``animation_types``, ``animation_width``,
  ``animation_retry_sleep``, ``animation_max_tries``, ``fast_gif``) — animation support removed entirely

**Keys moved to correct section:**

- ``ml.stream_sequence.frame_strategy`` → ``ml.ml_sequence.general.frame_strategy`` —
  ``StreamConfig`` ignores this key; ``DetectorConfig`` reads it from ``ml_sequence.general``
- ``ml.disable_locks`` → ``ml.ml_sequence.general.disable_locks`` —
  was a sibling of ``ml_sequence``/``stream_sequence`` and never reached pyzm
- ``monitors.<id>.resize`` → ``monitors.<id>.stream_sequence.resize`` —
  top-level ``resize`` in a monitor override was stored in ``g.config`` but pyzm reads it
  from ``stream_sequence``
- ``monitors.<id>.match_past_detections`` → ``monitors.<id>.ml_sequence.general.match_past_detections`` —
  same issue: top-level copy never reached pyzm

**Default changed:**

- ``stream_sequence.resize`` default changed from ``800`` to ``None`` (no resize). You must now
  explicitly set ``resize: 800`` (or another value) in ``stream_sequence`` if you want frame
  downscaling before detection.

**No action required** if you run ``install.sh`` — it merges new keys from the example config
via ``config_upgrade_yaml.py``. If you maintain your config manually, apply the moves listed above.

YAML Migration (current master)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This is a **major breaking change**. All configuration files have been migrated from INI/JSON to YAML format:

- ``zmeventnotification.ini`` → ``zmeventnotification.yml``
- ``secrets.ini`` → ``secrets.yml``
- ``objectconfig.ini`` → ``objectconfig.yml``
- ``es_rules.json`` → ``es_rules.yml``

The old INI/JSON files have been moved to the ``legacy/`` directory for reference. The ``install.sh`` script
will automatically migrate your existing INI/JSON configs to YAML if you have old configs and no YAML
equivalents. The old files will be renamed with a ``.migrated`` suffix.

**Key changes:**

- **YAML format** — All config files now use YAML syntax instead of INI sections/key-value pairs.
  For example, ``[general]`` sections become ``general:`` with indented keys beneath them.
- **Secrets file** — Now ``/etc/zm/secrets.yml``. The ``!TOKEN_NAME`` syntax for referencing secrets
  remains the same. The secrets file itself uses a top-level ``secrets:`` key with tokens underneath.
- **Templating removed** — ``objectconfig.yml`` no longer supports ``{{variable}}`` template
  substitution. All values in ``ml_sequence`` and ``stream_sequence`` are specified directly/inline.
  The ``use_sequence`` flag no longer exists — sequences are always used.
- **Parameter substitution removed** — ``common_params.py`` and its substitution engine have been
  removed. ``${base_data_path}`` is the only substitution still supported (for path expansion).
- **Default model changed to YOLO ONNX** — YOLOv3 defaults are now disabled. The default enabled
  model is ``yolo11n`` using ONNX format via OpenCV DNN. This requires **OpenCV 4.13+**.
  Direct Ultralytics/PyTorch support has been removed in favor of ONNX via OpenCV DNN.
- **Perl config module changed** — The ES now uses ``YAML::XS`` (via the
  ``libyaml-libyaml-perl`` package on Debian/Ubuntu) instead of ``Config::IniFiles``.
- **Rules file is now YAML** — ``es_rules.json`` has been replaced by ``es_rules.yml``.
  The ``install.sh`` script will auto-convert the old JSON file.
- **New migration tools** — ``tools/config_upgrade.py`` has been replaced by:

  - ``tools/config_upgrade_yaml.py`` — upgrades an existing YAML config with new keys from the example
  - ``tools/es_config_migrate_yaml.py`` — migrates ES INI config and secrets to YAML
  - ``tools/config_migrate_yaml.py`` — migrates ``objectconfig.ini`` to YAML

- **New feature: tag_detected_objects** — When set to ``yes`` in the ``hook`` section of
  ``zmeventnotification.yml``, detected object labels (e.g. person, cat) will be written as Tags
  into ZoneMinder's database. Requires ZM >= 1.37.44.

- **Install flags changed** — ``INSTALL_YOLOV11`` / ``INSTALL_YOLOV26`` now default to ``yes``.
  ``install.sh`` downloads both YOLOv11 and YOLOv26 ONNX models by default.
  YOLOv3 defaults are now ``no``. Set either flag to ``no`` to skip.

**Upgrading:**

1. Run ``sudo ./install.sh`` — it will auto-detect old INI/JSON files and migrate them to YAML
2. Review the generated ``.yml`` files and verify the migration looks correct
3. Old files are renamed to ``*.migrated`` and originals are in the ``legacy/`` directory for reference
4. If you had custom ``{{}}`` templates in ``objectconfig.ini``, you will need to manually inline
   those values in ``objectconfig.yml`` as templating is no longer supported


