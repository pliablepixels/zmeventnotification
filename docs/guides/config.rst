Configuration Guide
====================

All configuration files use **YAML format**. There are two parts to the configuration of this system:

* The Event Notification Server configuration — typically ``/etc/zm/zmeventnotification.yml``
* The Machine Learning Detection Hook configuration — typically ``/etc/zm/objectconfig.yml``

The ES comes with a `sample ES config file <https://github.com/pliablepixels/zmeventnotification/blob/master/zmeventnotification.example.yml>`__
which you should customize as fit. The sample config file is well annotated, so you really should read the comments to get an
understanding of what each parameter does. Similarly, the ES also comes with a `sample objectconfig.yml file <https://github.com/pliablepixels/zmeventnotification/blob/master/hook/objectconfig.example.yml>`__
which you should read as well if you are using hooks.

.. note::

    If you are upgrading from an older version that used INI/JSON config files (``zmeventnotification.ini``,
    ``objectconfig.ini``, ``secrets.ini``, ``es_rules.json``), the ``install.sh`` script will automatically
    migrate them to YAML. See :doc:`breaking` for details on the migration.

Secrets
--------

Both ``zmeventnotification.yml`` and ``objectconfig.yml`` support a shared secrets mechanism that keeps
passwords and tokens out of your main config files. This lets you share config files safely without
exposing credentials.

Add a ``secrets`` key in the ``general`` section of either (or both) config files, pointing to a
secrets file. Then reference any secret by prefixing its name with ``!``.

For example, in ``/etc/zm/objectconfig.yml`` (or ``/etc/zm/zmeventnotification.yml``):

::

  general:
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

Any value starting with ``!`` is treated as a secret token and replaced with the
corresponding value from the secrets file.

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

.. note::

   Because ``!`` triggers secret lookup, you cannot use a password beginning with ``!``
   directly in the config. Instead, create a token in your secrets file and reference it.

Event Server Configuration
----------------------------

The Event Server is configured via ``/etc/zm/zmeventnotification.yml``.

Key Sections
~~~~~~~~~~~~~~

The file is organized into these sections:

- ``general`` — secrets file path, base data path, ES control interface settings, ``skip_monitors``
- ``network`` — WebSocket port and bind address
- ``auth`` — ZoneMinder user/password authentication and timeout
- ``fcm`` — Firebase Cloud Messaging for push notifications. Supports proxied delivery
  (default via ``fcm_v1_url``) or direct delivery using a Google Service Account
  (``fcm_service_account_file``). Also controls ``replace_push_messages``,
  ``fcm_android_priority``, ``fcm_android_ttl``, ``include_profile_in_push``, and token storage
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

.. _es_config_reference:

Complete Reference
~~~~~~~~~~~~~~~~~~~~

Every key accepted by ``zmeventnotification.yml``, grouped by YAML section.

``general`` — app-level settings
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. list-table::
   :header-rows: 1
   :widths: 30 18 52

   * - Key
     - Default
     - Description
   * - ``secrets``
     - *none*
     - Path to secrets YAML file for ``!TOKEN`` substitution
   * - ``base_data_path``
     - ``/var/lib/zmeventnotification``
     - Base path for data directories and scripts
   * - ``use_escontrol_interface``
     - ``no``
     - Enable ES control interface for dynamic behaviour overrides
   * - ``escontrol_interface_file``
     - ``${base_data_path}/misc/escontrol_interface.dat``
     - File to persist ES control admin overrides
   * - ``escontrol_interface_password``
     - *none*
     - Password for accepting control interface connections
   * - ``restart_interval``
     - ``7200``
     - Auto-restart ES after this many seconds (``0`` = disable)
   * - ``skip_monitors``
     - *none*
     - Comma-separated monitor IDs to completely skip ES processing

``network`` — WebSocket server
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. list-table::
   :header-rows: 1
   :widths: 30 18 52

   * - Key
     - Default
     - Description
   * - ``port``
     - ``9000``
     - WebSocket listening port
   * - ``address``
     - ``[::]``
     - Bind address (use ``0.0.0.0`` for all IPv4 interfaces)

``auth`` — authentication
^^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. list-table::
   :header-rows: 1
   :widths: 30 18 52

   * - Key
     - Default
     - Description
   * - ``enable``
     - ``yes``
     - Check username/password against ZoneMinder database
   * - ``timeout``
     - ``20``
     - Authentication timeout in seconds

``fcm`` — Firebase Cloud Messaging
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. list-table::
   :header-rows: 1
   :widths: 30 18 52

   * - Key
     - Default
     - Description
   * - ``enable``
     - ``yes``
     - Enable FCM push notifications
   * - ``use_fcmv1``
     - ``yes``
     - Use FCM V1 protocol (recommended)
   * - ``replace_push_messages``
     - ``no``
     - Replace previous push for same monitor (collapses notifications)
   * - ``token_file``
     - ``${base_data_path}/push/tokens.txt``
     - File to persist registered FCM tokens
   * - ``date_format``
     - ``%I:%M %p, %d-%b``
     - strftime format for notification timestamps
   * - ``fcm_android_priority``
     - ``high``
     - Android push priority (``high`` or ``normal``)
   * - ``fcm_android_ttl``
     - *none*
     - Android message TTL in seconds (omit for FCM default)
   * - ``fcm_log_raw_message``
     - ``no``
     - Log full push message on the cloud function (debugging only)
   * - ``fcm_log_message_id``
     - ``NONE``
     - Unique ID to identify your messages in cloud function logs
   * - ``fcm_v1_key``
     - *(managed zmNinjaNG key)*
     - Authorization key for the FCM cloud function proxy
   * - ``fcm_v1_url``
     - *(managed zmNinjaNG URL)*
     - URL of the FCM cloud function proxy
   * - ``include_profile_in_push``
     - ``no``
     - Include profile name in push display (iOS subtitle, Android body append)
   * - ``fcm_service_account_file``
     - *none*
     - Path to Google service account JSON for direct FCM (bypasses proxy)

``mqtt`` — MQTT messaging
^^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. list-table::
   :header-rows: 1
   :widths: 30 18 52

   * - Key
     - Default
     - Description
   * - ``enable``
     - ``no``
     - Enable MQTT notifications
   * - ``server``
     - ``127.0.0.1``
     - MQTT broker hostname or IP
   * - ``topic``
     - ``zoneminder``
     - MQTT topic name
   * - ``username``
     - *none*
     - MQTT broker username
   * - ``password``
     - *none*
     - MQTT broker password
   * - ``retain``
     - ``no``
     - Set retain flag on MQTT messages
   * - ``tick_interval``
     - ``15``
     - MQTT keep-alive interval in seconds
   * - ``tls_ca``
     - *none*
     - Path to CA certificate (enables MQTT over TLS)
   * - ``tls_cert``
     - *none*
     - Path to client certificate (for mutual TLS)
   * - ``tls_key``
     - *none*
     - Path to client private key (for mutual TLS)
   * - ``tls_insecure``
     - ``no``
     - Disable TLS peer verification

``ssl`` — WebSocket SSL
^^^^^^^^^^^^^^^^^^^^^^^^^^

.. list-table::
   :header-rows: 1
   :widths: 30 18 52

   * - Key
     - Default
     - Description
   * - ``enable``
     - ``yes``
     - Enable SSL for the WebSocket server
   * - ``cert``
     - *none*
     - Path to SSL certificate file
   * - ``key``
     - *none*
     - Path to SSL private key file

``push`` — third-party push API
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. list-table::
   :header-rows: 1
   :widths: 30 18 52

   * - Key
     - Default
     - Description
   * - ``use_api_push``
     - ``no``
     - Enable third-party push notifications (e.g. Pushover)
   * - ``api_push_script``
     - *none*
     - Script to invoke for push (receives event ID, monitor ID, name, cause, type, image path)

``customize`` — notification and display
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. list-table::
   :header-rows: 1
   :widths: 30 18 52

   * - Key
     - Default
     - Description
   * - ``es_rules``
     - *none*
     - Path to ES rules YAML file for custom notification routing
   * - ``console_logs``
     - ``no``
     - Display log messages to console
   * - ``es_debug_level``
     - ``5``
     - Debug verbosity level for ES messages
   * - ``event_check_interval``
     - ``5``
     - Seconds between event polling checks
   * - ``monitor_reload_interval``
     - ``300``
     - Seconds between monitor list reloads
   * - ``read_alarm_cause``
     - ``no``
     - Read alarm cause from ZM (requires ZM >= 1.31.2)
   * - ``tag_alarm_event_id``
     - ``no``
     - Append event ID to alarm notification title
   * - ``use_custom_notification_sound``
     - ``no``
     - Use custom notification sound
   * - ``include_picture``
     - ``no``
     - Include picture URL in push notifications
   * - ``picture_url``
     - *none*
     - URL template for event images (use ``EVENTID`` as placeholder)
   * - ``picture_portal_username``
     - *none*
     - Username for picture URL authentication
   * - ``picture_portal_password``
     - *none*
     - Password for picture URL authentication
   * - ``send_event_start_notification``
     - ``yes``
     - Send notifications when events start
   * - ``send_event_end_notification``
     - ``no``
     - Send notifications when events end
   * - ``use_hooks``
     - ``no``
     - Master on/off switch for ML hooks

``hook`` — ML hook configuration
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. list-table::
   :header-rows: 1
   :widths: 30 18 52

   * - Key
     - Default
     - Description
   * - ``max_parallel_hooks``
     - ``0``
     - Maximum concurrent hook processes (``0`` = unlimited)
   * - ``event_start_hook``
     - *none*
     - Script to run when an event starts
   * - ``event_end_hook``
     - *none*
     - Script to run when an event ends
   * - ``event_start_hook_notify_userscript``
     - *none*
     - User script to run after event start hook completes
   * - ``event_end_hook_notify_userscript``
     - *none*
     - User script to run after event end hook completes
   * - ``event_start_notify_on_hook_success``
     - ``none``
     - Notification channels when start hook returns 0 (``web``, ``fcm``, ``mqtt``, ``api``, ``all``, ``none``)
   * - ``event_start_notify_on_hook_fail``
     - ``none``
     - Notification channels when start hook returns 1
   * - ``event_end_notify_on_hook_success``
     - ``none``
     - Notification channels when end hook returns 0
   * - ``event_end_notify_on_hook_fail``
     - ``none``
     - Notification channels when end hook returns 1
   * - ``event_end_notify_if_start_success``
     - ``yes``
     - Only send end notification if start notification was sent
   * - ``use_hook_description``
     - ``no``
     - Use hook script output as notification text
   * - ``hook_skip_monitors``
     - *none*
     - Comma-separated monitor IDs to skip hooks for
   * - ``hook_pass_image_path``
     - *none*
     - Pass image storage path to hook script (requires ZM >= 1.33)
   * - ``tag_detected_objects``
     - ``no``
     - Write detected labels as ZM Tags (requires ZM >= 1.37.44)

Detection Hook Configuration
-------------------------------

The detection hooks are configured via ``/etc/zm/objectconfig.yml``.

Key Sections
~~~~~~~~~~~~~~

The file is organized into these sections:

- ``general`` — ZM portal/API credentials, data paths, debug images,
  ``import_zm_zones``, ``tag_detected_objects``, ``show_models``
- ``push`` — direct FCM push notifications from ``zm_detect`` (Path 1 only, ZM 1.39.2+).
  See :ref:`push_config` below for setup details.
- ``remote`` — remote ML server (``pyzm.serve``) gateway URL, mode, credentials, fallback
- ``ml`` — the detection pipeline:

  - ``ml.stream_sequence`` — frame selection: ``frame_set``, ``resize``, retry settings
  - ``ml.ml_sequence.general`` — pipeline-wide settings: ``model_sequence``, ``frame_strategy``,
    ``disable_locks``, ``match_past_detections``, ``max_detection_size``, ``aliases``
  - ``ml.ml_sequence.<type>`` — per-type ``general`` + ``sequence`` lists for object, face, alpr, audio
    (see :doc:`hooks` for full details)

- ``monitors`` — per-monitor overrides for ``wait``, ``ml_sequence``,
  ``stream_sequence``, and ``zones`` (with ``detection_pattern`` and ``ignore_pattern``)

.. _push_config:

**Direct Push Notifications (push section)**

The ``push`` section configures direct FCM push notifications
from ``zm_detect`` — **Path 1 only**, requires ZM 1.39.2+. ``zm_detect`` reads registered
tokens from ZM's ``Notifications`` table via pyzm and sends push notifications through an
FCM cloud function proxy after detection.

Setup steps:

1. Ensure ZoneMinder is 1.39.2+ (adds the Notifications REST API).
2. Set ``push.enabled`` to ``yes`` in ``objectconfig.yml``.
   The cloud function URL and key are pre-configured with the managed zmNinjaNG
   defaults (same as the ES) — no additional configuration needed.
3. Register device tokens: client apps (e.g. zmNinjaNG) register FCM tokens via
   the ZM ``/api/notifications.json`` REST endpoint. Tokens are stored in ZM's
   ``Notifications`` database table.

If you run your own FCM cloud function proxy, replace ``fcm_v1_url`` and
``fcm_v1_key`` with your own values.

``zm_detect`` respects per-token monitor filtering, throttle intervals,
and push state. Invalid tokens are automatically cleaned up.

By default, push notifications are only sent when detection finds a match.
If you use external sensor triggers and want a push even when ML detects
nothing, set ``push.send_push_on_no_match`` to ``yes``. The event
cause/reason (e.g. "External Motion") is used as the notification text.

.. _hook_config_reference:

Complete Reference
~~~~~~~~~~~~~~~~~~~~

Every key accepted by ``objectconfig.yml``, grouped by YAML section.
Keys not listed here will be logged as unrecognized and ignored.

.. note::

   Several keys have been moved or removed in 7.x. See :doc:`breaking` for details
   on what changed and migration steps.

``general`` — app-level settings
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Consumed by ``zm_detect.py`` / ``utils.py``:

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
   * - ``show_frame_match_type``
     - ``yes``
     - Show frame match prefix in detection output: ``[a]`` (alarm), ``[s]`` (snapshot), ``[x]`` (other)
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

.. _hook_push_reference:

``push`` — direct FCM push notifications
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Direct push from ``zm_detect`` (Path 1 only, requires ZM 1.39.2+).
See :ref:`push_config` above for setup steps.

.. list-table::
   :header-rows: 1
   :widths: 28 15 57

   * - Key
     - Default
     - Description
   * - ``enabled``
     - ``no``
     - Enable direct FCM push notifications from ``zm_detect``
   * - ``fcm_v1_url``
     - *(managed zmNinjaNG URL)*
     - URL of the FCM cloud function proxy. Replace only if you run your own.
   * - ``fcm_v1_key``
     - *(managed zmNinjaNG key)*
     - Authorization key for the cloud function proxy. Replace only if you run your own.
   * - ``replace_push_messages``
     - ``yes``
     - Collapse notifications per monitor (replaces previous push)
   * - ``include_picture``
     - ``yes``
     - Include event image URL in the notification
   * - ``picture_url``
     - *none*
     - Picture URL template (use ``EVENTID`` as placeholder for event ID)
   * - ``picture_portal_username``
     - *none*
     - Username for picture URL authentication
   * - ``picture_portal_password``
     - *none*
     - Password for picture URL authentication
   * - ``include_profile_in_push``
     - ``no``
     - Include profile name in push display (iOS subtitle, Android body append)
   * - ``send_push_on_no_match``
     - ``no``
     - Send push notification even when detection finds no matches. Useful for
       external sensor triggers where you want a notification regardless of ML
       results. The event cause/reason is used as the notification text.
   * - ``android_priority``
     - ``high``
     - FCM priority for Android (``high`` or ``normal``)
   * - ``android_ttl``
     - *none*
     - Android message TTL in seconds (omit for FCM default)

``remote`` — remote ML gateway settings
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Forwarded to pyzm ``Detector``:

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

``ml.stream_sequence`` — frame extraction
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Read by pyzm ``StreamConfig``:

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

``ml.ml_sequence.general`` — detection pipeline
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Read by pyzm ``DetectorConfig``:

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
     - ---
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

``ml.ml_sequence.<type>`` — per-type model settings
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Each type (``object``, ``face``, ``alpr``, ``audio``) has a ``general`` section for
overrides and a ``sequence`` list of model configurations. See :doc:`hooks` for details
on model-specific keys (``object_weights``, ``face_detection_framework``,
``alpr_service``, etc.).

``monitors`` — per-monitor overrides
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Any key from the sections above can be overridden per monitor. Dict values
(``ml_sequence``, ``stream_sequence``) are deep-merged; scalar values are replaced.
See :doc:`hooks` for zone configuration (``detection_pattern``, ``ignore_pattern``).

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
