Testing
========

The zmeventnotification project has two tiers of tests: unit tests that
need no special hardware, and end-to-end (e2e) tests that run real ML
models through the full config-to-detection chain.

None of the tests require a running ZoneMinder instance.


Running all tests
------------------

.. code-block:: bash

   cd zmeventnotification

   # Perl tests
   prove -I t/lib -I . -r t/

   # Python tests (unit + e2e)
   cd hook && python3 -m pytest tests/ -v && cd ..


Unit / integration tests
-------------------------

These tests mock pyzm and use no real models.  They run anywhere:

.. code-block:: bash

   # Perl
   prove -I t/lib -I . -r t/

   # Python
   pip install pytest pyyaml
   cd hook && python3 -m pytest tests/ -m "not e2e" -v


End-to-end tests
-----------------

The ``hook/tests/test_e2e/`` directory contains 26 tests that exercise
the full objectconfig YAML → pyzm detection → output chain using real
YOLO models and a real test image (``bird.jpg``, included in the repo).

These tests use **real pyzm** (installed as a system library, not
mocked) and call the same functions that ``zm_detect.py`` uses:
``process_config()`` → secret substitution → ``Detector.from_dict()`` →
``detector.detect()`` → ``format_detection_output()``.

**Prerequisites:**

- pyzm installed (``pip install pyzm`` or from source)
- ML models at ``/var/lib/zmeventnotification/models/``
  (at least one YOLO model, e.g. ``yolov4/`` or ``ultralytics/``)
- Python packages: ``opencv-python``, ``numpy``, ``shapely``

**Run all e2e tests:**

.. code-block:: bash

   cd hook
   python3 -m pytest tests/test_e2e/ -v

**Run a single test file:**

.. code-block:: bash

   python3 -m pytest tests/test_e2e/test_pattern_config.py -v


Test file reference
--------------------

.. list-table::
   :header-rows: 1
   :widths: 35 10 55

   * - File
     - Tests
     - What it covers
   * - ``test_config_to_detect.py``
     - 5
     - Full config→detect→output chain, output format, show_percent,
       image in matched_data, ``${base_data_path}`` substitution
   * - ``test_secret_chain.py``
     - 2
     - ``!TOKEN`` secret substitution in model paths and general config fields
   * - ``test_pattern_config.py``
     - 3
     - Restrictive pattern (no matches), broad pattern (matches),
       specific label-only pattern
   * - ``test_confidence_config.py``
     - 3
     - High threshold filters, low threshold keeps, low vs high comparison
   * - ``test_disabled_config.py``
     - 2
     - ``enabled=no`` produces nothing, mixed enabled/disabled
   * - ``test_monitor_config.py``
     - 3
     - Per-monitor ml_sequence override, zone parsing,
       per-monitor config key override (show_percent)
   * - ``test_multi_model_config.py``
     - 2
     - UNION strategy (both models), FIRST strategy (first model only)
   * - ``test_zone_config.py``
     - 3
     - Full-image zone keeps detections, tiny zone filters all,
       zone with restrictive pattern
   * - ``test_format_chain.py``
     - 3
     - JSON roundtrip validity, label-confidence correlation,
       bounding box coordinates valid


Test dependencies
------------------

.. list-table::
   :header-rows: 1
   :widths: 20 80

   * - Tier
     - Dependencies
   * - Perl
     - ``Test::More``, ``YAML::XS``, ``JSON``, ``Time::Piece``
   * - Python (unit)
     - ``pytest``, ``pyyaml``
   * - Python (e2e)
     - all of the above plus ``pyzm``, ``opencv-python``, ``numpy``, ``shapely``


Pytest markers
---------------

.. list-table::
   :header-rows: 1
   :widths: 20 80

   * - Marker
     - Description
   * - ``e2e``
     - End-to-end tests requiring real pyzm, models, and images on disk
