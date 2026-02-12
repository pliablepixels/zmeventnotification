Key Principles - Event Notification Server  and Hooks
=======================================================

Summary
+++++++++
This guide is meant to give you an idea of how the Event Notification Server (ES) works, how it invokes hooks and how notifications are finally sent out.

.. _from-detection-to-notification:

From Event Detection to Notification
+++++++++++++++++++++++++++++++++++++
1: How it starts
----------------------
The ES is a perl process (typically ``/usr/bin/zmeventnotification.pl``) that acts like just any other ZM daemon (there are many) that is started by ZoneMinder when it starts up. Specifically, the ES gets "auto-started" only if you have enabled ``OPT_USE_EVENT_NOTIFICATION`` in your ``Zoneminder->System`` menu options. Technically, ZM uses a 'control' process called ``zmdc.pl`` that starts a bunch of important daemons (see `here <https://github.com/ZoneMinder/zoneminder/blob/release-1.34/scripts/zmdc.pl.in#L93>`__ for a list of daemons) and keeps a tab on them. If any of them die, they get restarted.

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

The entire concept of hooks is to "influence" whether or not to actually send out a notification for a new event. If you are already using hooks, you are likely using the most popular hook that I wrote, which actually does object/person/face detection on the image(s) that constitute the event to make an intelligent decision on whether you really want to be notified of the event. If you recall, the initial reason why I wrote the ES was to send "push notifications" to zmNinja. You'd be inundated if you got a push for *every* new event ZM reports. 

So when you have hooks enabled, the script that is invoked when a new event is detected by the ES is defined in ``event_start_hook`` inside ``zmeventnotification.yml``. I am going to assume you did not change that hook script, because the default script does the fancy image recognition that lot of people love. That script, which is usually ``/var/lib/zmeventnotification/bin/zm_event_start.sh`` does the following:

* It invokes `/var/lib/zmeventnotification/bin/zm_detect.py` that is the actual script that does the fancy detection and waits for a response. If this python file detects objects that meet the criteria in ``/etc/zm/objectconfig.yml`` it will return an exit code of ``0`` (success) with a text string describing the objects, else it will return an exit code of ``1`` (fail) 
* It passes on the output and the return value of the script back to the ES

* At this stage, if hooks were used and it returned a success (``0``) and ``use_hook_description=yes`` in ``zmeventnotification.yml`` then the detection text gets written to the ZM DB for the event

The ES has no idea what the event start script does. All it cares about is the "return value". If it returns ``0`` that means the hook "succeeded" and if it returned any non ``0`` value, the script failed. This return code makes a difference on whether the final notification is sent out or not, as you will see later.

3.2: Will the ES send a notification?
********************************************
So at this stage, we have a new event and we need to decide if the ES will send out a notification. The following factors matter:

* If you had hooks enabled, and the hook succeeded (i.e. return value of ``0``), then the notification *may* be sent to the channels you specified in ``event_start_notify_on_hook_success``. 
* If the hook failed (i.e. return value of non zero, then the notification *may* be sent to the channels specified in ``event_start_notify_on_hook_fail``)

.. sidebar:: Summary of rules:

  * if hooks are used, needs to return 0 as exit status
  * Then, if you use dynamic controls (``use_escontrol_interface=yes``), those commands will be checked
  * Then, if you have a rule file (ES 6.0+), rules will have to allow it
  * Then, channel must be in the notify_on_xxx attributes
  * Then, if FCM, monitor must be in tokens.txt for that device
  * Then, if FCM, delay must be > delay specified in tokens.txt

3.2.1: Wait what is a channel?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
At a high level, there are 4 types of clients that are interested in receiving notifications:

* zmNinja: the mobile app that uses Firebase Cloud Messaging (FCM) to get push notifications. This is the "fcm" channel
* Any websocket client: This included zmNinja desktop and any other custom client you may have written to get notifications via web sockets. This is the "web" channel
* receivers that use MQTT. This is the "mqtt" channel.
* Any 3rd party push solution which you may be using to deliver push notifications. A popular one is "pushover" for which I provide a `plugin <https://github.com/pliablepixels/zmeventnotification/blob/master/pushapi_plugins/pushapi_pushover.py>`__. This is the "api" channel.

So, for example:

::

  event_start_notify_on_hook_success = all
  event_start_notify_on_hook_fail = api,web

This will mean when a new event occurs, everyone may get a notification if the hook succeeded but if the hook fails, only API  and Web channels will be notified, not FCM. This means zmNinja mobile app will not be notified. Obviously, if you don't want to get deluged with constant notifications on your phone, don't put ``fcm`` as a channel in ``event_Start_notify_on_hook_fail``.

3.2.2: The tokens.txt file
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Why do I say above that you *may* get a notification?

You'd think if the channels conditions are met and the hook conditions are met, then those channels *will* get a notification. Not quite. 

.. note::

    ``tokens.txt`` is another "configuration" file that impacts the decision process for sending a notification out. This only applies to the "fcm" channel (i.e. mobile push notification) and is not documented very much. So read this section well.

There is another file, ``/var/lib/zmeventnotification/push/tokens.txt`` that dictates if events are finally sent or not. This pre-dates all the hook stuff and was created really so that zmNinja could receive notifications from the ES.

This file is actually created  when zmNinja sets up push notification. Here is how it works:

* When zmNinja runs and you enable push notifications, it asks either Apple or Google for a unique token to receive notifications via their push servers. 
* This token is then sent to the ES via websockets. The ES stores this token in the ``tokens.txt`` file and every time it restarts, it reloads these tokens so it knows these clients expect notifications over FCM. **So if your zmNinja app cannot connect to the ES for the first time, the token will never be saved and the ES will never be able to send notifications to your zmNinja app**.

However, there are other things the ``tokens.txt`` file saves. Let's take a look:

Here is a typical tokens.txt entry: (This used to be a cryptic colon separated file, now migrated to JSON starting ES 6.0.1)


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
* intlist = interval in seconds before the next notification is sent. If we look at the first row, it says monitor 1 events will be sent as soon as they occur, however for monitor 2 and 5, notifications will only be sent if the previous notification for that monitor was *at least* 120 seconds before (2 mins). How is this set? You actually set it via zmNinja->Settings->Event Server Settings
* platform the device type (we need this to create a push notification message correctly)
* pushstate = Finally, this tells us if push is enabled or disabled for this device. There are two ways to disable - you can disable push notifications for zmNinja on your device, or you can simply uncheck "use event server" in zmNinja. This is for the latter case. If you uncheck "use event server", we need to be able to tell the ES that even though it has a token on file, it should not send notifications.
* appversion = version of zmNinja (so we know if FCMv1 is supported). For any zmNinja version prior to ``1.6.000`` this is set to ``unknown``.

.. important::

    It is important to note here that if zmNinja is not able to connect to the ES at least for the first time, you will never receive notifications. Check your ``tokens.txt`` file to make sure you have entries. If you don't that means zmNinja can't reach your ES.

You will also note that ``tokens.txt`` does not contain any other entries besides android and iOS. zmNinja desktop does not feature here, for example. That is because ``tokens.txt`` only exists to store FCM registrations. zmNinja desktop only receives notifications when it is running and via websockets, so that connection is established when the desktop app runs. FCM tokens on the other hand need to be remembered, because zmNinja may not be running in your phone and the ES still needs to send out notifications to all tokens (devices) that might have previously registered.


3.2.4: Wait, what on earth is a "Rules file"?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
The ES uses a ``es_rules.yml`` that gets installed in ``/etc/zm/``.
It is a YAML file that supports various rules. As of today, it only supports
the "mute" action. You can specify "mute" time ranges where the ES will not send out notifications.

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
      998:
        rules:
          - time_format: "%I:%M %p"
            from: "5 pm"
            to: "7 am"
            action: mute

It says for Monitor ID 999, don't send notifications between
9:30pm to 1am on Mon,Tue,Wed for any alarms that don't have "person" in it's cause
assuming you are using object detection. It also says from 3am - 6am for all days of the week,
don't send alarms if the alarm cause has "truck" in it.

For Monitor 998, don't send notifications from 5pm to 7am for all days of the week.
Note that you need to install ``Time::Piece`` in Perl.


4: Deciding what to do when a new event ends
-----------------------------------------------------
Everything above was when an event first starts. The ES also allows similar functions for when an event *ends*. It pretty much follows the flow defined in  :ref:`when_event_starts` with the following differences:

* The hook, if enabled is defined by ``event_end_hook`` inside ``zmeventnotification.yml``
* The default end script which is usually ``/var/lib/zmeventnotification/bin/zm_event_end.sh`` doesn't do anything. All the image recognition happens at the event start. Feel free to modify it to do anything you want. As of now, its just a "pass through" that returns a success (``0``) exit code
* Sending notification rules are the same as the start section, except that ``event_end_notify_on_hook_success`` and ``event_end_notify_on_hook_fail`` are used for channel rules in ``zmeventnotification.yml``
* When the event ends, the ES will check the ZM DB to see if the detection text it wrote during start still exists. It may have been overwritten if ZM detect more motion after the detection. As of today, ZM keeps its notes in memory and doesn't know some other entity has updated the notes and overwrites it. 
* At this stage, the fork that was started when the event started exits

User triggers after event_start and event_end
----------------------------------------------
Starting version ``5.14`` I also support two new triggers called ``event_start_hook_notify_userscript`` and ``event_end_hook_notify_userscript``. If specified, they are invoked so that the user can perform any housekeeping jobs that are necessary. These triggers are useful if you want to use the default object detection scripts *as well* as doing your own things after it.
   
5: Actually sending the notification
-------------------------------------
So let's assume that all checks have passed above and we are now about to send the notification. What is actually sent?

* ``zmeventnotification.pl`` finally sends out the message. The exact protocol depends on the channel:

  - If it is FCM, the message is sent using FCM API
  - If it is MQTT, we use  use ``MQTT::Simple`` (a perl package) to send the message
  - If it is Websockets, we use ``Net::WebSocket``, another perl package to send the message
  - If it is a 3rd party push service, then we rely on ``api_push_script`` in `zmeventnotification.yml`` to send the message.

5.1 Notification Payload
***************************
Irrespective of the protocol, the notification message typically consists of:

* Alarm text
* if you are using ``fcm`` or ``push_api``, you can also include an image of the alarm. That picture is typically a URL, specified in ``picture_url`` inside ``zmeventnotification.yml``
* If you are sending over MQTT, there is additional data, including a JSON structure that provides the detection text in an easily parseable structure (``detection`` field)
* There are some other fields included as well

5.1.1 Image inside the notification payload
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
We mentioned above that the image is contained in the ``picture_url`` attribute. Let's dive into that a bit. The format of the picture url is: ``https://pliablepixels.duckdns.org:8889/zm/index.php?view=image&eid=EVENTID&fid=<FID>&width=600``

There are interesting things you can do with the ``<FID>`` part.

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

- So obviously, there was a need to allow for programmatic change to the ES and dynamically.

That is what the "ES control interface" does. It is a websocket based interface that requires authentication. Once you authenticate, you can change any ES parameter that is in the config. Read more about it: :ref:`escontrol_interface`. 

Just remember:
  
  - admin override via this channel takes precedence over config file
  - admin overrides are stored in a different file ``/var/lib/zmeventnotification/misc/escontrol_interface.dat`` and are encoded. So if you are confused why your config changes are not working, and you have enabled this control interface, check for that dat file and remove it to start from scratch.

How Machine Learning works
+++++++++++++++++++++++++++

There is a dedicated document that describes how hooks work at :doc:`hooks`. Refer to that for details. This section will describe high level principles.

As described earlier, the entry point to all the machine learning goodness starts with ``/var/lib/zmeventnotitication/bin/zm_detect.py``. This file reads ``/etc/zm/objectconfig.yml`` and based on the many settings there goes about doing various forms of detection. There are some important things to remember:

* When the hooks are invoked, ZM has *just started* recording the event. Which means there are only limited frames to analyze. In fact, at times, if you see the detection scripts are not able to download frames, then it is possible they haven't yet been written to disk by ZM. This is a good situation to use the ``wait`` attribute in ``objectconfig.yml`` and wait for a few seconds before it tries to get frames. 

.. sidebar:: Gotcha

    If you ever wonder why detection did not work when the ES invoked it, but worked just fine when you ran the detection manually, this may be why: during detection the snapshot was different from the final value.

* The detection scripts DO NOT analyze all frames recorded so far. That would take too long (well, not if you have a powerful GPU). It only analyzes two frames at most, depending on your ``frame_id`` value in ``objectconfig.yml``.  Those two frames are ``snapshot`` and ``alarm``, assuming you set ``frame_id=bestmatch``
* ``snapshot`` is the frame that has the highest score. It is very possible this frame changes *after* the detection is done, because it is entirely possible that another frame with a higher score is recorded by ZM as the event proceeds. 
* There are various steps to detection:

  1. Match all the rules in ``objectconfig.yml`` (example type(s) of detection for that monitor, etc.) 
  2. Do the actual detection
  3. Make sure the detections meet the rules in ``objectconfig.yml`` (example, it intersects  the polygon boundaries, category of detections, etc.)
  4. Of these step 2. can either be done locally or remotely, depending on how you set up ``ml_gateway``. Everything else is done locally. See  :ref:`this FAQ entry <local_remote_ml>` for more details.

