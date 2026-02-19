Configuration Guide
====================

All configuration files use **YAML format**. There are two parts to the configuration of this system:

* The Event Notification Server configuration - typically ``/etc/zm/zmeventnotification.yml``
* The Machine Learning Hooks configuration - typically ``/etc/zm/objectconfig.yml``

The ES comes with a `sample ES config file <https://github.com/pliablepixels/zmeventnotification/blob/master/zmeventnotification.example.yml>`__
which you should customize as fit. The sample config file is well annotated, so you really should read the comments to get an
understanding of what each parameter does. Similarly, the ES also comes with a `sample objectconfig.yml file <https://github.com/pliablepixels/zmeventnotification/blob/master/hook/objectconfig.yml>`__
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

- ``general`` — ZM portal/API credentials, data paths, process locking, debug images,
  ``import_zm_zones``, ``match_past_detections``, ``tag_detected_objects``
- ``animation`` — create GIF/MP4 animations from event frames around the detection.
  Key settings: ``create_animation`` (``yes``/``no``), ``animation_types`` (``mp4,gif``),
  ``animation_width``, ``animation_retry_sleep``, ``animation_max_tries``, ``fast_gif``
- ``remote`` — remote ML server (``pyzm.serve``) gateway URL, mode, credentials, fallback
- ``ml`` — the detection pipeline:

  - ``ml.stream_sequence`` — frame selection: ``frame_set``, ``frame_strategy``, retry settings, ``resize``
  - ``ml.ml_sequence`` — model pipeline: ``model_sequence`` ordering, per-type ``general`` + ``sequence`` lists
    (see :doc:`hooks` for full details)

- ``monitors`` — per-monitor overrides for ``wait``, ``resize``, ``ml_sequence``,
  ``stream_sequence``, and ``zones`` (with ``detection_pattern`` and ``ignore_pattern``)

Refer to the sample config files for the full list of options with inline comments.

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
