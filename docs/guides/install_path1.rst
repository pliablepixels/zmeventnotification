Path 1: Detection Only (no ES)
==============================

Use ZoneMinder's ``EventStartCommand`` to run ML detection directly — no Event Server needed.
Requires **ZM 1.38.1 or above**.

If you also want push notifications, WebSockets, or MQTT, see :doc:`install_path2`.

.. important::

   The installer now creates a **shared Python virtual environment** at
   ``/opt/zoneminder/venv`` instead of installing globally with
   ``pip install --break-system-packages``.

   Why the change:

   - Modern Linux distributions (Debian 12+, Ubuntu 23.04+, Fedora 38+)
     mark the system Python as *externally managed* (PEP 668) and actively
     block global pip installs.
   - ``--break-system-packages`` bypasses that protection but can break
     OS tools that depend on the system Python.
   - Multiple ZoneMinder components (pyzm, hook helpers) need to share a
     single Python environment — a dedicated venv gives them isolation from
     the OS while still sharing packages with each other.

Step 1: Run the installer
~~~~~~~~~~~~~~~~~~~~~~~~~

.. code:: bash

   git clone https://github.com/pliablepixels/zmeventnotification
   cd zmeventnotification
   sudo -H ./install.sh    # say No to ES, Yes to hooks, Yes to hook config

Or, to run non-interactively:

.. code:: bash

   sudo -H ./install.sh --no-install-es --install-hook --install-hook-config --no-interactive

This handles everything:

- Creates a Python virtual environment at ``/opt/zoneminder/venv``
  (customizable with ``--venv-path``).
- Installs **pyzm** and the **hook helpers** into the venv.
- Downloads ML models (YOLOv4, YOLOv11, YOLOv26 by default).
- Installs hook scripts, creates the directory structure, and installs
  config files.

Both pyzm and the hook helpers live in the venv, keeping your system
Python clean.

.. note::

   The installer pulls in **core pyzm** automatically. If you need additional
   pyzm extras (remote ML server, training UI, etc.) or want to install a
   local development version of pyzm, see the
   `pyzm installation guide <https://pyzmv2.readthedocs.io/en/latest/guide/installation.html>`__.

To use a custom venv path:

.. code:: bash

   sudo -H ./install.sh --venv-path /usr/local/zm/venv

.. _install-specific-models:

**Model flags** — to control which models are downloaded, pass environment variables:

.. code:: bash

   # Example: only YOLOv26, skip YOLOv4
   sudo -H INSTALL_YOLOV4=no INSTALL_TINYYOLOV4=no ./install.sh

Available flags (default in parentheses): ``INSTALL_YOLOV11`` (yes), ``INSTALL_YOLOV26`` (yes),
``INSTALL_YOLOV4`` (yes), ``INSTALL_TINYYOLOV4`` (yes), ``INSTALL_YOLOV3`` (no),
``INSTALL_TINYYOLOV3`` (no), ``INSTALL_CORAL_EDGETPU`` (no), ``INSTALL_BIRDNET`` (no).

You can also use the CLI flag ``--install-birdnet`` to install BirdNET audio detection.

.. _opencv_install:

Step 2: OpenCV
~~~~~~~~~~~~~~

The install script does **not** install OpenCV for you, because you may want
GPU support or a specific version.

.. important::

   ONNX models (YOLOv11, YOLOv26) require **OpenCV 4.13+**.

**Quick install (no GPU):**

.. code:: bash

   /opt/zoneminder/venv/bin/pip install opencv-contrib-python

**For GPU support**, compile from source with CUDA enabled. See the
`official OpenCV build guide <https://docs.opencv.org/master/d7/d9f/tutorial_linux_install.html>`__.
Here is an `example gist <https://gist.github.com/pliablepixels/73d61e28060c8d418f9fcfb1e912e425>`__
with instructions for compiling OpenCV from source on Ubuntu 24 that worked for me
(not authoritative — adapt as needed for your setup).

The venv is created with ``--system-site-packages``, so a system-wide OpenCV
built from source is automatically visible inside the venv.

.. note::

   If you already had OpenCV installed (from source or a system package)
   *before* running the installer, the install script registers an
   ``opencv-python`` compatibility shim so that pip does not overwrite your
   build. This is specifically needed because ``pyzm[train]`` depends on
   ``ultralytics``, which unconditionally pulls ``opencv-python`` from PyPI
   and will overwrite custom OpenCV builds (e.g. CUDA or Metal-accelerated).

   If your OpenCV is nevertheless replaced, you can restore it:

   .. code:: bash

      /opt/zoneminder/venv/bin/pip uninstall opencv-python opencv-python-headless
      # Rebuild / reinstall your custom OpenCV

Verify it works:

.. code:: bash

   /opt/zoneminder/venv/bin/python -c "import cv2; print(cv2.__version__)"

.. _opencv_seg_fault:

Step 3: Configure
~~~~~~~~~~~~~~~~~

Edit ``/etc/zm/objectconfig.yml`` — at minimum, fill in the ``general`` section with your
ZM portal URL, username, and password (or point them to ``secrets.yml``).

.. note::

   If you also want to run the remote ML detection server (``pyzm.serve``)
   on this same machine, install the ``serve`` extra:
   ``/opt/zoneminder/venv/bin/pip install "pyzm[serve]"``.
   See :ref:`remote_ml_config` for details.

Step 4: Wire up ZoneMinder
~~~~~~~~~~~~~~~~~~~~~~~~~~~

For each monitor, go to **Config -> Recording** and set:

**Event Start Command**::

   /var/lib/zmeventnotification/bin/zm_detect.py -e %EID% -m %MID% -r "%EC%" -n --pyzm-debug

``-c`` defaults to ``/etc/zm/objectconfig.yml``; pass it explicitly only if your config is elsewhere.

Step 5: Test manually
~~~~~~~~~~~~~~~~~~~~~

First, verify you have the right versions installed:

.. code:: bash

   sudo -u www-data /var/lib/zmeventnotification/bin/zm_detect.py --version

You should see **app:7.0.0** (or above) and **pyzm:2.0.0** (or above).
If either version is lower, update the corresponding package before continuing.

Then test detection (``--config`` defaults to ``/etc/zm/objectconfig.yml``):

.. code:: bash

   # Test with a real ZM event
   sudo -u www-data /var/lib/zmeventnotification/bin/zm_detect.py \
       --eventid <eid> --monitorid <mid> --debug

   # Or test with a local image (no ZM event needed)
   wget https://upload.wikimedia.org/wikipedia/commons/c/c4/Anna%27s_hummingbird.jpg -O /tmp/bird.jpg
   sudo -u www-data /var/lib/zmeventnotification/bin/zm_detect.py \
       --file /tmp/bird.jpg --debug

Optional: Face recognition
~~~~~~~~~~~~~~~~~~~~~~~~~~

Only needed if you want to recognize *who* a face belongs to (not just detect faces):

.. code:: bash

   sudo apt-get install libopenblas-dev liblapack-dev libblas-dev
   /opt/zoneminder/venv/bin/pip install face_recognition

Optional: Google Coral EdgeTPU
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Follow the `Coral setup guide <https://coral.ai/docs/accelerator/get-started/>`__ first,
then run the installer with:

.. code:: bash

   sudo -H INSTALL_CORAL_EDGETPU=yes ./install.sh

Make sure the web user has device access: ``sudo usermod -a -G plugdev www-data`` (reboot required).

.. warning::

   Google's official ``pycoral`` packages only support Python 3.9 and below. If you are
   running Python 3.10+, see `pycoral#149 <https://github.com/google-coral/pycoral/issues/149>`__
   for community workarounds.

Post-install diagnostics
~~~~~~~~~~~~~~~~~~~~~~~~

After installation, run the diagnostic tool to check your environment:

::

   sudo -u www-data python3 tools/install_doctor.py \
       --hook-config /etc/zm/objectconfig.yml \
       --es-config /etc/zm/zmeventnotification.yml \
       --web-owner www-data --web-group www-data \
       --base-data /var/lib/zmeventnotification

(Run from the zmeventnotification source directory.)
This checks GPU/CUDA availability, OpenCV version, model file paths, file permissions,
SSL certificates, MQTT/FCM Perl dependencies, and Python package versions. Fix any
issues it reports before proceeding. Note that ``install.sh`` runs this automatically
at the end of installation.

Troubleshooting
~~~~~~~~~~~~~~~

If something isn't working, see :doc:`hooks_faq` for debugging steps and common issues.
