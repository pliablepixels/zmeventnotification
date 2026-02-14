Installation
============

There are two ways to use ML-powered object detection with ZoneMinder:

.. topic:: Path 1: Detection only (no ES)

   Wire ``zm_detect.py`` directly to ZoneMinder using ``EventStartCommand``
   (requires ZM 1.38.1+). ZM calls the detection script automatically when
   an event starts. No daemon needed — simpler to set up.
   See :doc:`install_path1` for setup instructions.

.. topic:: Path 2: Full Event Server

   Install and run the Event Notification Server alongside ZoneMinder. The ES
   detects new events via shared memory, invokes the ML hooks, and handles
   push notifications, WebSockets, MQTT, rules, and more.
   See :doc:`install_path2` for setup instructions.

.. list-table:: Feature comparison
   :header-rows: 1
   :widths: 55 15 15

   * - Feature
     - Path 1
     - Path 2
   * - Object / face / ALPR detection
     - |yes|
     - |yes|
   * - Annotated images (``objdetect.jpg``)
     - |yes|
     - |yes|
   * - Detection notes written to ZM events
     - |yes|
     - |yes|
   * - Detection metadata (``objects.json``)
     - |yes|
     - |yes|
   * - Local or remote ML (via ``pyzm.serve``)
     - |yes|
     - |yes|
   * - Push notifications (iOS/Android via FCM)
     - |no|
     - |yes|
   * - WebSocket notifications
     - |no|
     - |yes|
   * - MQTT publishing
     - |no|
     - |yes|
   * - Notification rules / time-based muting
     - |no|
     - |yes|
   * - zmNg/zmNinja integration
     - |no|
     - |yes|
   * - Per-device monitor filtering (``tokens.txt``)
     - |no|
     - |yes|
   * - ES control interface (dynamic config)
     - |no|
     - |yes|

.. |yes| unicode:: U+2714 .. heavy checkmark
.. |no| unicode:: U+2014 .. em dash

If you only need detection results written to your ZM events, Path 1 is simpler to set up.
If you need real-time notifications on your phone or other clients, you need Path 2.

.. toctree::

   install_path1
   install_path2
