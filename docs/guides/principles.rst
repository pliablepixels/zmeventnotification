Key Principles — How Detection and Notifications Work
======================================================

Summary
+++++++++
This guide explains the detection and notification flow for ZoneMinder's ML ecosystem. There are two paths:

* **Path 1 (Detection only)** — ZoneMinder calls ``zm_detect.py`` directly via ``EventStartCommand``. No daemon, no notifications.
* **Path 2 (Full Event Server)** — The Event Notification Server (ES) monitors shared memory for new events, invokes ML hooks, and sends push notifications via FCM, WebSockets, MQTT, and 3rd-party APIs.

Both paths use the same ML pipeline (``zm_detect.py`` + ``objectconfig.yml``). The difference is what triggers detection and what happens with the results.

Path 1: From Event to Detection
+++++++++++++++++++++++++++++++++

.. note::

   Path 1 requires ZoneMinder 1.38.1 or later, which introduced ``EventStartCommand`` support.

1: ZoneMinder triggers the detection
--------------------------------------
When ZoneMinder detects motion and creates a new event, it calls the command configured in ``EventStartCommand``. ZM substitutes runtime tokens before invoking the command:

* ``%EID%`` — the Event ID
* ``%MID%`` — the Monitor ID
* ``%EC%`` — the Event Cause string

A typical ``EventStartCommand`` looks like:

::

  /var/lib/zmeventnotification/bin/zm_detect.py -e %EID% -m %MID% -r "%EC%" -n --pyzm-debug

(``-c`` defaults to ``/etc/zm/objectconfig.yml`` and can be omitted if your config is at the standard path.)

2: zm_detect.py runs the ML pipeline
--------------------------------------
``zm_detect.py`` reads ``/etc/zm/objectconfig.yml``, downloads frames from the event, and runs them through the configured ML pipeline (object detection, face recognition, ALPR, etc.). The pipeline is identical to what the ES invokes in Path 2 — see :ref:`how-ml-works` for details.

3: Results
-----------
When detection finishes, ``zm_detect.py`` produces the following:

* **Exit code** — ``0`` if objects matching the configured criteria were found, ``1`` otherwise.
* **Event notes** — When invoked with ``-n``, the detection string (e.g. "person, car") is written to the ZM event notes in the database.
* **Annotated image** — When ``write_image_to_zm: yes`` is set in ``objectconfig.yml``, an ``objdetect.jpg`` with bounding boxes is saved to the event folder.
* **Detection metadata** — An ``objects.json`` file with labels, boxes, confidences, and frame info is saved alongside the image.
* **Event tags** — When ``tag_detected_objects: yes`` (requires ZM >= 1.37.44), detected labels are tagged in ZoneMinder.

That is the complete Path 1 flow. There is no daemon running, no shared memory polling, and no notifications — ZoneMinder calls the script, the script runs detection, and results are written back to the event.

.. _from-detection-to-notification:

Path 2: From Event Detection to Notification
+++++++++++++++++++++++++++++++++++++++++++++

.. note::

   This section covers the full Event Notification Server (ES) flow. If you are using Path 1 (detection only via ``EventStartCommand``), you can skip this section.

1: How it starts
----------------------
The ES is a perl process (typically ``/usr/bin/zmeventnotification.pl``) that acts like just any other ZM daemon (there are many) that is started by ZoneMinder when it starts up. Specifically, the ES gets "auto-started" only if you have enabled ``OPT_USE_EVENT_NOTIFICATION`` in your ``Zoneminder->System`` menu options. Technically, ZM uses a 'control' process called ``zmdc.pl`` that starts a bunch of important daemons (run ``sudo zmdc.pl status`` to see a list of daemons on your system) and keeps a tab on them. If any of them die, they get restarted.

.. sidebar:: Configuration files

    This may be a good place to talk about configuration files. The ES has many customizations that are controlled by ``/etc/zm/zmeventnotification.yml``. If you are using hooks, they are controlled by ``/etc/zm/objectconfig.yml``. Both these files use ``/etc/zm/secrets.yml`` to move personal information away from config files. Study both these config files well. They are heavily commented for your benefit.

2: Detecting New Events
-----------------------------
Once the ES is up and running, it uses shared memory to know when new events are reported by ZM. Basically, ZM writes data to shared memory (SHM) whenever a new event is detected. The ES regularly polls this memory to detect new events. This has 2 important side effects:

* The ES *must* run on the same server that ZM is running on. If you are using a multi-server system, you need an ES *per* server.
* If an event starts and ends before the ES checks SHM, this event may be missed. If you are seeing that happening, reduce ``event_check_interval`` in ``zmeventnotification.yml``. By default this is set to 5 seconds, which means events that open and close in a span of 5 seconds have a potential of being missed, if they start immediately after the ES checks for new events.

.. _when_event_starts:

3: Deciding what to do when a new event starts
-----------------------------------------------------
When the ES detects a new event, it forks a sub-process to handle that event and continues its loop to listening for new events (by polling SHM). There is exactly one fork for each new event and that fork typically lives till the event is completely finished.

3.1: Hooks (Optional)
***************************

If you are *not* using hooks, that is ``use_hooks=no`` in ``/etc/zm/zmeventnotification.yml`` then directly skip to the next section.

The purpose of hooks is to influence whether or not to send a notification for a new event. The most common hook performs object/person/face detection on the event's images to decide whether the event warrants a notification. Without hooks, you would receive a push notification for *every* event ZM reports.

When hooks are enabled, the script invoked on a new event is defined by ``event_start_hook`` in ``zmeventnotification.yml``. This section assumes you are using the default hook script, ``/var/lib/zmeventnotification/bin/zm_event_start.sh``, which does the following:

* It invokes ``/var/lib/zmeventnotification/bin/zm_detect.py``, which performs object detection and waits for a response. If it detects objects that meet the criteria in ``/etc/zm/objectconfig.yml`` it returns an exit code of ``0`` (success) with a text string describing the objects, otherwise it returns ``1`` (fail)
* It passes on the output and the return value of the script back to the ES

* At this stage, if hooks were used and it returned a success (``0``) and ``use_hook_description=yes`` in ``zmeventnotification.yml`` then the detection text gets written to the ZM DB for the event

The ES does not interpret the hook script's logic — it only checks the return value. A return of ``0`` means the hook succeeded; any non-zero value means it failed. This return code determines whether a notification is sent, as described below.

3.2: Will the ES send a notification?
********************************************
So at this stage, we have a new event and we need to decide if the ES will send out a notification. The following factors matter:

* If you had hooks enabled, and the hook succeeded (i.e. return value of ``0``), then the notification *may* be sent to the channels you specified in ``event_start_notify_on_hook_success``.
* If the hook failed (i.e. return value of non zero, then the notification *may* be sent to the channels specified in ``event_start_notify_on_hook_fail``)

3.2.1: Notification channels
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. note::

   While zmNg supports push notifications, it is not yet available on the App Store or Play Store and therefore FCM push will not work with zmNg as of today. Use zmNinja for push notifications until zmNg is published.

.. sidebar:: Summary of rules:

  * if hooks are used, needs to return 0 as exit status
  * Then, if you use dynamic controls (``use_escontrol_interface=yes``), those commands will be checked
  * Then, if you have a rule file (ES 6.0+), rules will have to allow it
  * Then, channel must be in the notify_on_xxx attributes
  * Then, if FCM, monitor must be in tokens.txt for that device
  * Then, if FCM, delay must be > delay specified in tokens.txt

At a high level, there are 4 types of clients that are interested in receiving notifications:

* zmNg/zmNinja: the mobile app that uses Firebase Cloud Messaging (FCM) to get push notifications. This is the "fcm" channel
* Any websocket client: This includes zmNg/zmNinja desktop and any other custom client you may have written to receive notifications via web sockets. This is the "web" channel
* receivers that use MQTT. This is the "mqtt" channel.
* Any 3rd party push solution which you may be using to deliver push notifications. A popular one is "pushover" for which I provide a `plugin <https://github.com/pliablepixels/zmeventnotification/blob/master/pushapi_plugins/pushapi_pushover.py>`__. This is the "api" channel.

So, for example:

::

  event_start_notify_on_hook_success = all
  event_start_notify_on_hook_fail = api,web

With this configuration, all channels may receive a notification when the hook succeeds, but on hook failure only API and Web channels are notified — FCM is excluded, so the zmNg/zmNinja mobile app will not receive a push. If you want to avoid excessive mobile notifications, do not include ``fcm`` in ``event_start_notify_on_hook_fail``.

3.2.2: The tokens.txt file
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Even when the channel and hook conditions are met, a notification is not guaranteed. There is an additional layer of control.

.. note::

    ``tokens.txt`` is a configuration file that affects FCM (mobile push) notification delivery. It is covered in detail below.

The file ``/var/lib/zmeventnotification/push/tokens.txt`` controls whether FCM notifications are ultimately delivered. It predates the hook system and was originally created for zmNg/zmNinja push notification support.

This file is actually created  when zmNg/zmNinja sets up push notification. Here is how it works:

* When zmNg/zmNinja runs and you enable push notifications, it asks either Apple or Google for a unique token to receive notifications via their push servers.
* This token is then sent to the ES via websockets. The ES stores this token in the ``tokens.txt`` file and every time it restarts, it reloads these tokens so it knows these clients expect notifications over FCM. **So if your zmNg/zmNinja app cannot connect to the ES for the first time, the token will never be saved and the ES will never be able to send notifications to your zmNg/zmNinja app**.

The ``tokens.txt`` file stores additional fields beyond the token itself. Here is a typical entry (migrated from a colon-separated format to JSON in ES 6.0.1):


::

  {"tokens":{"<long token>":
              { "platform":"ios",
                "monlist":"1,2,5,6,7,8,9,10",
                "pushstate":"enabled",
                "intlist":"0,120,120,120,0,120,120,0",
                "appversion":"1.5.001",
                <etc>
              }
            }
  }


* long token = unique token, we discussed this above
* monlist = list of monitors that will be processed for events for this connection. For example, in the first row, this device will ONLY get notifications for monitors 1,2,5
* intlist = interval in seconds before the next notification is sent. If we look at the first row, it says monitor 1 events will be sent as soon as they occur, however for monitor 2 and 5, notifications will only be sent if the previous notification for that monitor was *at least* 120 seconds before (2 mins). How is this set? You actually set it via zmNg/zmNinja->Settings->Event Server Settings
* platform the device type (we need this to create a push notification message correctly)
* pushstate = Finally, this tells us if push is enabled or disabled for this device. There are two ways to disable - you can disable push notifications for zmNg/zmNinja on your device, or you can simply uncheck "use event server" in zmNg/zmNinja. This is for the latter case. If you uncheck "use event server", we need to be able to tell the ES that even though it has a token on file, it should not send notifications.
* appversion = version of zmNg/zmNinja (so we know if FCMv1 is supported). For any zmNg/zmNinja version prior to ``1.6.000`` this is set to ``unknown``.

.. important::

    It is important to note here that if zmNg/zmNinja is not able to connect to the ES at least for the first time, you will never receive notifications. Check your ``tokens.txt`` file to make sure you have entries. If you don't that means zmNg/zmNinja can't reach your ES.

You will also note that ``tokens.txt`` does not contain any other entries besides android and iOS. zmNg/zmNinja desktop does not feature here, for example. That is because ``tokens.txt`` only exists to store FCM registrations. zmNg/zmNinja desktop only receives notifications when it is running and via websockets, so that connection is established when the desktop app runs. FCM tokens on the other hand need to be remembered, because zmNg/zmNinja may not be running in your phone and the ES still needs to send out notifications to all tokens (devices) that might have previously registered.


3.2.3: The Rules file
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
The ES uses a ``es_rules.yml`` that gets installed in ``/etc/zm/``.
It is a YAML file that supports various rules. Two actions are supported:

- ``mute`` — suppress the notification entirely during the matching time window
- ``critical_notify`` — escalate the notification as a critical/high-priority alert (the notification is still sent, but marked as critical)

You can specify time ranges, days of the week, and cause patterns to control when each action applies.

Here is an example of the rules file:

::

  notifications:
    monitors:
      999:
        rules:
          - comment: "Be careful with dates, no leading spaces, etc"
            time_format: "%I:%M %p"
            from: "9:30 pm"
            to: "1 am"
            daysofweek: "Mon,Tue,Wed"
            cause_has: "^(?!.*(person)).*$"
            action: mute
          - time_format: "%I:%M %p"
            from: "3 am"
            to: "6 am"
            action: mute
            cause_has: truck
          - comment: "Always escalate person detections at night"
            time_format: "%I:%M %p"
            from: "10 pm"
            to: "6 am"
            cause_has: person
            action: critical_notify
      998:
        rules:
          - time_format: "%I:%M %p"
            from: "5 pm"
            to: "7 am"
            action: mute

It says for Monitor ID 999, don't send notifications between
9:30pm to 1am on Mon,Tue,Wed for any alarms that don't have "person" in it's cause
assuming you are using object detection. It also says from 3am - 6am for all days of the week,
don't send alarms if the alarm cause has "truck" in it. From 10pm - 6am, any alarm with
"person" in the cause will be escalated as a critical notification.

Rules are evaluated sequentially; the first matching rule wins.

For Monitor 998, don't send notifications from 5pm to 7am for all days of the week.
Note that you need to install ``Time::Piece`` in Perl.


4: Deciding what to do when a new event ends
-----------------------------------------------------
The sections above cover what happens when an event starts. The ES also supports similar functionality for when an event *ends*. The flow follows the same structure as :ref:`when_event_starts` with the following differences:

* The hook, if enabled is defined by ``event_end_hook`` inside ``zmeventnotification.yml``
* The default end script, ``/var/lib/zmeventnotification/bin/zm_event_end.sh``, is a pass-through that returns ``0``. All image recognition happens at event start. You can modify it to perform any custom actions you need
* Sending notification rules are the same as the start section, except that ``event_end_notify_on_hook_success`` and ``event_end_notify_on_hook_fail`` are used for channel rules in ``zmeventnotification.yml``
* When the event ends, the ES will check the ZM DB to see if the detection text it wrote during start still exists. It may have been overwritten if ZM detect more motion after the detection. As of today, ZM keeps its notes in memory and doesn't know some other entity has updated the notes and overwrites it.
* At this stage, the fork that was started when the event started exits

User triggers after event_start and event_end
----------------------------------------------
Starting with version ``5.14``, two additional triggers are supported: ``event_start_hook_notify_userscript`` and ``event_end_hook_notify_userscript``. When specified, these scripts are invoked after the corresponding hook completes, allowing you to perform custom actions alongside the default object detection pipeline.

5: Actually sending the notification
-------------------------------------
Once all checks have passed, ``zmeventnotification.pl`` sends the notification. The protocol depends on the channel:

  - If it is FCM, the message is sent using the FCM API. By default, messages are proxied through
    a cloud function (``fcm_v1_url``). You can bypass the proxy and send directly to Google's FCM V1
    API by setting ``fcm_service_account_file`` to the path of a Google Service Account JSON file in
    the ``fcm`` section of ``zmeventnotification.yml``.
  - If it is MQTT, the message is sent using ``MQTT::Simple`` (a perl package)
  - If it is Websockets, the message is sent using ``Net::WebSocket`` (a perl package)
  - If it is a 3rd party push service, the message is sent via the script defined in ``api_push_script`` in ``zmeventnotification.yml``

5.1 Notification Payload
***************************
Irrespective of the protocol, the notification message typically consists of:

* Alarm text
* if you are using ``fcm`` or ``push_api``, you can also include an image of the alarm. That picture is typically a URL, specified in ``picture_url`` inside ``zmeventnotification.yml``
* If you are sending over MQTT, there is additional data, including a JSON structure that provides the detection text in an easily parseable structure (``detection`` field)
* There are some other fields included as well

5.1.1 Image inside the notification payload
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
The image is specified by the ``picture_url`` attribute. The URL format is: ``https://pliablepixels.duckdns.org:8889/zm/index.php?view=image&eid=EVENTID&fid=<FID>&width=600``

The ``<FID>`` portion supports several values:

* ``fid=BESTMATCH`` - this will replace the frameID with whichever frame objects were detected
* ``fid=objdetect``

Whatever value is finally used for ``<FID>`` is what we call the "anchor" frame.

.. note::

   Animations are a new concept and requires ZM 1.35+. Animations can be created around the time of alarm and sent to you as a live notification, so you see moving frames in your push message. You can create animations as MP4 or GIF files (or both). MP4 is more space efficient and animates approximately +-5 seconds around the anchor frame. GIF animation takes more space and animates approximately +-2 seconds around the anchor frame.


* ``fid=objdetect``

  - in ZM 1.34 and below this will extract the frame that has objects with borders around them (static image)
  - in ZM 1.35+ if you have opted to create a GIF animation, this will return the GIF animation of the event or the frame with borders around the objects (static image)

* ``fid=objdetect_gif``

  - only ZM 1.35+. Returns the GIF animation for the alarmed event if it exists

* ``fid=objdetect_mp4``

  - only ZM 1.35+. Returns the MP4 animation for the alarmed event if it exists


Controlling the Event Server
++++++++++++++++++++++++++++
There is both a static and dynamic way to control the ES.

- You can change parameters in ``zmeventnotification.yml``. This will however require you to restart the ES (``sudo zmdc.pl restart  zmeventnotification.pl``). You can also change hook related parameters in ``objectconfig.yml`` and they will automatically take effect for the next detection (because the hook scripts restart with each invocation), if you are using local detections.

- For dynamic, programmatic changes without a restart, the ES provides a control interface. This is a websocket-based interface that requires authentication. Once authenticated, you can modify any ES configuration parameter at runtime. See :ref:`escontrol_interface` for details.

Keep in mind:

  - Admin overrides via the control interface take precedence over the config file.
  - Overrides are stored in ``/var/lib/zmeventnotification/misc/escontrol_interface.dat`` (encoded). If your config changes do not seem to take effect and you have the control interface enabled, check for this file and remove it to reset to config-file defaults.

.. _how-ml-works:

How Machine Learning Works
+++++++++++++++++++++++++++

.. note::

   This section applies to both Path 1 and Path 2. The ML pipeline is the same regardless of how ``zm_detect.py`` is invoked.

For a detailed configuration reference, see :doc:`hooks`. This section describes the high-level principles.

The entry point to the ML pipeline is ``/var/lib/zmeventnotification/bin/zm_detect.py``. It reads ``/etc/zm/objectconfig.yml`` and runs the configured detection types (object, face, ALPR, etc.). There are some important things to keep in mind:

* When the hooks are invoked, ZM has *just started* recording the event. Which means there are only limited frames to analyze. In fact, at times, if you see the detection scripts are not able to download frames, then it is possible they haven't yet been written to disk by ZM. This is a good situation to use the ``wait`` attribute in ``objectconfig.yml`` and wait for a few seconds before it tries to get frames.

.. sidebar:: Gotcha

    If you ever wonder why detection did not work when the ES invoked it, but worked just fine when you ran the detection manually, this may be why: during detection the snapshot was different from the final value.

* The detection scripts do not analyze all frames recorded so far. They analyze at most two frames, depending on your ``frame_id`` value in ``objectconfig.yml``. With ``frame_id=bestmatch``, those two frames are ``snapshot`` and ``alarm``.
* ``snapshot`` is the frame that has the highest score. It is very possible this frame changes *after* the detection is done, because it is entirely possible that another frame with a higher score is recorded by ZM as the event proceeds.
* There are various steps to detection:

  1. Match all the rules in ``objectconfig.yml`` (example type(s) of detection for that monitor, etc.)
  2. Do the actual detection
  3. Make sure the detections meet the rules in ``objectconfig.yml`` (example, it intersects  the polygon boundaries, category of detections, etc.)
  4. Of these step 2. can either be done locally or remotely, depending on how you set up ``ml_gateway``. Everything else is done locally. See  :ref:`this FAQ entry <local_remote_ml>` for more details.
