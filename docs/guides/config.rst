Configuration Guide
====================

All configuration files use **YAML format**. There are two parts to the configuration of this system:

* The Event Notification Server configuration - typically ``/etc/zm/zmeventnotification.yml``
* The Machine Learning Hooks configuration - typically ``/etc/zm/objectconfig.yml``

The ES comes with a `sample ES config file <https://github.com/pliablepixels/zmeventnotification/blob/master/zmeventnotification.example.yml>`__
which you should customize as fit. The sample config file is well annotated, so you really should read the comments to get an
understanding of what each parameter does. Similarly, the ES also comes with a `sample objectconfig.yml file <https://github.com/pliablepixels/zmeventnotification/blob/master/hook/objectconfig.example.yml>`__
which you should read as well if you are using hooks.

.. note::

    If you are upgrading from an older version that used INI/JSON config files (``zmeventnotification.ini``,
    ``objectconfig.ini``, ``secrets.ini``, ``es_rules.json``), the ``install.sh`` script will automatically
    migrate them to YAML. See :doc:`breaking` for details on the migration.

Secret Tokens
-------------
All the config files have a notion of secrets. Basically, it is a mechanism to separate out your personal passwords and tokens
into a different file from your config file. This allows you to easily share your config files without inadvertently sharing your
secrets.

Basically, this is how it works:

You add a ``secrets`` key in the ``general`` section of either/both config files. This points to some filename you have created with tokens. Then you can just use the token name (prefixed with ``!``) in the config file.

For example, let's suppose we have this in ``/etc/zm/objectconfig.yml``:

::

  general:
    # This is an optional file
    # If specified, you can specify tokens with secret values in that file
    # and only refer to the tokens in your main config file
    secrets: /etc/zm/secrets.yml

    portal: "!ZM_PORTAL"
    user: "!ZM_USER"
    password: "!ZM_PASSWORD"

And ``/etc/zm/secrets.yml`` contains:

::

  secrets:
    ZMES_PICTURE_URL: "https://mysecretportal/zm/index.php?view=image&eid=EVENTID&fid=objdetect&width=600"
    ZM_USER: myusername
    ZM_PASSWORD: mypassword
    ZM_PORTAL: "https://mysecretportal/zm"
    ZM_API_PORTAL: "https://mysecretportal/zm/api"

Then, while parsing the config file every time a value is found that starts with ``!`` that means it's a secret token and the corresponding value from the secrets file will be substituted.

Secret resolution is **recursive** — tokens are resolved throughout the
entire config, including inside nested structures like ``ml_sequence``
and ``stream_sequence``. For example, you can use ``!ALPR_KEY`` inside
an ALPR model entry:

::

  ml:
    ml_sequence:
      alpr:
        sequence:
          - alpr_key: "!ALPR_KEY"

Token matching is **case-insensitive**: ``!ZM_USER``, ``!zm_user``, and
``!Zm_User`` all match a secret named ``ZM_USER`` (or ``zm_user``).

The same concept applies to ``/etc/zm/zmeventnotification.yml``.

**Obviously this means you can no longer have a password beginning with an exclamation mark directly in the config. It will be treated as a secret token**.
To work around this, create a password token in your secrets file and put the real password there.

Key ES Configuration Sections
-------------------------------

The ``zmeventnotification.yml`` file is organized into these sections:

- ``general`` — secrets file path, base data path, ES control interface settings, ``skip_monitors``
- ``network`` — WebSocket port and bind address
- ``auth`` — ZoneMinder user/password authentication and timeout
- ``fcm`` — Firebase Cloud Messaging for push notifications. Supports proxied delivery
  (default via ``fcm_v1_url``) or direct delivery using a Google Service Account
  (``fcm_service_account_file``). Also controls ``replace_push_messages``,
  ``fcm_android_priority``, ``fcm_android_ttl``, and token storage
- ``mqtt`` — MQTT broker settings with optional TLS (one-way or mutual)
- ``ssl`` — SSL certificate/key for the WebSocket server
- ``push`` — third-party push API (e.g. Pushover) via ``api_push_script``
- ``customize`` — event polling intervals, debug levels, picture URL, notification toggles
- ``hook`` — ML hook scripts, notification channel routing, ``max_parallel_hooks``,
  ``tag_detected_objects``, and user scripts

``max_parallel_hooks`` (default ``0`` = unlimited) limits how many hook child
processes can run concurrently. When the limit is reached, new events wait until a
slot is free. This is useful for resource-constrained systems where too many
simultaneous ML detections can cause OOM or GPU contention.

Key Hook Configuration Sections
---------------------------------

The ``objectconfig.yml`` file is organized into these sections:

- ``general`` — ZM portal/API credentials, data paths, debug images,
  ``import_zm_zones``, ``tag_detected_objects``, ``show_models``
- ``push`` — direct FCM push notifications from ``zm_detect`` (Path 1 only, ZM 1.39.2+).
  See :ref:`push_config` below for full details.
- ``remote`` — remote ML server (``pyzm.serve``) gateway URL, mode, credentials, fallback
- ``ml`` — the detection pipeline:

  - ``ml.stream_sequence`` — frame selection: ``frame_set``, ``resize``, retry settings
  - ``ml.ml_sequence.general`` — pipeline-wide settings: ``model_sequence``, ``frame_strategy``,
    ``disable_locks``, ``match_past_detections``, ``max_detection_size``, ``aliases``
  - ``ml.ml_sequence.<type>`` — per-type ``general`` + ``sequence`` lists for object, face, alpr, audio
    (see :doc:`hooks` for full details)

- ``monitors`` — per-monitor overrides for ``wait``, ``ml_sequence``,
  ``stream_sequence``, and ``zones`` (with ``detection_pattern`` and ``ignore_pattern``)

.. _hook_config_reference:

Complete Hook Config Reference
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Every key accepted by ``objectconfig.yml``, grouped by YAML section.
Keys not listed here will be logged as unrecognized and ignored.

.. note::

   Several keys have been moved or removed in 7.x. See :doc:`breaking` for details
   on what changed and migration steps.

**general** — app-level settings consumed by ``zm_detect.py`` / ``utils.py``:

.. list-table::
   :header-rows: 1
   :widths: 28 15 57

   * - Key
     - Default
     - Description
   * - ``secrets``
     - *none*
     - Path to secrets YAML file for ``!TOKEN`` substitution
   * - ``base_data_path``
     - ``/var/lib/zmeventnotification``
     - Base path for model files and data directories
   * - ``portal``
     - ``""``
     - ZoneMinder portal URL (e.g. ``https://zm.example.com/zm``)
   * - ``api_portal``
     - ``""``
     - ZoneMinder API URL (e.g. ``https://zm.example.com/zm/api``)
   * - ``user``
     - *none*
     - ZoneMinder username
   * - ``password``
     - *none*
     - ZoneMinder password
   * - ``allow_self_signed``
     - ``yes``
     - Accept self-signed SSL certificates
   * - ``image_path``
     - ``${base_data_path}/images``
     - Directory for detection images and past-detection files
   * - ``pyzm_overrides``
     - ``{}``
     - Dict of pyzm settings to override (e.g. ``log_level_debug``)
   * - ``wait``
     - ``0``
     - Seconds to sleep before running detection
   * - ``show_percent``
     - ``no``
     - Show confidence percentage in detection output
   * - ``show_models``
     - ``no``
     - Show model name in detection output (e.g. ``(YOLOv11) person``)
   * - ``write_image_to_zm``
     - ``yes``
     - Write annotated image back to ZoneMinder event
   * - ``write_debug_image``
     - ``yes``
     - Write a debug image with all detections to ``image_path``
   * - ``tag_detected_objects``
     - ``no``
     - Write detected labels as ZM Tags (requires ZM >= 1.37.44)
   * - ``poly_color``
     - ``(255,255,255)``
     - RGB color for polygon overlays on annotated images
   * - ``poly_thickness``
     - ``2``
     - Line thickness for polygon overlays (pixels)
   * - ``import_zm_zones``
     - ``no``
     - Import zone definitions from ZoneMinder instead of using config zones
   * - ``only_triggered_zm_zones``
     - ``no``
     - When ``yes``, import only ZM zones that triggered the alarm (forces ``import_zm_zones: yes``)

**remote** — remote ML gateway settings (forwarded to pyzm ``Detector``):

.. list-table::
   :header-rows: 1
   :widths: 28 15 57

   * - Key
     - Default
     - Description
   * - ``ml_gateway``
     - *none*
     - URL of remote ``pyzm.serve`` instance (e.g. ``http://gpu:5000``)
   * - ``ml_gateway_mode``
     - ``url``
     - ``url`` (server fetches frames) or ``image`` (client sends JPEG)
   * - ``ml_user``
     - *none*
     - Username for remote gateway authentication
   * - ``ml_password``
     - *none*
     - Password for remote gateway authentication
   * - ``ml_timeout``
     - ``60``
     - Gateway request timeout in seconds
   * - ``ml_fallback_local``
     - ``no``
     - Fall back to local detection if remote gateway fails

**ml.stream_sequence** — frame extraction settings (read by pyzm ``StreamConfig``):

.. list-table::
   :header-rows: 1
   :widths: 28 15 57

   * - Key
     - Default
     - Description
   * - ``frame_set``
     - ``snapshot,alarm,1``
     - Comma-separated list of frames to extract (``snapshot``, ``alarm``, or numeric IDs)
   * - ``resize``
     - *none*
     - Resize frames to this width (pixels) before detection. Omit for original resolution.
   * - ``max_frames``
     - ``0``
     - Maximum frames to extract (``0`` = no limit)
   * - ``start_frame``
     - ``1``
     - First frame index to consider
   * - ``frame_skip``
     - ``1``
     - Process every Nth frame
   * - ``contig_frames_before_error``
     - ``5``
     - Contiguous frame errors before giving up
   * - ``max_attempts``
     - ``1``
     - Retries per frame on failure
   * - ``sleep_between_attempts``
     - ``3``
     - Seconds between retries
   * - ``save_frames``
     - ``no``
     - Save extracted frames to disk
   * - ``save_frames_dir``
     - ``/tmp``
     - Directory for saved frames
   * - ``convert_snapshot_to_fid``
     - ``yes``
     - Convert snapshot frame to its actual frame ID

**ml.ml_sequence.general** — detection pipeline settings (read by pyzm ``DetectorConfig``):

.. list-table::
   :header-rows: 1
   :widths: 28 15 57

   * - Key
     - Default
     - Description
   * - ``model_sequence``
     - ``object``
     - Comma-separated model types to run (``object``, ``face``, ``alpr``, ``audio``)
   * - ``frame_strategy``
     - ``most_models``
     - How to pick the best frame: ``most_models``, ``first``, ``first_new``, ``most``, ``most_unique``
   * - ``same_model_sequence_strategy``
     - ``first``
     - How to combine results from multiple models of the same type: ``first``, ``most``, ``most_unique``, ``union``
   * - ``disable_locks``
     - ``no``
     - Disable file-based locking for model execution
   * - ``match_past_detections``
     - ``no``
     - Deduplicate static objects across successive detections
   * - ``past_det_max_diff_area``
     - ``5%``
     - Area difference threshold for past-detection matching
   * - ``<label>_past_det_max_diff_area``
     - —
     - Per-label override (e.g. ``car_past_det_max_diff_area: 10%``)
   * - ``ignore_past_detection_labels``
     - ``[]``
     - Labels to never deduplicate (e.g. ``['dog', 'cat']``)
   * - ``max_detection_size``
     - *none*
     - Maximum bounding box size to accept (pixels or percentage, e.g. ``90%``)
   * - ``pattern``
     - ``.*``
     - Global regex pattern for accepted labels
   * - ``aliases``
     - ``[]``
     - Groups of labels to treat as equivalent (e.g. ``[['car','bus','truck']]``)

**ml.ml_sequence.<type>** — per-type settings (``object``, ``face``, ``alpr``, ``audio``):

Each type has a ``general`` section for overrides and a ``sequence`` list of model
configurations. See :doc:`hooks` for details on model-specific keys (``object_weights``,
``face_detection_framework``, ``alpr_service``, etc.).

**push** — direct FCM push notifications:

See :ref:`push_config` below.

**monitors** — per-monitor overrides:

Any key from the sections above can be overridden per monitor. Dict values
(``ml_sequence``, ``stream_sequence``) are deep-merged; scalar values are replaced.
See :doc:`hooks` for zone configuration (``detection_pattern``, ``ignore_pattern``).

.. _push_config:

Direct Push Notifications (``push`` section)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The ``push`` section in ``objectconfig.yml`` configures direct FCM push notifications
from ``zm_detect`` — **Path 1 only**, requires ZM 1.39.2+. ``zm_detect`` reads registered
tokens from ZM's ``Notifications`` table via pyzm and sends push notifications through an
FCM cloud function proxy after detection.

**Key settings:**

- ``enabled`` — ``yes``/``no`` (default ``no``)
- ``fcm_v1_url`` — URL of the FCM cloud function proxy. Pre-configured with the
  managed zmNg default (same proxy used by the ES). Replace only if you run your
  own cloud function.
- ``fcm_v1_key`` — authorization key for the cloud function proxy. Pre-configured
  with the managed zmNg default. Replace only if you run your own cloud function.
- ``replace_push_messages`` — ``yes`` to collapse notifications per monitor
- ``include_picture`` — ``yes`` to include event image URL in the notification
- ``android_priority`` — FCM priority (``high`` or ``normal``)
- ``android_ttl`` — optional TTL in seconds

**Setup steps:**

1. Ensure ZoneMinder is 1.39.2+ (adds the Notifications REST API).
2. Set ``push.enabled`` to ``yes`` in ``objectconfig.yml``.
   The cloud function URL and key are pre-configured with the managed zmNg
   defaults (same as the ES) — no additional configuration needed.
3. Register device tokens: client apps (e.g. zmNg) register FCM tokens via
   the ZM ``/api/notifications.json`` REST endpoint. Tokens are stored in ZM's
   ``Notifications`` database table.

If you run your own FCM cloud function proxy, replace ``fcm_v1_url`` and
``fcm_v1_key`` with your own values.

``zm_detect`` respects per-token monitor filtering, throttle intervals,
and push state. Invalid tokens are automatically cleaned up.

Configuration Tools
---------------------

Several tools are provided in the ``tools/`` directory of the source tree:

- ``tools/install_doctor.py`` — post-install diagnostic checker. Validates GPU/CUDA availability,
  OpenCV version, model file paths, file permissions, SSL certificates, and Perl/Python dependencies.
  Run automatically by ``install.sh`` at the end of installation. See :doc:`install_path1` for usage.
- ``tools/config_migrate_yaml.py`` — migrates ``objectconfig.ini`` to ``objectconfig.yml``
- ``tools/es_config_migrate_yaml.py`` — migrates ``zmeventnotification.ini`` and ``secrets.ini``
  to their YAML equivalents
- ``tools/config_upgrade_yaml.py`` — merges new keys from example configs into your existing YAML
  config (used during upgrades to add new options without overwriting your settings)
- ``tools/config_edit.py`` — programmatic config editor

See :doc:`breaking` for details on the INI-to-YAML migration.
