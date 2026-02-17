Machine Learning Hooks FAQ
===========================

How do the hooks actually invoke object detection?
-----------------------------------------------------

* When the Event Notification Server detects an event, it invokes the script specified in ``event_start_hook`` in your ``zmeventnotification.yml``. This is typically ``/var/lib/zmeventnotification/bin/zm_event_start.sh``

* ``zm_event_start.sh`` in turn invokes ``zm_detect.py`` that does the actual machine learning. Upon exit, it returns ``0`` (success) meaning an object was found, or ``1`` (failure) meaning nothing was detected. Based on how you have configured your settings, this information is then stored in ZM and/or pushed to your mobile device as a notification.


Necessary Reading - Sample Config Files
----------------------------------------
The sample configuration files, `zmeventnotification.example.yml <https://github.com/pliablepixels/zmeventnotification/blob/master/zmeventnotification.example.yml>`__ and `objectconfig.yml <https://github.com/pliablepixels/zmeventnotification/blob/master/hook/objectconfig.yml>`__ come with extensive commentary about each attribute and what they do. Please go through them to get a better understanding. Note that most of the configuration attributes in ``zmeventnotification.yml`` are not related to machine learning, except for the ``hook`` section.

.. _hooks-debug-issues:

How To Debug Issues
---------------------

* Make sure you have debug logging enabled as described in :ref:`es-hooks-logging`
* Don't just post the final error message. Please post *full* debug logs when reporting problems.

If you have problems with hooks, there are three areas of failure:

1. **The ES is unable to invoke hooks properly** (missing files, wrong paths, etc.)
   — This will be reported in ES logs. See :ref:`this section <debug_reporting_es>`.

2. **Hooks don't work** (detection script fails or returns unexpected results)
   — Covered by the debugging steps below and in :ref:`triage-no-detection`.

3. **The wrapper script** (typically ``/var/lib/zmeventnotification/bin/zm_event_start.sh``) **is not able to run** ``zm_detect.py``
   — This won't be covered in either log (I need to add logging for this...).

**Debugging hooks step by step:**

- Stop the ES if it is running (``sudo zmdc.pl stop zmeventnotification.pl``) so that we don't mix up what we are debugging
  with any new events that the ES may generate.

- Next, look at ``/var/log/zm/zmeventnotification.log`` for the event that invoked a hook. For example::

   01/06/2021 07:20:31.936130 zmeventnotification[28118].DBG [main:977] [|----> FORK:DeckCamera (6), eid:182253 Invoking hook on event start:'/var/lib/zmeventnotification/bin/zm_event_start.sh' 182253 6 "DeckCamera" " stairs" "/var/cache/zoneminder/events/6/2021-01-06/182253"]

- Then run ``zm_detect.py`` manually with debug flags::

   sudo -u www-data /var/lib/zmeventnotification/bin/zm_detect.py --config /etc/zm/objectconfig.yml --debug --eventid 182253 --monitorid 6 --eventpath=/tmp

  (You can use ``/tmp`` as the event path for convenience, or the actual event path shown in the log.)

- This will print debug logs on the terminal showing exactly what went wrong.

**Testing with the ES (if using hook mode):**

1. Run ``zm_detect.py`` manually as shown above to verify detection works.
2. Stop the ES: ``sudo zmdc.pl stop zmeventnotification.pl``
3. Set ``console_logs: "yes"`` in ``zmeventnotification.yml``.
4. Start it manually: ``sudo -u www-data /usr/bin/zmeventnotification.pl --debug``
5. Force an alarm and check the output.


.. _triage-no-detection:

Triaging "No Detection" Problems
----------------------------------

If your events are not getting detection results, follow these steps to isolate the problem.

**Step 1: Find the hook invocation in ES logs**

Look at your ``zmeventnotification.log`` for lines like::

   FORK:DoorBell (2), eid:12345 Invoking hook on event start:'/var/lib/zmeventnotification/bin/zm_event_start.sh' 12345 2 "DoorBell" "Motion" "/var/cache/zoneminder/events/2/2026-02-14/12345"

This tells you the exact arguments the ES passed to the hook script:
``<eid> <mid> "<MonitorName>" "<Cause>" "<EventPath>"``.

**Step 2: Run zm_detect manually with debug flags**

Translate the hook invocation into a direct ``zm_detect.py`` call and add
``--debug`` and ``--pyzm-debug`` for full diagnostic output::

   sudo -u www-data /var/lib/zmeventnotification/bin/zm_detect.py \
     --eventid <eid> \
     --monitorid <mid> \
     --config /etc/zm/objectconfig.yml \
     --eventpath "<EventPath>" \
     --reason "<Cause>" \
     --debug \
     --pyzm-debug

Replace ``<eid>``, ``<mid>``, ``<EventPath>``, and ``<Cause>`` with the values
from your log line. The ``sudo -u www-data``
is important — it runs the script as the same user the ES uses, so file permissions
and library paths match.

- ``--debug`` enables verbose console output from zm_detect itself.
- ``--pyzm-debug`` routes the pyzm library's internal debug logs (model loading,
  frame download, inference) through the same log, so you can see exactly what
  the ML pipeline is doing.

**Step 3: Read the output**

Common things to look for:

- **Import errors** (e.g. ``cv2``, ``numpy``, ``pyzm``) — a library is not installed
  globally or not visible to the ``www-data`` user.
- **Config errors** — bad YAML syntax, missing model files, wrong paths in
  ``objectconfig.yml``.
- **Frame download failures** — ZM API unreachable, authentication issues, or the
  event frames haven't been written to disk yet (see the snapshot/alarm timing
  section below).

  One common reason detection fails is that the hook cannot download the event image.
  To verify image downloads work:

  -  Make sure your ``objectconfig.yml`` ``general`` section settings are
     correct (portal, user, admin).
  -  The hooks download images using URLs like
     ``https://yourportal/zm/?view=image&eid=<eid>&fid=snapshot`` and
     ``https://yourportal/zm/?view=image&eid=<eid>&fid=alarm``.
  -  Open a browser, log into ZM, then in a new tab try
     ``https://yourportal/zm/?view=image&eid=<eid>&fid=snapshot``
     (replace ``<eid>`` with a real event ID). Do you see an image? If not,
     your ZM portal settings need fixing — post in the ZM forums for help.
  -  Do the same with ``fid=alarm``. If that doesn't return an image either,
     your ZM version may need updating.

- **Model loading failures** — missing weight files, incompatible OpenCV version,
  Coral TPU not accessible.
- **No detections** — the model ran successfully but didn't find any objects in the
  frame. Try ``write_debug_image: yes`` in ``objectconfig.yml`` to save the frame
  that was actually analyzed.


My hooks run fine in manual mode, but don't in daemon mode
------------------------------------------------------------
The errors are almost always related to the fact that when run in daemon mode, Python cannot find certain
libraries (example ``cv2``). This usually happens if you don't install these libraries globally (i.e. for all users).

To zero-in on what is going on:

   - Make sure you have set up logging as per :ref:`es-hooks-logging`. This should
     ensure these sort of errors are caught in the logs.
   - Try and run the script manually the way the daemon calls it. You will see the invocation in ``zmeventnotification.log``.
     Run it with ``sudo -u www-data`` to match the daemon's user — see :ref:`triage-no-detection` for the full procedure.

One user reported that they never saw logs. I get the feeling its because logs were not setup correctly, but there are some other insights
worth looking into. See `here <https://forums.zoneminder.com/viewtopic.php?f=33&p=119084&sid=8438a0ec567b9b7206bcd2372e22c615#p119084>`__


It looks like when ES invokes the hooks, it misses objects, but when I run it manually, it detects it just fine
------------------------------------------------------------------------------------------------------------------

This is a very common situation. Here is what is likely happening:

* If you have configured ``BESTMATCH`` then the hooks will search for both your "alarmed" frame and the "snapshot" frame for objects. If you have configured ``snapshot``, ``alarm`` or a specific ``fid=xx`` only that frame will be searched

* An 'alarm' frame is the first frame that caused the motion trigger
* A 'snapshot' frame is the frame with the *highest* score in the event

The way ZM works is that the 'snapshot' frame may keep changing till the full event is over. This is because as event frames are analyzed, if their 'score' is higher than the current snapshot score, the frame is replaced.

The 'alarm' frame is more static, but it may still take some finite time to be written to disk. If the alarm frame is not written by the time the hooks request it, ZM will return the first frame.

What is likely happening in your case is that when the hooks are invoked, your snapshot frame is the current frame with the highest score, and your alarmed frame may or may not be written to disk yet. So the hooks run on what is available.

However, when you run it manually later, your snapshot image has likely changed. It is possible as well that your alarmed frame exists now, whereas it did not exist before.

How do I make sure this is what is happening?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
- Enable ``write_debug_image`` in ``objectconfig.yml``. This will create a debug image inside the event path where your event recording is. Take a look at the debug images it creates. Is it the same as the images you see at a later date? If not, you know this is exactly what is happening
- When you run the detection script manually, see if its printing an ``[a]`` or an ``[s]`` before the detected text. The latter means ``snapshot`` and if that is so, the chances are very high this is exactly what the issue is. In case it prints ``[a]`` it also means the same thing, but the occurrence of this is less than snapshot.

How do I solve this issue?
~~~~~~~~~~~~~~~~~~~~~~~~~~
- Add a ``wait: 5`` to that monitor in ``objectconfig.yml``. This delays hook execution by 5 seconds, giving ZM time to write the right frames to disk.
- Use ``stream_sequence`` retry settings (``max_attempts``, ``sleep_between_attempts``) to automatically retry frame downloads.
- Fix your zone triggers. This is really the right way. If you use object detection, re-look at how your zone triggers to be able to capture the object of interest as soon as possible. If you do that, chances are high that by the time the script runs, the image containing the object will be written to disk.


I am trying to use YoloV4 and I see errors in OpenCV
-----------------------------------------------------
- If you plan to use YoloV4 (full or Tiny) the minimum version requirement OpenCV 4.4.
  So if you suddently see an error like: ``Unsupported activation: mish in function 'ReadDarknetFromCfgStream'``
  popping up with YoloV4, that is a sign that you need to get a later version of OpenCV.

.. note::

   The default model is now YOLOv11 (ONNX format), which requires **OpenCV 4.13+**.
   If you are using the default configuration, make sure your OpenCV version meets
   this requirement. YoloV4 (OpenCV 4.4+) is still supported as a fallback.

I'm having issues with accuracy of Face Recognition
-----------------------------------------------------
- Use ``cnn`` mode in face recognition. Much slower, but far more accurage than ``hog``
-  Look at debug logs.

   -  If it says "no faces loaded" that means your known images don't
      have recognizable faces
   -  If it says "no faces found" that means your alarmed image doesn't
      have a face that is recognizable
   -  Read comments about ``num_jitters``, ``model``, ``upsample_times``
      in ``objectconfig.yml``

-  Experiment. Read the `accuracy wiki <https://github.com/ageitgey/face_recognition/wiki/Face-Recognition-Accuracy-Problems>`__ link.


I get ``ModuleNotFoundError: No module named 'pycoral'`` when using the Coral TPU
----------------------------------------------------------------------------------
The ``pycoral`` library is **not** installed by the ES installer — it only downloads
the TPU model files. You must install the Coral runtime and Python API yourself:

1. Follow the setup guide at https://coral.ai/docs/accelerator/get-started/
2. Install the correct ``libedgetpu`` library (max or standard performance)
3. Install the pycoral API: ``pip3 install pycoral``
   (or see https://coral.ai/software/#pycoral-api)

   .. warning::

      Installing ``pycoral`` on Python 3.10+ is not straightforward — Google's official
      packages only support up to Python 3.9. See
      `pycoral#149 <https://github.com/google-coral/pycoral/issues/149>`__ for
      community workarounds and alternative installation methods.

4. Make sure your web user has access to the Coral USB device::

      sudo usermod -a -G plugdev www-data

I am using a Coral TPU and while it works fine, at times it fails loading
--------------------------------------------------------------------------
If you have configured the TPU properly, and on occasion you see an error like:

::

   Error running model: Failed to load delegate from libedgetpu.so.1

then it is likely that you either need to replace your USB cable or need to reset your
USB device. In my case, after I set it up correctly, it would often show the error above
during runs. I realized that replacing the USB cable that Google provided solved it for
a majority of cases. See `this comment <https://github.com/tensorflow/tensorflow/issues/32743#issuecomment-766084239>`__
for my experience on the cable. After buying the cable, I still saw it on occasion, but
not frequently at all. In those cases, resetting USB works fine and you don't have to reboot.
See `this comment <https://github.com/tensorflow/tensorflow/issues/32743#issuecomment-808912638>`__.

I get a segment fault/core dump while trying to use opencv in detection
--------------------------------------------------------------------------
See :ref:`opencv_seg_fault`.

.. _local_remote_ml:

Local vs. Remote server for Machine Learning
---------------------------------------------
You can offload ML inference to a remote server using ``pyzm.serve``, the built-in
remote ML detection server that replaces the legacy ``mlapi``. On the remote (GPU) box::

   pip install pyzm[serve]
   python -m pyzm.serve --models yolo11s --port 5000

Then in ``objectconfig.yml`` on the ZM box, set::

   remote:
     ml_gateway: "http://gpu-box:5000"
     ml_gateway_mode: "url"
     ml_fallback_local: "yes"
     ml_user: "!ML_USER"
     ml_password: "!ML_PASSWORD"
     ml_timeout: 60

The advantage: models load once on the server and persist in memory, so subsequent
detections are fast. If the remote server is down and ``ml_fallback_local`` is ``yes``,
detection falls back to local inference automatically.

**Choosing a gateway mode:**

- ``ml_gateway_mode: "image"`` (default) — the ZM box fetches frames locally, JPEG-encodes
  them, and uploads to the server. Works even if the GPU box can't reach ZM directly.
  You still need OpenCV on the ZM box for frame extraction.

- ``ml_gateway_mode: "url"`` (recommended) — the ZM box sends frame URLs to the server,
  and the **server** fetches images directly from ZoneMinder. More efficient because frames
  don't pass through the ZM box as an intermediary. Requires that the GPU box can reach
  your ZM web portal over the network. With this mode, you don't need ML libraries *or*
  OpenCV on the ZM box for the detection itself (OpenCV is still needed if you use
  ``write_image_to_zm`` or ``write_debug_image``).

See :ref:`remote_ml_config` for full setup details
