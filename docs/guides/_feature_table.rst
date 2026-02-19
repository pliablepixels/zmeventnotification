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
