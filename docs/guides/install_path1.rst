Path 1: Detection Only (no ES)
==============================

Use ZoneMinder's ``EventStartCommand`` to run ML detection directly — no Event Server needed.
Requires **ZM 1.38.1 or above**.

If you also want push notifications, WebSockets, or MQTT, see :doc:`install_path2`.

.. note::

   On newer Linux distros (Ubuntu 23.04+, Debian 12+, etc.) you may need to add
   ``--break-system-packages`` to ``pip3 install`` commands below, or use a virtual environment.

Step 1: Install OpenCV
~~~~~~~~~~~~~~~~~~~~~~

The install script does **not** install OpenCV for you, because you may want GPU support
or a specific version.

.. _opencv_install:

**Quick install (no GPU):**

.. code:: bash

   # Add --break-system-packages if your distro requires it
   sudo -H pip3 install opencv-contrib-python

**For GPU support**, compile from source with CUDA enabled. See the
`official OpenCV build guide <https://docs.opencv.org/master/d7/d9f/tutorial_linux_install.html>`__.
Here is an `example gist <https://gist.github.com/pliablepixels/73d61e28060c8d418f9fcfb1e912e425>`__
with instructions for compiling OpenCV from source on Ubuntu 24 that worked for me
(not authoritative — adapt as needed for your setup).

.. important::

   The default YOLOv26 model requires **OpenCV 4.13+**.
   Verify it works: ``python3 -c "import cv2; print(cv2.__version__)"``

.. _opencv_seg_fault:

Step 2: Install pyzm
~~~~~~~~~~~~~~~~~~~~~

.. code:: bash

   # Add --break-system-packages if your distro requires it
   sudo -H pip3 install pyzm

.. note::

   This installs the core pyzm library only. If you also want to run the
   remote ML detection server (``pyzm.serve``) on this same machine, install
   with the ``serve`` extra instead: ``sudo -H pip3 install pyzm[serve]``.
   This pulls in the additional dependencies (FastAPI, uvicorn, etc.) needed
   for the server. See :ref:`remote_ml_config` for details.

Step 3: Run the installer
~~~~~~~~~~~~~~~~~~~~~~~~~

.. code:: bash

   git clone https://github.com/pliablepixels/zmeventnotification
   cd zmeventnotification
   sudo -H ./install.sh    # say No to ES, Yes to hooks, Yes to hook config

Or, to run non-interactively:

.. code:: bash

   sudo -H ./install.sh --no-install-es --install-hook --install-hook-config --no-interactive

This handles everything else: downloads ML models (YOLOv4, YOLOv26 by default),
installs the hook scripts and Python packages, creates the directory structure,
and installs the config files.

.. _install-specific-models:

**Model flags** — to control which models are downloaded, pass environment variables:

.. code:: bash

   # Example: only YOLOv26, skip YOLOv4
   sudo -H INSTALL_YOLOV4=no INSTALL_TINYYOLOV4=no ./install.sh

Available flags (default in parentheses): ``INSTALL_YOLOV26`` (yes), ``INSTALL_YOLOV4`` (yes),
``INSTALL_TINYYOLOV4`` (yes), ``INSTALL_YOLOV3`` (no), ``INSTALL_TINYYOLOV3`` (no),
``INSTALL_CORAL_EDGETPU`` (no).

Step 4: Configure
~~~~~~~~~~~~~~~~~

Edit ``/etc/zm/objectconfig.yml`` — at minimum, fill in the ``general`` section with your
ZM portal URL, username, and password (or point them to ``secrets.yml``).

Step 5: Wire up ZoneMinder
~~~~~~~~~~~~~~~~~~~~~~~~~~~

For each monitor, go to **Config -> Recording** and set:

**Event Start Command**::

   /var/lib/zmeventnotification/bin/zm_detect.py -c /etc/zm/objectconfig.yml -e %EID% -m %MID% -r "%EC%" -n --pyzm-debug

Step 6: Test manually
~~~~~~~~~~~~~~~~~~~~~

First, verify you have the right versions installed:

.. code:: bash

   sudo -u www-data /var/lib/zmeventnotification/bin/zm_detect.py --version

You should see **app:7.0.0** (or above) and **pyzm:2.0.0** (or above).
If either version is lower, update the corresponding package before continuing.

Then test detection:

.. code:: bash

   # Test with a real ZM event
   sudo -u www-data /var/lib/zmeventnotification/bin/zm_detect.py \
       --config /etc/zm/objectconfig.yml --eventid <eid> --monitorid <mid> --debug

   # Or test with a local image (no ZM event needed)
   wget https://upload.wikimedia.org/wikipedia/commons/c/c4/Anna%27s_hummingbird.jpg -O /tmp/bird.jpg
   sudo -u www-data /var/lib/zmeventnotification/bin/zm_detect.py \
       --config /etc/zm/objectconfig.yml --file /tmp/bird.jpg --debug

Optional: Face recognition
~~~~~~~~~~~~~~~~~~~~~~~~~~

Only needed if you want to recognize *who* a face belongs to (not just detect faces):

.. code:: bash

   sudo apt-get install libopenblas-dev liblapack-dev libblas-dev
   # Add --break-system-packages if your distro requires it
   sudo -H pip3 install face_recognition

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

Troubleshooting
~~~~~~~~~~~~~~~

If something isn't working, see :doc:`hooks_faq` for debugging steps and common issues.
