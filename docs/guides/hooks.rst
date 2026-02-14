Machine Learning Hooks
======================

.. note::

        This page covers the ML detection pipeline, which is required for **both**
        Path 1 (detection only) and Path 2 (full ES).
        For installation instructions, see :doc:`installation`.
        The hooks use `pyzm <https://pyzmv2.readthedocs.io/en/latest/>`__ v2
        for detection. Make sure you have ``pyzm`` installed before proceeding.

.. important::

        Please don't ask me basic questions like "pip3 command not found - what do I do?" or
        "cv2 not found, how can I install it?" Hooks require some terminal
        knowledge and familiarity with troubleshooting. I don't plan to
        provide support for these hooks. They are for reference only.


Key Features
~~~~~~~~~~~~~

- Detection: objects, faces
- Recognition: faces
- License plate recognition (ALPR) via cloud services
- Platforms:

   - CPU (object, face detection, face recognition),
   - GPU (object, face detection, face recognition),
   - EdgeTPU (object, face detection)

- Machine learning can run locally or remotely via ``pyzm.serve``

Requirements
~~~~~~~~~~~~

- Python 3.10+
- OpenCV 4.13+ (for the default YOLOv26 ONNX model)
- pyzm v2 (``pip install pyzm``)

How it works
~~~~~~~~~~~~

The main detection script is ``zm_detect.py``. It reads ``objectconfig.yml``,
connects to ZoneMinder, downloads event frames, runs the ML detection pipeline
(via pyzm's ``Detector`` API), and returns results.

.. _path1_setup:

Path 1: Detection only (no ES)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**Requires ZM 1.37+.** ZoneMinder can call ``zm_detect.py`` directly via its
Event Start Command feature — no Event Server needed.

Configure per monitor in ZM: go to the monitor's **Config -> Recording** tab and set:

- **Event Start Command**::

     /var/lib/zmeventnotification/bin/zm_detect.py -c /etc/zm/objectconfig.yml -e %EID% -m %MID% -r "%EC%" -n

ZM substitutes ``%EID%``, ``%MID%``, ``%EC%`` tokens at runtime when an event starts.

Detection results are:

- Written to the ZM event notes (``-n`` flag)
- Saved as ``objdetect.jpg`` and ``objects.json`` in the event folder
  (if ``write_image_to_zm: "yes"`` in ``objectconfig.yml``)
- Optionally tagged in ZM (if ``tag_detected_objects: "yes"``, requires ZM >= 1.37.44)

**What you get:** object/face/ALPR detection, annotated images, detection notes in ZM,
local or remote ML via ``pyzm.serve``.

**What you don't get:** push notifications (FCM), WebSocket notifications, MQTT,
notification rules/muting, zmNinja push, or the ES control interface.

To set up Path 1, you only need to:

1. Install pyzm and the hooks (see :doc:`install_path1`)
2. Edit ``/etc/zm/objectconfig.yml`` with your ZM portal credentials and desired models
3. Set the **Event Start Command** in the monitor's Config -> Recording tab as shown above
4. Optionally, set **Event End Command** (same tab) to a similar invocation if you want end-of-event processing

.. _path2_setup:

Path 2: Full Event Server
^^^^^^^^^^^^^^^^^^^^^^^^^^

The ES is a Perl daemon that monitors ZoneMinder's shared memory for new events,
invokes the ML hooks, and handles push notifications, WebSockets, MQTT, rules, and more.

When an event occurs, the ES invokes ``zm_event_start.sh``, which calls ``zm_detect.py``.
Based on the detection result and your notification settings, the ES sends alerts via
FCM (iOS/Android push), WebSockets, MQTT, and/or third-party push APIs.

**What you get (in addition to Path 1):** push notifications to zmNinja and other
FCM clients, WebSocket notifications, MQTT publishing, notification rules (time-based
muting, per-monitor controls), per-device monitor filtering via ``tokens.txt``, and the
ES control interface.

To set up Path 2:

1. Install the ES and its Perl dependencies (see :doc:`install_path2`)
2. Install pyzm and the hooks (see :doc:`install_path1`)
3. Edit ``/etc/zm/zmeventnotification.yml`` and ``/etc/zm/objectconfig.yml``
4. Enable ``OPT_USE_EVENTNOTIFICATION`` in ZM ``Options -> Systems``

See :doc:`principles` for a detailed walkthrough of how the ES processes events.

.. note::

   Do **not** configure both ``EventStartCommand`` (Path 1) and the ES hook (Path 2)
   for the same monitors — you would end up running detection twice on every event.

Manual testing
^^^^^^^^^^^^^^^

Regardless of which path you use, you can always test detection manually::

   # Test with a ZM event
   sudo -u www-data /var/lib/zmeventnotification/bin/zm_detect.py \
       --config /etc/zm/objectconfig.yml --eventid <eid> --monitorid <mid> --debug

   # Test with a local image file (no ZM event needed)
   sudo -u www-data /var/lib/zmeventnotification/bin/zm_detect.py \
       --config /etc/zm/objectconfig.yml --file /path/to/image.jpg --debug


Post install steps
~~~~~~~~~~~~~~~~~~

-  Make sure you edit your installed ``objectconfig.yml`` to the right
   settings. You MUST change the ``general`` section for your own
   portal.
-  Make sure the ``CONFIG_FILE`` variable in ``zm_event_start.sh`` is
   correct


Test operation
~~~~~~~~~~~~~~

You can test detection directly with ``zm_detect.py`` (no need to go through the shell wrapper):

::

    sudo -u www-data /var/lib/zmeventnotification/bin/zm_detect.py \
        --config /etc/zm/objectconfig.yml --eventid <eid> --monitorid <mid> --debug

Replace ``<eid>`` with an actual event ID from your ZM console. The ``<mid>`` is the monitor ID
(optional — if specified, monitor-specific settings from ``objectconfig.yml`` will be used).

You can also test with a local image file instead of a ZM event::

    sudo -u www-data /var/lib/zmeventnotification/bin/zm_detect.py \
        --config /etc/zm/objectconfig.yml --file /path/to/test.jpg --debug

If using the ES hook mode, you can also test the full shell wrapper::

    sudo -u www-data /var/lib/zmeventnotification/bin/zm_event_start.sh <eid> <mid>

If it doesn't work, go back and figure out where you have a problem


Upgrading
~~~~~~~~~
To upgrade at a later stage, see :ref:`upgrade_es_hooks`.

Sidebar: Local vs. Remote Machine Learning
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
You can run the machine learning code on a separate server using ``pyzm.serve``
(the built-in remote ML detection server that replaces the legacy ``mlapi``).
This frees up your ZM server resources and keeps models loaded in memory on the GPU box
so subsequent detections are fast. See :ref:`this FAQ entry <local_remote_ml>`.

To start the server on your GPU box::

   pip install pyzm[serve]
   python -m pyzm.serve --models yolov4 --port 5000

Then point ``ml_gateway`` in ``objectconfig.yml`` to that server::

   remote:
     ml_gateway: "http://gpu-box:5000"
     ml_gateway_mode: "url"          # let the server fetch images directly from ZM
     ml_fallback_local: "yes"

Use ``ml_gateway_mode: "url"`` if your GPU box can reach ZoneMinder directly (recommended
for best performance). Use ``"image"`` (default) if the GPU box is on a different network
and can't reach ZM. See :ref:`remote_ml_config` for full details.


.. _supported_models:

Which models should I use?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- **YOLOv26 ONNX (Recommended)**: The default and recommended model. Uses ONNX format via OpenCV's DNN
  module. Requires OpenCV 4.13+. Multiple sizes are available (``yolo26n``, ``yolo26s``, ``yolo26m``,
  ``yolo26l``, ``yolo26x``) — smaller models are faster, larger models are more accurate.
  The ``n`` (nano) variant is enabled by default and provides a good balance.

- **YOLOv4**: Still supported via Darknet weights. Requires OpenCV 4.4+.

- **Google Coral Edge TPU**: Supported for both object detection and face detection. See install instructions above.

- **YOLOv3 / Tiny YOLOv3 / Tiny YOLOv4**: Still available but no longer installed by default.
  Set the appropriate ``INSTALL_*`` flag to ``yes`` during install if you need them.

- For face recognition, use ``face_model: cnn`` for more accuracy and ``face_model: hog`` for better speed


.. _detection_sequence:

Understanding detection configuration
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

You can chain arbitrary detection types (object, face, alpr) and multiple models within
each type. The detection pipeline is configured through two key structures in ``objectconfig.yml``:

- ``ml_sequence`` — specifies the sequence of ML detection steps
- ``stream_sequence`` — specifies frame selection and retry preferences

.. note::

   All configuration is now in YAML format in ``objectconfig.yml``. The old ``{{variable}}``
   template substitution syntax is **no longer supported**. All values must be specified directly
   in the YAML file. The ``use_sequence`` flag no longer exists — the sequence structures are
   always used.

   The only substitution supported is ``${base_data_path}`` which is replaced with the value from
   ``general.base_data_path``.

Per-monitor overrides
^^^^^^^^^^^^^^^^^^^^^^
If you want to change ``ml_sequence`` or ``stream_sequence`` on a per monitor basis, you can do so
under the ``monitors`` section. You can override the entire structure or just parts of it:

::

   monitors:
     3:
       ml_sequence:
         general:
           model_sequence: "object,face"
         object:
           general:
             pattern: "(person|car)"
     7:
       ml_sequence:
         general:
           model_sequence: "object,alpr"



Understanding ml_sequence
^^^^^^^^^^^^^^^^^^^^^^^^^^
The ``ml_sequence`` structure lies in the ``ml`` section of ``objectconfig.yml``.
At a high level, this is how it is structured:

::

   ml:
     ml_sequence:
       general:
         model_sequence: "<comma separated detection types>"
       <detection_type>:
         general:
           pattern: "<pattern>"
           same_model_sequence_strategy: "<strategy>"
         sequence:
           - name: "Model name"
             enabled: "yes"
             # ... model-specific parameters ...
           - name: "Another model"
             enabled: "yes"
             # ... model-specific parameters ...

Here is a concrete example from the default ``objectconfig.yml``:

::

   ml:
     ml_sequence:
       general:
         model_sequence: "object,face,alpr"
       object:
         general:
           pattern: "(person|car|motorbike|bus|truck|boat)"
           same_model_sequence_strategy: first
         sequence:
           - name: YOLOv26n ONNX GPU/CPU
             enabled: "yes"
             object_weights: "${base_data_path}/models/ultralytics/yolo26n.onnx"
             object_min_confidence: 0.3
             object_framework: opencv
             object_processor: gpu
       face:
         general:
           pattern: ".*"
           same_model_sequence_strategy: union
         sequence:
           - name: DLIB face recognition
             enabled: "yes"
             face_detection_framework: dlib
             known_images_path: "${base_data_path}/known_faces"
             face_model: cnn

**Explanation:**

- The ``general`` section at the top level specifies characteristics that apply to all elements inside
  the structure.

   - ``model_sequence`` dictates the detection types (comma separated). Example ``object,face,alpr`` will
     first run object detection, then face, then alpr

- For each detection type in ``model_sequence``, you specify model configurations in the ``sequence`` list.
  Each entry in the sequence is a model configuration with a ``name`` and ``enabled`` flag.

  **Note**: When using ``pyzm.serve`` (remote ML), the ``ml_sequence`` and zone settings from
  ``objectconfig.yml`` are sent along with each detection request.

Leveraging same_model_sequence_strategy and frame_strategy effectively
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

When we allow model chaining, the question we need to answer is 'How deep do we want to go to get what we want?'
That is what these attributes offer. 

``same_model_sequence_strategy`` is part ``ml_sequence``  with the following possible values:

   - ``first`` - When detecting objects, if there are multiple fallbacks, break out the moment we get a match
      using any object detection library (Default)
   - ``most`` - run through all libraries, select one that has most object matches
   - ``most_unique`` - run through all libraries, select one that has most unique object matches

``frame_strategy`` is part of ``stream_sequence`` with the following possible values:

   - 'most_models': Match the frame that has matched most models (does not include same model alternatives) (Default)
   - 'first': Stop at first match 
   - 'most': Match the frame that has the highest number of detected objects
   - 'most_unique' Match the frame that has the highest number of unique detected objects
           

**A proper example:**

Take a look at `this article <https://medium.com/zmninja/multi-frame-and-multi-model-analysis-533fa1d2799a>`__ for a walkthrough.

**All options:**

``ml_sequence`` supports various other attributes. See the
`pyzm DetectorConfig documentation <https://pyzmv2.readthedocs.io/en/latest/source/pyzm.html>`__
for the full list of supported keys (``match_past_detections``, ``past_det_max_diff_area``,
``aliases``, ``max_detection_size``, etc.).

Understanding stream_sequence
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
The ``stream_sequence`` structure lies in the ``ml`` section of ``objectconfig.yml``.
At a high level, this is how it is structured:

::

   ml:
     stream_sequence:
       frame_set: "snapshot,alarm"
       frame_strategy: most_models
       contig_frames_before_error: 5
       max_attempts: 3
       sleep_between_attempts: 4
       resize: 800

**Explanation:**

- ``frame_set`` defines the set of frames it should use for analysis (comma separated)
- ``frame_strategy`` defines what it should do when a match has been found
- ``contig_frames_before_error``: How many contiguous errors should occur before giving up on the series of frames 
- ``max_attempts``: How many times to try each frame (before counting it as an error in the ``contig_frames_before_error`` count)
- ``sleep_between_attempts``: When an error is encountered, how many seconds to wait for retrying 
- ``resize``: what size to resize frames too (useful if you want to speed things up and/or are running out of memory)

**A proper example:**

Take a look at `this article <https://medium.com/zmninja/multi-frame-and-multi-model-analysis-533fa1d2799a>`__ for a walkthrough.

**All options:**

``stream_sequence`` supports various other attributes. See the
`pyzm StreamConfig documentation <https://pyzmv2.readthedocs.io/en/latest/source/pyzm.html>`__
for the full list (``max_frames``, ``start_frame``, ``frame_skip``, ``save_frames``, etc.).


How ml_sequence and stream_sequence work together
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Like this:

::

   for each frame in stream sequence:
      perform stream_sequence actions on each frame
      for each model_sequence in ml_options:
      if detected, use frame_strategy (in stream_sequence) to decide if we should try other model sequences
         perform general actions:
            for each model_configuration in ml_options.sequence:
               detect()
               if detected, use same_model_sequence_strategy to decide if we should try other model configurations
      

.. _remote_ml_config:

Using the remote ML detection server (pyzm.serve)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. note::

   ``pyzm.serve`` replaces the legacy ``mlapi`` server. It is built into pyzm itself,
   uses the same ``Detector`` API, and requires no separate configuration file. The old
   ``mlapiconfig.ini`` is no longer needed.

**Server setup** (GPU box)::

   pip install pyzm[serve]

   # Basic usage
   python -m pyzm.serve --models yolov4 --port 5000

   # With authentication
   python -m pyzm.serve --models yolov4 --port 5000 \
       --auth --auth-user admin --auth-password secret

   # Multiple models, GPU inference
   python -m pyzm.serve --models yolov4 yolo26s --port 5000 --processor gpu

**Client setup** (``objectconfig.yml`` on the ZM box)::

   remote:
     ml_gateway: "http://192.168.1.183:5000"
     ml_gateway_mode: "image"       # "image" (default) or "url"
     ml_fallback_local: "yes"
     ml_user: "!ML_USER"
     ml_password: "!ML_PASSWORD"
     ml_timeout: 60

When ``ml_gateway`` is set, ``zm_detect.py`` creates the ``Detector`` in remote mode.
The server keeps models loaded in memory so subsequent requests skip the expensive
model-load step.

If the remote server is unreachable and ``ml_fallback_local`` is ``yes``, detection
falls back to running locally on the ZM box.

All other settings (``ml_sequence``, ``stream_sequence``, monitor overrides, animation,
image writing, etc.) stay in ``objectconfig.yml`` — there is no second config file to manage.

**Two detection modes:**

Image mode (``ml_gateway_mode: "image"``, default)
   Frame extraction happens locally on the ZM box, then each frame is JPEG-encoded and
   uploaded to the server's ``/detect`` endpoint. This works universally but transfers
   every frame through the ZM box.

URL mode (``ml_gateway_mode: "url"``)
   The ZM box sends frame URLs (e.g. ``https://zm/index.php?view=image&eid=123&fid=snapshot``)
   and ZM auth credentials to the server's ``/detect_urls`` endpoint. The **server** fetches
   images directly from ZoneMinder and runs detection. This is more efficient when the GPU box
   has fast/direct network access to ZM, since frames don't have to pass through the ZM box
   as an intermediary.

   To use URL mode, the server must be able to reach your ZM web portal over HTTP/HTTPS.

**Server endpoints:**

- ``GET /health`` — returns ``{"status": "ok", "models_loaded": true}``
- ``POST /detect`` — (image mode) accepts multipart ``file`` (JPEG) + optional ``zones`` (JSON)
- ``POST /detect_urls`` — (URL mode) accepts JSON with frame URLs, auth token, and optional zones
- ``POST /login`` — (auth mode only) accepts ``{"username": ..., "password": ...}``, returns JWT token

Here is a part of my config, for example:

::

   general:
     import_zm_zones: "yes"

   monitors:
     3:
       # doorbell
       ml_sequence:
         general:
           model_sequence: "object,face"
         object:
           general:
             pattern: "(person|monitor_doorbell)"
     7:
       # Driveway
       ml_sequence:
         general:
           model_sequence: "object,alpr"
         object:
           general:
             pattern: "(person|car|motorbike|bus|truck|boat)"
     2:
       # Front lawn
       ml_sequence:
         general:
           model_sequence: "object"
         object:
           general:
             pattern: "(person)"
     4:
       # deck
       ml_sequence:
         object:
           general:
             pattern: "(person|monitor_deck)"
       stream_sequence:
         frame_strategy: most_models
         frame_set: "alarm"
         contig_frames_before_error: 5
         max_attempts: 3
         sleep_between_attempts: 4
         resize: 800

About specific detection types
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

License plate recognition
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Three ALPR options are provided: 

- `Plate Recognizer <https://platerecognizer.com>`__ . It uses a deep learning model that does a far better job than OpenALPR (based on my tests). The class is abstracted, obviously, so in future I may add local models. For now, you will have to get a license key from them (they have a `free tier <https://platerecognizer.com/pricing/>`__ that allows 2500 lookups per month)
- `OpenALPR <https://www.openalpr.com>`__ . While OpenALPR's detection is not as good as Plate Recognizer, when it does detect, it provides a lot more information (like car make/model/year etc.)
- `OpenALPR command line <http://doc.openalpr.com/compiling.html>`__. This is a basic version of OpenALPR that can be self compiled and executed locally. It is far inferior to the cloud services and does NOT use any form of deep learning. However, it is free, and if you have a camera that has a good view of plates, it will work.

``alpr_service`` defined the service to be used.

Face Dection & Recognition
^^^^^^^^^^^^^^^^^^^^^^^^^^^
When it comes to faces, there are two aspects (that many often confuse):

- Detecting a Face
- Recognizing a Face 

Face Detection 
'''''''''''''''
If you only want "face detection", you can use either dlib/face_recognition or Google's TPU. Both are supported.
Take a look at ``objectconfig.yml`` for how to set them up.

Face Detection + Face Recognition
'''''''''''''''''''''''''''''''''''

Face Recognition uses
`this <https://github.com/ageitgey/face_recognition>`__ library. Before
you try and use face recognition, please make sure you did a
``sudo -H pip3 install face_recognition`` The reason this is not
automatically done during setup is that it installs a lot of
dependencies that takes time (including dlib) and not everyone wants it.

.. sidebar:: Face recognition limitations

        Don't expect magic with overhead cameras. This library requires a
        reasonable face orientation (works for front facing, or somewhat side
        facing poses) and does not work for full profiles or completely overhead
        faces. Take a look at the `accuracy
        wiki <https://github.com/ageitgey/face_recognition/wiki/Face-Recognition-Accuracy-Problems>`__
        of this library to know more about its limitations. Also note that I found `cnn` mode is much more accurage than `hog` mode. However, `cnn` comes with a speed and memory tradeoff.

Using the right face recognition modes
'''''''''''''''''''''''''''''''''''''''

- Face recognition uses dlib. Note that in ``objectconfig.yml`` you have two options of face detection/recognition. Dlib has two modes of operation (controlled by ``face_model``). Face recognition works in two steps:
  - A: Detect a face
  - B: Recognize a face

``face_model`` affects step A. If you use ``cnn`` as a value, it will use a DNN to detect a face. If you use ``hog`` as a value, it will use a much faster method to detect a face. ``cnn`` is *much* more accurate in finding faces than ``hog`` but much slower. In my experience, ``hog`` works ok for front faces while ``cnn`` detects profiles/etc as well. 

Step B kicks in only after step A succeeds (i.e. a face has been detected). The algorithm used there is common irrespective of whether you found a face via ``hog`` or ``cnn``.

Configuring face recognition directories
''''''''''''''''''''''''''''''''''''''''''

-  Make sure you have images of people you want to recognize in
   ``/var/lib/zmeventnotification/known_faces``
- You can have multiple faces per person
- Typical configuration:

:: 

  known_faces/
    +----------bruce_lee/
                +------1.jpg
                +------2.jpg
    +----------david_gilmour/
            +------1.jpg
            +------img2.jpg
            +------3.jpg
    +----------ramanujan/
            +------face1.jpg
            +------face2.jpg


In this example, you have 3 names, each with different images.

- It is recommended that you now train the images by doing:

::

  sudo -u www-data /var/lib/zmeventnotification/bin/zm_train_faces.py


If you find yourself running out of memory while training, use the size argument like so:

::

     sudo -u www-data /var/lib/zmeventnotification/bin/zm_train_faces.py --size 800

   
   
- Note that you do not necessarily have to train it first but I highly recommend it. 
  When detection runs, it will look for the trained file and if missing, will auto-create it. 
  However, detection may also load yolo and if you have limited GPU resources, you may run out of memory when training. 

-  When face recognition is triggered, it will load each of these files
   and if there are faces in them, will load them and compare them to
   the alarmed image

known faces images
''''''''''''''''''
-  Make sure the face is recognizable
-  crop it to around 800 pixels width (doesn't seem to need bigger
   images, but experiment. Larger the image, the larger the memory
   requirements)
- crop around the face - not a tight crop, but no need to add a full body. A typical "passport" photo crop, maybe with a bit more of shoulder is ideal.


.. _hooks-troubleshooting:

Troubleshooting
~~~~~~~~~~~~~~~

See also :ref:`triage-no-detection` in the FAQ for a step-by-step guide on
translating ES log lines into manual ``zm_detect.py`` commands with debug flags.

-  In general, I expect you to debug properly. Please don't ask me basic
   questions without investigating logs yourself
-  Always run ``zm_event_start.sh`` or ``zm_detect.py`` in manual mode first to make sure it
   works
-  Make sure you've set up debug logging as described in :ref:`es-hooks-logging`
-  One of the big reasons why object detection fails is because the hook
   is not able to download the image to check. This may be because your
   ZM version is old or other errors. Some common issues:

   -  Make sure your ``objectconfig.yml`` ``general`` section settings are
      correct (portal, user,admin)
   -  For object detection to work, the hooks expect to download images
      of events using
      ``https://yourportal/zm/?view=image&eid=<eid>&fid=snapshot`` and
      possibly ``https://yourportal/zm/?view=image&eid=<eid>&fid=alarm``
   -  Open up a browser, log into ZM. Open a new tab and type in
      ``https://yourportal/zm/?view=image&eid=<eid>&fid=snapshot`` in
      your browser. Replace ``eid`` with an actual event id. Do you see
      an image? If not, you'll have to fix/update ZM. Please don't ask
      me how. Please post in the ZM forums
   -  Open up a browser, log into ZM. Open a new tab and type in
      ``https://yourportal/zm/?view=image&eid=<eid>&fid=alarm`` in your
      browser. Replace ``eid`` with an actual event id. Do you see an
      image? If not, you'll have to fix/update ZM. Please don't ask me
      how. Please post in the ZM forums

.. _debug_reporting_hooks:

Debugging and reporting problems
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Reporting Problems:

1. Make sure you have debug logging enabled as described in :ref:`es-hooks-logging`
2. Don't just post the final error message. Please post _full_ debug logs. 

If you have problems with hooks, there are two areas of failure:

- The ES is unable to unable to invoke hooks properly (missing files/etc)

   - This will be reported in ES logs. See :ref:`this section <debug_reporting_es>`

- Hooks don't work

   - This is covered in this section 

- The wrapper script (typically ``/var/lib/zmeventnotification/bin/zm_event_start.sh`` is not able to run ``zm_detect.py``)

   - This won't be covered in either logs (I need to add logging for this...)


To understand what is going wrong with hooks, I like to do things the following way:

- Stop the ES if it is running (``sudo zmdc.pl stop zmeventnotification.pl``) so that we don't mix up what we are debugging
  with any new events that the ES may generate 

- Next, I take a look at ``/var/log/zm/zmeventnotification.log`` for the event that invoked a hook. Let's take 
  this as an example:

::

   01/06/2021 07:20:31.936130 zmeventnotification[28118].DBG [main:977] [|----> FORK:DeckCamera (6), eid:182253 Invoking hook on event start:'/var/lib/zmeventnotification/bin/zm_event_start.sh' 182253 6 "DeckCamera" " stairs" "/var/cache/zoneminder/events/6/2021-01-06/182253"]


Let's assume the above is what I want to debug, so then I run zm_detect manually like so:

::

   sudo -u www-data /var/lib/zmeventnotification/bin/zm_detect.py --config /etc/zm/objectconfig.yml --debug --eventid 182253 --monitorid 6 --eventpath=/tmp


Note that instead of ``/var/cache/zoneminder/events/6/2021-01-06/182253`` as the event path, I just use ``/tmp`` as it is easier for me. Feel free to use the actual
event path (that is where objdetect.jpg/json are stored if an object is found). 

This will print debug logs on the terminal.


Manually testing if detection is working well
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

You can manually invoke ``zm_detect.py`` to check if detection works:

.. code:: bash

    # Test with a ZM event
    sudo -u www-data /var/lib/zmeventnotification/bin/zm_detect.py \
        --config /etc/zm/objectconfig.yml --eventid <eid> --monitorid <mid> --debug

    # Test with a local image file (no ZM event needed)
    sudo -u www-data /var/lib/zmeventnotification/bin/zm_detect.py \
        --config /etc/zm/objectconfig.yml --file /path/to/image.jpg --debug

The ``--monitorid <mid>`` is optional. If specified, monitor-specific settings
(zones, ml_sequence overrides, etc.) from ``objectconfig.yml`` will be used.

The ``--debug`` flag prints detailed logs to the terminal.

**Testing with the ES (if using hook mode):**

1. Run ``zm_detect.py`` manually as shown above to verify detection works
2. Stop the ES: ``sudo zmdc.pl stop zmeventnotification.pl``
3. Set ``console_logs: "yes"`` in ``zmeventnotification.yml``
4. Start it manually: ``sudo -u www-data /usr/bin/zmeventnotification.pl --debug``
5. Force an alarm and check the output

zm_detect.py command-line reference
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

::

    zm_detect.py [-h] [-c CONFIG] [-e EVENTID] [-p EVENTPATH] [-m MONITORID]
                 [-v] [--bareversion] [-o OUTPUT_PATH] [-f FILE] [-r REASON]
                 [-n] [-d] [--fakeit LABELS] [--pyzm-debug]

``-c, --config``
    Path to ``objectconfig.yml`` (required).

``-e, --eventid``
    ZM event ID to analyze (required unless ``--file`` is given).

``-f, --file``
    Skip event download, detect on a local image file instead.

``-m, --monitorid``
    Monitor ID. Enables per-monitor overrides (zones, ml_sequence, etc.) from config.

``-p, --eventpath``
    Path to store output files (``objdetect.jpg``, ``objects.json``).

``-r, --reason``
    Reason/cause string for the event (passed by ZM or the ES).

``-n, --notes``
    Update ZM event notes with detection results.

``-d, --debug``
    Print debug logs to terminal.

``--fakeit LABELS``
    Override detection with fake labels for testing (comma-separated).
    Example: ``--fakeit "dog,person"``

``--pyzm-debug``
    Route pyzm library internal debug logs through ZMLog.

``-v, --version``
    Print version and exit.

Questions
~~~~~~~~~~~
See :doc:`hooks_faq`
