Installation
============

There are two ways to use ML-powered object detection with ZoneMinder:

**Path 1: Detection only (no ES)** — Wire ``zm_detect.py`` directly to ZoneMinder
using ``EventStartCommand`` (requires ZM 1.38.1+). ZM calls the detection script
automatically when an event starts. Detection results are written to the event notes
and saved as ``objdetect.jpg`` / ``objects.json`` in the event folder.

*You get:* object/face/ALPR detection, annotated images, detection notes in ZM, local
or remote ML (via ``pyzm.serve``).

*You don't get:* push notifications (FCM), WebSocket notifications, MQTT publishing,
notification rules/muting, zmNg/zmNinja push, monitor-level notification filtering, or
the ES control interface.

**Path 2: Full Event Server** — Install and run the Event Notification Server alongside
ZoneMinder. The ES detects new events via shared memory, invokes the ML hooks, and
handles push notifications, WebSockets, MQTT, rules, and more.

*You get:* everything in Path 1, plus push notifications (iOS/Android via FCM), WebSocket
notifications, MQTT support, notification rules (time-based muting), zmNg/zmNinja integration,
the ES control interface, and per-device monitor filtering.

If you only need detection results written to your ZM events, Path 1 is simpler to set up.
If you need real-time notifications on your phone or other clients, you need Path 2.

.. toctree::

   install_path1
   install_path2
