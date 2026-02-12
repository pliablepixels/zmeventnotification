Machine Learning Hooks
======================

.. note::

        Before you install machine learnings hooks, please make sure you have installed
        the Event Notification Server (:doc:`install`) and have it working properly

.. important::

        Please don't ask me basic questions like "pip3 command not found - what do I do?" or
        "cv2 not found, how can I install it?" Hooks require some terminal
        knowledge and familiarity with troubleshooting. I don't plan to
        provide support for these hooks. They are for reference only


Key Features 
~~~~~~~~~~~~~

- Detection: objects, faces 
- Recognition: faces 
- Platforms: 

   - CPU (object, face detection, face recognition), 
   - GPU (object, face detection, face recognition), 
   - EdgeTPU (object, face detection)

- Machine learning can be installed locally with ZM, or remotely via mlapi 

Limitations
~~~~~~~~~~~

- Only tested with ZM 1.32+. May or may not work with older versions
- Needs Python3 (Python2 is not supported)

What
~~~~

Kung-fu machine learning goodness.

This is an example of how you can use the ``hook`` feature of the
notification server to invoke a custom script on the event before it
generates an alarm. I currently support object detection and face
recognition.

Please don't ask me questions on how to use them. Please read the
extensive documentation and ini file configs


.. _hooks_install:

Installation
~~~~~~~~~~~~

Automatic install
^^^^^^^^^^^^^^^^^^^^^^^^^^^

-  You need to have ``pip3`` installed. On ubuntu, it is
   ``sudo apt install python3-pip``, or see
   `this <https://pip.pypa.io/en/stable/installing/>`__
-  Clone the event server and go to the ``hook`` directory

.. code:: bash

    git clone https://github.com/pliablepixels/zmeventnotification # if you don't already have it downloaded

    cd zmeventnotification

-  (OPTIONAL) Edit ``hook/zm_event_start.sh`` and change:

   -  ``CONFIG_FILE`` to point to the right config file, if you changed
      paths

::

   sudo -H ./install.sh # and follow the prompts

I use a library called `Shapely <https://github.com/Toblerity/Shapely>`__ for polygon intersection checks.
Shapely requires a library called GeOS. If you see errors related to ``Failed `CDLL(libgeos_c.so)``` 
you may manually need to install libgeos  like so:

::

   sudo apt-get install libgeos-dev

**Google TPU**:
If you are planning on using Google EdgeTPU support,
you'll have to invoke the script using:

::

   sudo -H INSTALL_CORAL_EDGETPU=yes ./install.sh # and follow the prompts

EdgeTPU models/underlying libraries are not downloaded automatically.

For EdgeTPU, the expectation is  that you have followed all the instructions 
at `the coral site <https://coral.ai/docs/accelerator/get-started/>`__ first. 
Specifically, you need to make sure you have:

   1. Installed the right libedgetpu library (max or std)
   2. Installed the right tensorflow-lite library 
   3. Installed pycoral APIs as per `the instructions <https://coral.ai/software/#pycoral-api>`__.


If you don't, things will break. Further, you also need to make sure your 
web user has access to the coral device.

On my ubuntu system, I needed to do:

::

   sudo usermod -a -G plugdev www-data

**Very important**: You need to reboot after this, otherwise, you may notice that the TPU
code crashes when you run the ES in daemon mode (may work fine in manual mode). Replace 'plugdev' with 'apex' for the Coral PCIe accelerator.


.._install-specific-models:

You can *optionally* choose to only install specific models by passing them as variables to the install script. The variables are labelled as ``INSTALL_<model>`` with possible values of ``yes`` or ``no``. ``<model>`` is the specific model.

Current model flags and their defaults:

- ``INSTALL_YOLOV3``: ``no``
- ``INSTALL_TINYYOLOV3``: ``no``
- ``INSTALL_YOLOV4``: ``yes``
- ``INSTALL_TINYYOLOV4``: ``yes``
- ``INSTALL_CORAL_EDGETPU``: ``no``
- ``INSTALL_YOLOV26``: ``yes`` (requires OpenCV 4.10+)

So for example:

::

  sudo INSTALL_YOLOV4=no INSTALL_YOLOV26=yes ./install.sh

Will install the ``YOLOv26 ONNX`` models but will skip ``YOLOv4``.

Another example:

::

   sudo -H INSTALL_CORAL_EDGETPU=yes ./install.sh --install-es --no-install-config --install-hook

Will install the ES and hooks, but no configs and will add the coral libraries.

.. note::

   The default object detection model is now **YOLOv26 ONNX** (via OpenCV DNN). This requires
   OpenCV 4.10 or above. Direct Ultralytics/PyTorch support has been removed in favor of ONNX
   inference through OpenCV's DNN module.

.. _opencv_install:

**Note:**: If you plan on using object detection, starting v5.0.0 of the ES, the setup script no longer installs opencv for you. This is because you may want to install your own version with GPU acceleration or other options. There are two options to install OpenCV:

  - You install a pip package. Very easy, but you don't get GPU support
  - You compile from source. Takes longer, but you get all the right modules as well as GPU support. Instructions are simple, if you follow them well.

  .. important::

    However you choose to install openCV, you need a minimum version of `4.1.1`. Using a version below that will very likely not work.


Installing OpenCV: Using the pip package (Easy, but not recommended if you plan to use OpenCV ML - example Yolo)
''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

::

  # Note this does NOT enable GPU support
  # It also seems to miss modules like bgsem etc

  sudo -H pip3 install opencv-contrib-python

  # NOTE: Do NOT install both opencv-contrib-python and opencv packages via pip. The contrib package includes opencv+extras


Installing OpenCV: from source (Recommended if you plan to use OpenCV ML - example Yolo)
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
General installation instructions are available at the `official openCV site <https://docs.opencv.org/master/d7/d9f/tutorial_linux_install.html>`__. However, see below, if you are looking for GPU support:

If you want to install a version with GPU support, I'd recommend you install OpenCV 4.2.x because it supports a CUDA backend for deep learning. Adrian's blog has a `good howto <https://www.pyimagesearch.com/2020/02/03/how-to-use-opencvs-dnn-module-with-nvidia-gpus-cuda-and-cudnn/>`__ on compiling OpenCV 4.2.x from scratch.

**I would strongly recommend you build from source, if you are able to. Pre built packages are not official from OpenCV and often seem to break/seg fault on different configurations.**

.. _opencv_seg_fault:

Make sure OpenCV works
+++++++++++++++++++++++

.. important::

  After you install opencv, make sure it works. Start python3 and inside the interpreter, do a ``import cv2``. If it seg faults, you have a problem with the package you installed. Like I said, I've never had issues after building from source.

  Note that if you get an error saying ``cv2 not found`` that means you did not install it in a place python3 can find it (you might have installed it for python2 by mistake)



**Note 3:** if you want to add "face recognition" you also need to do the following: (Note that if you are using Google Coral,
you can do face detection [not recognition] by using the coral libraries as well. You can skip this section if you want to use TPU based face detection)

::

    sudo apt-get install libopenblas-dev liblapack-dev libblas-dev  # not mandatory, but gives a good speed boost!
    sudo -H pip3 install face_recognition # mandatory

Takes a while and installs a gob of stuff, which is why I did not add it
automatically, especially if you don't need face recognition.

Note, if you installed ``face_recognition`` earlier without blas, do this:

.. code:: bash

  sudo -H pip3 uninstall dlib
  sudo -H pip3 uninstall face-recognition
  sudo apt-get install libopenblas-dev liblapack-dev libblas-dev # this is the important part
  sudo -H pip3 install dlib --verbose --no-cache-dir # make sure it finds openblas
  sudo -H pip3 install face_recognition

Option 2: Manual install
^^^^^^^^^^^^^^^^^^^^^^^^
If automatic install fails for you, or you like to be in control, take a look at what ``install.sh`` does. I used to maintain explicit instructions on manual install, but its painful to keep this section in sync with ``install.sh``


Post install steps
~~~~~~~~~~~~~~~~~~

-  Make sure you edit your installed ``objectconfig.yml`` to the right
   settings. You MUST change the ``general`` section for your own
   portal.
-  Make sure the ``CONFIG_FILE`` variable in ``zm_event_start.sh`` is
   correct


Test operation
~~~~~~~~~~~~~~

::

    sudo -u www-data /var/lib/zmeventnotification/bin/zm_event_start.sh <eid> <mid> # replace www-data with apache if needed

Replace with your own ``eid`` (Example 123456). This will be an event id for an event that you want to test. Typically,
open up the ZM console, look for an event you want to run analysis on and select the ID of the event. That is the ``eid``.
The ``mid`` is the monitor ID for the event. This is optional. If you specify it, any monitor specific settings (such as 
zones, hook customizations, etc. in ``objectconfig.yml``/``mlapiconfig.ini`` will be used).

The above command will  try and run detection.

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
     ml_fallback_local: "yes"


.. _supported_models:

Which models should I use?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- **YOLOv26 ONNX (Recommended)**: The default and recommended model. Uses ONNX format via OpenCV's DNN
  module. Requires OpenCV 4.10+. Multiple sizes are available (``yolo26n``, ``yolo26s``, ``yolo26m``,
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

  **Note**: If you are using mlapi, there are certain parameters that get overridden by ``objectconfig.yml``
  See :ref:`mlapi_overrides`

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

``ml_sequence`` supports various other attributes. Please see `the pyzm API documentation <https://pyzm.readthedocs.io/en/latest/source/pyzm.html#pyzm.ml.detect_sequence.DetectSequence>`__
that describes all options. The ``options`` parameter is what you are looking for.

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

``stream_sequence`` supports various other attributes. Please see `the pyzm API documentation <https://pyzm.readthedocs.io/en/latest/source/pyzm.html#pyzm.ml.detect_sequence.DetectSequence.detect_stream>`__
that describes all options. The ``options`` parameter is what you are looking for.


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
     ml_fallback_local: "yes"
     ml_user: "!ML_USER"
     ml_password: "!ML_PASSWORD"
     ml_timeout: 60

When ``ml_gateway`` is set, ``zm_detect.py`` creates the ``Detector`` in remote mode.
Frame extraction still happens locally on the ZM box (it has ZM API access), but each
frame is JPEG-encoded and POSTed to the remote server for inference. The server keeps
models loaded in memory so subsequent requests skip the expensive model-load step.

If the remote server is unreachable and ``ml_fallback_local`` is ``yes``, detection
falls back to running locally on the ZM box.

All other settings (``ml_sequence``, ``stream_sequence``, monitor overrides, animation,
image writing, etc.) stay in ``objectconfig.yml`` — there is no second config file to manage.

Server endpoints:

- ``GET /health`` — returns ``{"status": "ok", "models_loaded": true}``
- ``POST /detect`` — accepts multipart ``file`` (JPEG) + optional ``zones`` (JSON), returns detection results
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


Troubleshooting
~~~~~~~~~~~~~~~

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


Performance comparison 
~~~~~~~~~~~~~~~~~~~~~~~

* CPU: Intel(R) Xeon(R) CPU E5-1660 v3 @ 3.00GHz 8 cores, with 32GB RAM
* GPU: GeForce 1050Ti
* TPU: Google Coral USB stick, running on USB 3.0 in 'standard' mode 
* Environment: I am running using mlapi, so you will see load time only once across multiple runs 
* Image size: 800px

The TPU is running in standard mode, not max. Also note that these figures use pycoral, which is a python
wrapper around the TPU C++ libraries. 
You should also look at  Google's Coral `coral benchmark site <https://coral.ai/docs/edgetpu/benchmarks/>`__ for better numbers.
Note that their performance figures are specific to their C++ code. Python will have 
additional overheads (as noted on their site)
Finally, if you are facing data transfter/delegate loading issues considering buying a good quality USB 3.1/10Gbps rated
cable. I faced intermittent issues with delegate load issues (not always) which seems to have gone away after I ditched 
Google's cable with a good quality one (I bought `this one <https://www.amazon.com/Anker-Powerline-Certified-Samsung-MacBook/dp/B07213D35X/ref=sr_1_4?dchild=1&keywords=usb+3.1+anker+usb+c&qid=1611410490&sr=8-4>`__)

::

   pp@homeserver:/var/lib/zmeventnotification/mlapi$ tail -F /var/log/zm/zm_mlapi.log | grep "perf:"

  
   First Run (Model load included):

   01/25/21 14:45:19 zm_mlapi[953841] DBG1 detect_sequence.py:398 [perf: Starting for frame:snapshot]
   01/25/21 14:45:22 zm_mlapi[953841] DBG1 coral_edgetpu.py:93 [perf: processor:tpu TPU initialization (loading /var/lib/zmeventnotification/models/coral_edgetpu/ssdlite_mobiledet_coco_qat_postprocess_edgetpu.tflite from disk) took: 3086.99 ms]
   01/25/21 14:45:22 zm_mlapi[953841] DBG1 coral_edgetpu.py:179 [perf: processor:tpu Coral TPU detection took: 39.30 ms]
   01/25/21 14:45:22 zm_mlapi[953841] DBG1 yolo.py:88 [perf: processor:gpu Yolo initialization (loading /var/lib/zmeventnotification/models/yolov4/yolov4.weights model from disk) took: 182.36 ms]
   01/25/21 14:45:23 zm_mlapi[953841] DBG1 yolo.py:169 [perf: processor:gpu Yolo detection took: 1249.93 ms]
   01/25/21 14:45:23 zm_mlapi[953841] DBG2 yolo.py:204 [perf: processor:gpu Yolo NMS filtering took: 0.68 ms]
   01/25/21 14:45:26 zm_mlapi[953841] DBG1 face.py:40 [perf: processor:gpu Face Recognition library load time took: 0.00 ms ]
   01/25/21 14:45:30 zm_mlapi[953841] DBG1 face.py:201 [perf: processor:gpu Finding faces took 4418.08 ms]
   01/25/21 14:45:30 zm_mlapi[953841] DBG1 face.py:213 [perf: processor:gpu Computing face recognition distances took 80.49 ms]
   01/25/21 14:45:30 zm_mlapi[953841] DBG1 face.py:245 [perf: processor:gpu Matching recognized faces to known faces took 3.13 ms]
   01/25/21 14:45:30 zm_mlapi[953841] DBG1 detect_sequence.py:398 [perf: Starting for frame:alarm]

   Second Run:

   01/25/21 14:45:35 zm_mlapi[953841] DBG1 detect_sequence.py:398 [perf: Starting for frame:snapshot]
   01/25/21 14:45:35 zm_mlapi[953841] DBG1 coral_edgetpu.py:179 [perf: processor:tpu Coral TPU detection took: 24.66 ms]
   01/25/21 14:45:35 zm_mlapi[953841] DBG1 yolo.py:169 [perf: processor:gpu Yolo detection took: 58.06 ms]
   01/25/21 14:45:35 zm_mlapi[953841] DBG2 yolo.py:204 [perf: processor:gpu Yolo NMS filtering took: 1.35 ms]
   01/25/21 14:45:35 zm_mlapi[953841] DBG1 face.py:201 [perf: processor:gpu Finding faces took 290.92 ms]
   01/25/21 14:45:35 zm_mlapi[953841] DBG1 face.py:213 [perf: processor:gpu Computing face recognition distances took 14.51 ms]
   01/25/21 14:45:35 zm_mlapi[953841] DBG1 face.py:245 [perf: processor:gpu Matching recognized faces to known faces took 2.23 ms]


Manually testing if detection is working well
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

You can manually invoke the detection module to check if it works ok:

.. code:: bash

    sudo -u www-data /var/lib/zmeventnotification/bin/zm_detect.py --config /etc/zm/objectconfig.yml --eventid <eid> --monitorid <mid> --debug

The ``--monitorid <mid>`` is optional and is the monitor ID. If you do
specify it, it will pick up the right mask to apply (if it is in your
config)


**STEP 1: Make sure the scripts(s) work** 

- Run the python script manually to see if it works (refer to sections above on how to run them manually) 
- ``./zm_event_start.sh <eid> <mid>`` --> make sure it
  downloads a proper image for that eid. Make sure it correctly invokes
  detect.py If not, fix it. (``<mid>`` is optional and is used to apply a
  crop mask if specified) 
- Make sure the ``image_path`` you've chosen in the config file is WRITABLE by www-data (or apache) before you move to step 2

**STEP 2: run zmeventnotification in MANUAL mode** 

- ``sudo zmdc.pl stop zmeventnotification.pl`` 
- change console_logs to yes in ``zmeventnotification.yml``
-  ``sudo -u www-data ./zmeventnotification.pl  --config ./zmeventnotification.yml``
-  Force an alarm, look at logs

**STEP 3: integrate with the actual daemon** 
- You should know how to do this already

Questions
~~~~~~~~~~~
See :doc:`hooks_faq`
