Breaking Changes
----------------

pyzm v2 and pyzm.serve (ES 7.x)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

pyzm has been rewritten as v2. This is the ML detection library used by ``zm_detect.py``.
The key changes that affect ES users:

**What changed:**

- **``mlapi`` is replaced by ``pyzm.serve``** — the remote ML detection server is now built
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

   - On the GPU box: ``pip install pyzm[serve]`` then ``python -m pyzm.serve --models yolov4 --port 5000``
   - In ``objectconfig.yml``: use the ``remote:`` section with ``ml_gateway`` (see below)
   - Delete ``mlapiconfig.ini`` — it is no longer used

3. **New: URL-mode remote detection**: If your GPU box can reach ZoneMinder directly,
   set ``ml_gateway_mode: "url"`` in the ``remote:`` section. The server will fetch frames
   directly from ZM instead of having them uploaded by the ZM box. This is more efficient.

4. **No changes to objectconfig.yml format** — the ``ml_sequence`` and ``stream_sequence``
   YAML structures are fully backward compatible. ``Detector.from_dict()`` reads them
   identically.

**Remote ML config — before (mlapi) vs. after (pyzm.serve):**

Before (``objectconfig.yml`` with mlapi)::

   remote:
     ml_gateway: "http://gpu-box:5000"
     # Also needed: mlapiconfig.ini on the GPU box

After (``objectconfig.yml`` with pyzm.serve)::

   remote:
     ml_gateway: "http://gpu-box:5000"
     ml_gateway_mode: "url"          # NEW — "image" (default) or "url"
     ml_fallback_local: "yes"
     ml_user: "!ML_USER"
     ml_password: "!ML_PASSWORD"
     ml_timeout: 60

On the GPU box, start with::

   pip install pyzm[serve]
   python -m pyzm.serve --models yolov4 --port 5000 --auth --auth-user admin --auth-password secret


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

- **YAML format**: All config files now use YAML syntax instead of INI sections/key-value pairs.
  For example, ``[general]`` sections become ``general:`` with indented keys beneath them.
- **Secrets file**: Now ``/etc/zm/secrets.yml``. The ``!TOKEN_NAME`` syntax for referencing secrets
  remains the same. The secrets file itself uses a top-level ``secrets:`` key with tokens underneath.
- **``{{}}`` templating removed**: ``objectconfig.yml`` no longer supports ``{{variable}}`` template
  substitution. All values in ``ml_sequence`` and ``stream_sequence`` are specified directly/inline.
  The ``use_sequence`` flag no longer exists — sequences are always used.
- **``common_params.py`` removed**: The entire parameter substitution engine has been removed.
  ``${base_data_path}`` is the only substitution still supported (for path expansion).
- **Default model changed to YOLOv26 ONNX**: YOLOv3 defaults are now disabled. The default enabled
  model is ``YOLOv26n`` using ONNX format via OpenCV DNN. This requires **OpenCV 4.10+**.
  Direct Ultralytics/PyTorch support has been removed in favor of ONNX via OpenCV DNN.
- **``Config::IniFiles`` Perl module no longer needed**: The ES now uses ``YAML::XS`` (via the
  ``libyaml-libyaml-perl`` package on Debian/Ubuntu) instead of ``Config::IniFiles``.
- **``es_rules`` is now YAML**: The rules file previously used JSON format. It is now YAML.
  The ``install.sh`` script will auto-convert ``es_rules.json`` to ``es_rules.yml``.
- **New migration tools**: ``tools/config_upgrade.py`` has been replaced by:

  - ``tools/config_upgrade_yaml.py`` — upgrades an existing YAML config with new keys from the example
  - ``tools/es_config_migrate_yaml.py`` — migrates ES INI config and secrets to YAML
  - ``tools/config_migrate_yaml.py`` — migrates ``objectconfig.ini`` to YAML

- **New feature: ``tag_detected_objects``**: When set to ``yes`` in the ``hook`` section of
  ``zmeventnotification.yml``, detected object labels (e.g. person, cat) will be written as Tags
  into ZoneMinder's database. Requires ZM >= 1.37.44.

- **``INSTALL_YOLOV26`` install flag**: ``install.sh`` now defaults to downloading YOLOv26 ONNX models
  (``INSTALL_YOLOV26=yes``). YOLOv3 defaults are now ``no``. Use ``INSTALL_YOLOV26=no`` to skip.

**Upgrading:**

1. Run ``sudo ./install.sh`` — it will auto-detect old INI/JSON files and migrate them to YAML
2. Review the generated ``.yml`` files and verify the migration looks correct
3. Old files are renamed to ``*.migrated`` and originals are in the ``legacy/`` directory for reference
4. If you had custom ``{{}}`` templates in ``objectconfig.ini``, you will need to manually inline
   those values in ``objectconfig.yml`` as templating is no longer supported


.. note::

   The sections below are historical breaking change notes from older releases. They reference
   the old INI/JSON config file names (``objectconfig.ini``, ``zmeventnotification.ini``, etc.)
   that were in use at the time. All config files are now YAML — see the "YAML Migration" section above.

Version 6.1.19 onwards
~~~~~~~~~~~~~~~~~~~~~~~~~
- ``match_past_detections``, ``past_det_max_diff_area`` and ``max_detection_size`` (and associated label prefixes) 
  need to be in the ``general`` section of ``ml_sequence``. In the previous release they were stuffed inside each 
  model sequence which lead to problems (imagine an event where snapshot and alarm had different objects and you
  were checking both. In pass 1, snapshot would match but alarm would not, so you'd see objects in alarm. In pass 2,
  alarm would match, but not snapshot and it would keep going on like this, effectively making match_past_detections 
  useless. To avoid this, I am checking for match_past_detections *after* all matching is done)
- You can now choose to ignore certain labels when you match past detections using `ignore_past_detection_labels` 

- ``stream_sequence`` now has a few new fields fields: 

  - ``delay_between_frames``. If specified, will wait for those many seconds before processing each frame. 
  - ``delay_between_snapshots``. If specified, will wait for those many seconds when processing snapshot frames.
    This allows you to do something like this: ``frame_set: snapshot,snapshot,snapshot,alarm`` with a 
    ``delay_between_snapshots:2``, which means it will keep analyzing snapshot 3 times, but with 2 seconds in between, which 
    lets you grab multiple snapshot frames as it changes during an event. This is really only useful for this specific case.


Version 6.1.18 onwards 
~~~~~~~~~~~~~~~~~~~~~~~
- I now support face detection using TPU (NOT recognition). See objectconfig.ini for an example
- You can now add descriptive names for each model sequence to better differentiate in logs 
- Each model sequence now has an ``enabled`` flag (default is ``yes``). If ``no`` that means the model won't be loaded. This is a good way 
  to temporarily remove models while keeping config files intact 
- We now also have a ``same_model_strategy`` value of ``union`` - when set to ``union`` it will combine detection from all models for that type 

Version 6.1.17 onwards
~~~~~~~~~~~~~~~~~~~~~~~
- You can now localize ``past_det_max_diff_area``, ``max_detection_size`` to specific objects
  by prefixing the object name. Example ``car_max_detection_size`` if present will override 
  values for ``max_detection_size`` for objects that are cars. Same holds true for ``car_past_det_max_diff_area`` if 
  ``match_past_detections=yes``
- ``mlapiconfig.ini`` also supports the above values - you no longer have to keep putting these to 
  ``objectconfig.ini``

Version 6.1.12 onwards 
~~~~~~~~~~~~~~~~~~~~~~~~
- A lot of config changes, if you are using mlapi. Basically, I'm no longer fully supporting settings in objectconfig.ini
  transferring to mlapi. See :ref:`mlapi_overrides`

Version 6.1.0 onwards 
~~~~~~~~~~~~~~~~~~~~~~
- You can now string together multiple models in arbitrary fashion to suit your needs. 
  There is a new entry in ``objectconfig.ini`` called ``ml_sequence`` that you can use to 
  create your own sequence. Note that if ``ml_sequence`` is present, it will override any/all
  parameters in the ``[object]``, ``[face]`` and ``[alpr]`` sections. Please read `this section <https://zmeventnotification.readthedocs.io/en/latest/guides/hooks.html#understanding-detection-configuration>`__
  to understand how this works.

- The ``hog`` model has been removed. Note this refers to the ``hog`` person detection
  model, not the hog detection of a face. That still exists. With Yolo, TinyYolo, coral
  there was no need to support this very low performance model anymore.

- You can now also specify arbitrary frames for analysis. See See `here <https://pyzm.readthedocs.io/en/latest/source/pyzm.html#pyzm.ml.detect_sequence.DetectSequence.detect_stream>`__ for details (look at options attribute).

- To enable the new ``*_sequence`` attributes mentioned above, make ``use_sequence=yes`` in ``objectconfig.ini``

- A new attribute, ``disable_locks``. When set to ``yes``, it will result in locks not being grabbed
  before inferencing. The entire idea of grabbing locks is so that you have control on how many
  simultaneous processes use your CPU/GPU/TPU resources, so I'd recommend you don't enable it. 
  Set it to ``yes`` only if you are facing lock issues (such as timeouts)


Version 6.0.5 onwards
~~~~~~~~~~~~~~~~~~~~~~
- You can now specify object detection patterns on a per polygon/zone basis. The format is ``<polygonname>_zone_detection_pattern``
  This works for imported ZM zones too. Please read the comments in ``objectconfig.ini``. Note that this attribute will not be automatically
  added to a migrated ``objectconfig.ini`` file as the actual attribute name will change depending on your zone name
- ``zmeventnotification.ini`` has a new attribute called ``replace_push_messages`` in the ``[fcm]`` section. When enabled (default is ``no``),
  push messages will replace each other in the notification bar. This was the old Android behaviour prior to FCMv1. You can go back to this mode of
  operation for both iOS and Android if you enable this.

Version 6.0.1 onwards
~~~~~~~~~~~~~~~~~~~~~~~~
- ``zmeventnotification.ini`` new attribute in ``[fcm]`` called ``use_fcmv1`` with a default of ``yes```.
  It is recommended you keep this on as this switches from the `legacy <https://firebase.google.com/docs/cloud-messaging/http-server-ref>`__ 
  FCM protocol to the FCM v1 which allows for better features (which I will add over time).

- ``objectconfig.ini`` has a new attribute ``fast_gif`` in ``[animation]``. If you are creating animations for push 
  and generating GIFs, this creates a 2x speed GIF.

Version 6.0.0 onwards
~~~~~~~~~~~~~~~~~~~~~~~~~
- The ES has a new attribute in ``[customize]`` called ``es_rules``. A sample file
  gets automatically installed when you run the install script in ``/var/lib/zmeventnotification``
- Its use is optional. It is a JSON file with various rules for the ES that are not
  configuration related. Over the next few releases, this fill will replace the cryptic context of ``tokens.txt``
  As of now, it can be used to specify custom times for notification. This list will grow
  over time.
- A new perl dependency (optional) has been added to :doc:`install` if you need flexible datetime
  parsing for ES rules.
  

  **On the Object Detection part:**

- This is going to be a big bad breaking change release, but continues the path
  to unification between various components I've developed.
- To help with this 'big bad breaking change', I've provided an upgrade script.
  When you run ``./install.sh`` it will automatically run it at the end and put a
  ``migrated-objectconfig.ini`` in your current directory (from where you ran ``./install.sh``)
  You can also run it manually by invoking ``tools/config_upgrade.py -c /etc/zm/objectconfig.ini`` 
- All the ml code has now moved to pyzm and both local hook and mlapi use pyzm. This means
  when I update ml code, both systems get it right always
- This version also supports Google Coral Edge TPU
- Several ``objectconfig.ini`` attributes have been replaced and some removed towards
  this unification goal:

  - ``models`` is now ``detection_sequence``
  - ``yolo`` is no longer used. Instead ``object`` is used. ``object`` could be multiple
    object detection techniques, yolo or otherwise.
  - ``[ml]`` is now ``[remote]``
  - ``[object]`` is a new section, which contains two new attributes:

    - ``object_framework`` which can be ``opencv`` or   ``coral_edgetpu``
    - ``object_processor`` which can be ``cpu``, ``gpu`` or ``tpu``

  - ``yolo_min_confidence``  is now ``object_min_confidence``
  - ``config``, ``weights``, ``labels`` are now ``object_config``, ``object_weights`` and ``object_labels`` respectively.
  - None of the ``tiny_`` attributes exist anymore. Simply switch weights, labels and config files to switch between full and tiny
  - ``yolo_type`` doesn't exist anymore (as ``tiny_`` attributes are removed, so it doesn't make sense)
  - ``alpr_pattern`` is now ``alpr_detection_pattern``
  - ``detect_pattern`` no longer exists. You now have a per detection type pattern, which allows
    you to specify patterns based on the detection type:

    - ``object_detection_pattern`` - for all objects
    - ``alpr_detection_pattern`` - for for license plates
    - ``face_detection_pattern`` - for all faces detected
    - ``[general]`` has various new attributes that allow you to limit concurrent processing:

      - ``cpu_max_processes`` specific how many simultaneous instances of model execution will be allowed at one time.
        When more than this number is reached, processes will wait till in-flight processes complete. ``cpu_max_lock_wait`` 
        specifies how long each process will wait (default 2 mins) before throwing an error.
      - ``tpu_max_processes`` and ``tpu_max_lock_wait`` same as above but for TPU
      - ``gpu_max_processes`` and ``gpu_max_lock_wait`` same as above but for GPU

Version 5.15.7 onwards
~~~~~~~~~~~~~~~~~~~~~~~~~~~~
- The ``<>/models/tinyyolo`` directory is now ``<>/models/tinyyolov3``.
  ``install.sh`` will automatically move it, but remember to change your
  ``objectonfig.ini`` path if you are using tiny yolo.

- You now have an option to use the new Tiny Yolo V4 models which will be 
  automatically downloaded unless you disabled it (You'll need OpenCV master
  as of Jul 11, 2020 as support for it was only merged 6 days ago)

- A new attribute, ``ject_area`` has been introduced in ``objectconfig.ini``.
  This specifies the largest area a detected object should take inside the image. 
  You can keep it as a % or px value. Remember the image is resized to 416x416. better
  to keep in %

Version 5.15.6 onwards
~~~~~~~~~~~~~~~~~~~~~~~~~
- I got lazy with 5.15.5. There were some errors that I fixed post 5.15
  which I 'post-pushed' into 5.15.5. It is possible you installed 5.15.5 and
  don't have these fixes. In other words, if your 5.15.5 is broken, Please
  upgrade.

- In this release, I've also taken a necessary step towards model naming 
  normalization. Basically, ``Yolo`` models are now ``YoloV3`` and ``CSPN`` 
  is now ``Yolov4``. This is because this is the terminology `Alexey <https://github.com/AlexeyAB/darknet>`__ has started
  using in his repo. This means you will have to change your ``objectconfig.ini`` and align it with
  the same ``objectconfig.ini`` provided in this repo. I've also normalized the names
  of the config, weights and name files for each model. The short of all of this is, look under
  the ``[yolo]`` section of the sample config and replace your current yolo paths.
  Note that I assume you use ``install.sh`` to install. If not, you'll have to manually
  rename the old model names to the new ones. (Note that YoloV4 requires OpenCV 4.4 or above)


Version 5.15.5 onwards
~~~~~~~~~~~~~~~~~~~~~~~~
- ``zmeventnotification.ini`` has a new attribute, ``topic`` under ``[mqtt]``
  which lets you set the topic name for the messages

- ``objectconfig.ini`` has a new attribute, ``only_triggered_zm_zones``. When set to yes,
  this will remove objects that don't fall into zones that ZM detects motion in.
  Make sure you read the comments in ``objectconfig.ini`` above the attribute
  to understand its limitations


Version 5.14.4 onwards
~~~~~~~~~~~~~~~~~~~~~~~
- Added ability for users to PR contrib modules
  See :doc:`contrib_guidelines`
- ``zmeventnotification.ini`` adds two new attributes that makes it simpler for users
  to keep object detection plugin hooks intact *and also* trigger their own scripts 
  for housekeeping. See the ini script for documentation on ``event_start_hook_notify_userscript``
  and ``event_end_hook_notify_userscript``


Version 5.13.3 onwards
~~~~~~~~~~~~~~~~~~~~~~~~~~
- New attribute ``es_debug_level`` in ``zmeventnotification.ini`` that controls debug level verbosity. Default is ``2``
- New CSPNet support with ResNeXt (requires OpenCV 4.3 or above)
  - Note that this requires a **manual model download** as the model is in a google drive link and all automated download scripts are hacks that stop working after a while.
- You can now choose which models to download as part of ``./install.sh``. See :ref:`install-specific-models`


Version  5.11 onwards
~~~~~~~~~~~~~~~~~~~~~~

- If you are using platerecognition.com local SDK for ALPR, their SDK and cloud versions have slightly different API formats. There is a new attribute called ``alpr_api_type`` in ``objectconfig.ini`` that should be set to ``local`` to handle this. 
- ``skip_monitors`` in ``zmeventnotification.ini`` is now called ``hook_skip_monitors`` to correctly reflect this only means hooks will be skipped for these monitors. A new attribute ``skip_monitors`` has been added that controls which monitors the ES will skip completely (That is, no analysis/notifications at all for these monitors)
- Added support for live animations as part of push messages. This requires an upgraded zmNinja app (``1.3.0.91`` or above) as well as ZoneMinder master (1.35) as of Mar 17 2020. Without these two updates, live notifications will not work. Specifically:
  - This introduces a new section in ``objectconfig.ini`` called ``[animation]``. Please read the config for more details.
  - You are also going to have to re-run ``install.sh`` to install new dependencies

Version 5.9.9 onwards
~~~~~~~~~~~~~~~~~~~~~~~~~
- You can now hyper charge your push notifications, including getting desktop notifications. See below
- I now support 3rd party push notification systems. A popular one is `pushover <http://pushover.net>`__ that a lot of people seem to use for customizing the quality of push notifications, including critical notifications, quiet time et. al. This adds the following parameters:
  - A new section called ``[push]`` in ``zmeventnotification.ini``  that adds two new attributes: ``use_api_push`` and ``api_push_script``
  - I've provided a sample push script that supports pushover. This gets automatically installed when you use ``install.sh`` into ``/var/lib/zmeventnotification/bin/pushapi_pushover.py``
  - This also adds a new channel type called ``api`` to the pre-existing ``fcm,web,mqtt`` set.
  - You are of course, encouraged to write your own 3rd party plugins for push and PR back to the project.
  - Read more in `this article <https://medium.com/zmninja/hypercharging-push-notifications-with-pushover-and-others-23ed9ab706>`__

Version 5.7.7 onwards
~~~~~~~~~~~~~~~~~~~~~~~
- For those who are happy to use the legacy openALPR self compiled version for license plate detection that does not use DNNs, I support that. This adds new parameters to `objectconfig.ini`. See objectconfig.ini for new parameters under the "If you are using OpenALPR command line" section.

Version 5.7.4 onwards
~~~~~~~~~~~~~~~~~~~~~~~
- I know support the new OpenCV 4.1.2 GPU backend support for CUDA. This will only work if you are on OpenCV 4.1.2 and have compiled it correctly to use CUDA and are using the right architecture. 
  - This adds a new attribute ``use_opencv_dnn_cuda`` in ``objectconfig.ini`` which by default is ``no``. Please read the comments in ``objectconfig.ini`` about how to use this.
- The ES supports a control channel using which you can control its behavior remotely
  - This adds new attributes ``use_escontrol_interface``, ``escontrol_interface_file`` and ``escontrol_interface_password`` to ``zmeventnotification.ini``. Read more about it :ref:`escontrol_interface`.
- If you are using face recognition, you now have the option of automatically saving unknown faces to a specific folders. That way it's easy for you to review them later and retrain your known faces.
  - This introduces the following new attributes to ``objectconfig.ini``: ``save_unknown_faces``, ``save_unknown_faces_leeway_pixels`` and ``unknown_images_path``. Their documentation is part of ``objectconfig.ini``
- The detection script(s) now attach a JSON payload of the detected objects along with the text, separated by ``--SPLIT--``. If you are hacking your own scripts, you need to handle this. The ES automatically handles it when sending notifications.

Version 5.2 onwards
~~~~~~~~~~~~~~~~~~~~
- `use_hooks` is a new attribute that controls whether hooks will be used or not
- `send_event_end_notification` is a new attribute that controls whether end notifications are sent 

Version 5.0 onwards
~~~~~~~~~~~~~~~~~~~~~

- ``install.sh`` no longer tries to install opencv on its own. You will have to install ``opencv`` and ``opencv-contrib`` on your own. See install instructions in :doc:`hooks`.

- The ``hook_script`` attribute is deprecated. You now have ``hook_on_event_start`` and ``hook_on_event_end`` which lets you invoke different scripts when an event starts or ends. You also have the concepts of channels, that allows you to decide whether to send a notification even if hooks don't return anything. Read up about ``notify_on_hook_success`` and ``notify_on_hook_fail`` in  ``zmeventnotification.ini`` 

- Now that we support pre/post event hooks, the script names have changed too (``zm_detect_wrapper.sh`` is ``zm_event_start.sh`` and we have a new script called ``zm_event_end.sh`` that is really just a dummy script. Change it to what you need to do at the end of an event, if you enable event end notifications)

- You can now offload the entire machine learning processes to a remote server. All you need to do is to use ``ml_gateway`` and related options in ``objectconfig.ini``. The "ML gateway" is `my mlapi project <https://github.com/pliablepixels/mlapi>`__

- The ES now supports a ``restart_interval`` config item in ``zmeventnotification.ini``. If not 0, this will restart the ES after those many seconds (example ``7200`` is 2 hours). This may be needed if you find the ES locking up after a few hours. I think 5.0 resolves this locking issue (see `this issue <https://github.com/pliablepixels/zmeventnotification/issues/175>`__) but if it doesn't use this, umm, hack for now.


Version 4.6 onwards
~~~~~~~~~~~~~~~~~~~~
- If you are using hooks, make sure you run ``sudo ./install.sh`` again - it will create additional files in ``/var/lib/zmeventnotification``
- The hook files ``detect.py`` and ``detect_wrapper.sh`` are now called ``zm_detect.py`` and ``zm_detect_wrapper.sh``.  Furthermore, these scripts no longer reside in ``/usr/bin``. They will now reside in ``/var/lib/zmeventnotification/bin``. I suppose I did not need to namespace and move, but I thought of the latter after I did the namespace changing.
- If you are using face recognition, 4.6.1 and above now allow multiple faces per person. Note that it is recommended you train them before you run detection. See the documentation for it in :doc:`hooks`.


Version 4.4 onwards
~~~~~~~~~~~~~~~~~~~~
- If you are using picture messaging, then the URL format has changed. Please REMOVE ``&username=<user>&password=<passwd>`` from the URL and put them into the ``picture_portal_username`` and ``picture_portal_password`` fields respectively


Version 4.1 onwards
~~~~~~~~~~~~~~~~~~~~
- Hook versions will now always be ``<ES version>.x``, so in this case ``4.1.x``
- Hooks have now migrated to using a `proper python ZM logger module <https://pypi.org/project/pyzmutils/>`__ so it better integrates with ZM logging 
- To view detection logs, you now need to follow the standard ZM logging process. See :ref:`es-hooks-logging` documentation for more details)
- You no longer have to manually install python requirements, the setup process should automatically install them
- If you are using MQTT and your  ``MQTT:Simple`` library was installed a while ago, you may need to update it. A new ``login`` method was added
  to that library on Dec 2018 which is required (`ref <https://github.com/Juerd/Net-MQTT-Simple/blob/cf01b43c27893a07185d4b58ff87db183d08b0e9/Changes#L21>`__)


Version 3.9 onwards
~~~~~~~~~~~~~~~~~~~~
- Hooks now add ALPR, so you need to run `sudo -H pip install -r requirements.txt` again
- See modified objectconfig.ini if you want to add ALPR. Currently works with platerecognizer.com, so you will need an API key. See hooks docs for more info

Version 3.7 onwards
~~~~~~~~~~~~~~~~~~~
- There were some significant changes to ZM (will be part of 1.34), which includes migration to Bcrypt for passwords. Changes were made to support Bcrypt, which means you will have to add additional libraries. See the installation guide.

version 3.3 onwards
~~~~~~~~~~~~~~~~~~~

- Please use ``yes`` or ``no`` instead of ``1`` and ``0`` in ``zmeventnotification.ini`` to maintain consistency with ``objectconfig.ini``
- In ``zmeventnotification.ini``, ``store_frame_in_zm`` is now ``hook_pass_image_path``

version 3.2 onwards
~~~~~~~~~~~~~~~~~~~

- Changes in paths for everything. - event server config file now defaults to ``/etc/zm`` 
- hook config now defaults to ``/etc/zm`` 
- Push token file now defaults to ``/var/lib/zmeventnotification/push`` 
- all object detection data files default to ``/var/lib/zmeventnotification``
- If you are migrating from a previous version: 
        - Make a copy of your ``/etc/zmeventnotification.ini`` and ``/var/detect/objectconfig.ini`` (if you are using hooks) 
        - Run ``sudo -H ./install.sh`` again inside the repo, let it set up all the files 
        - Compare your old config files to the news ones at ``/etc/zm`` and make necessary changes 
        - Make sure everything works well 
        - You can now delete the old ``/var/detect`` folder as well as ``/etc/zmeventnotification.ini`` 
        - Run zmNinja again to make sure its token is registered in the new tokens file (in ``/var/lib/zmeeventnotification/push/tokens.txt``)
