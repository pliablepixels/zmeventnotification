Path 2: Full Event Server
=========================

The ES is a Perl daemon that monitors ZoneMinder's shared memory for new events,
invokes the ML hooks, and handles push notifications, WebSockets, MQTT, rules, and more.

If you only want ML detection without the ES, see :doc:`install_path1` instead.

Step 1: Install ML dependencies
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Follow **Steps 1 and 2** from :doc:`install_path1` to install OpenCV and pyzm.
These are needed for the ML hooks that the ES invokes.

Step 2: Install the WebSocket Perl module
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The installer handles most Perl dependencies via apt, but ``Net::WebSocket::Server``
must be installed separately:

.. code:: bash

   sudo apt install make libprotocol-websocket-perl
   sudo cpanm Net::WebSocket::Server

   # If cpanm is not installed:
   sudo apt install cpanminus

Step 3: Run the installer
~~~~~~~~~~~~~~~~~~~~~~~~~

.. code:: bash

   git clone https://github.com/pliablepixels/zmeventnotification
   cd zmeventnotification
   sudo -H ./install.sh    # say Yes to everything

This installs the ES, hooks, ML models, Perl dependencies (via apt), config files,
and sets up the directory structure.

.. note::

   By default ``install.sh`` places the ES script in ``/usr/bin``. If your ZM install
   uses a different path (e.g. ``/usr/local/bin``), edit the ``TARGET_BIN`` variable
   in ``install.sh`` before running it.

Step 4: Set up SSL
~~~~~~~~~~~~~~~~~~

The ES runs in secure (WSS) mode by default and **requires SSL certificates**.
If you already use SSL for ZoneMinder, just point the ES to those same certs.

**If you don't have certificates yet** — generate self-signed ones:

.. code:: bash

   sudo openssl req -x509 -nodes -days 4096 -newkey rsa:2048 \
       -keyout /etc/zm/apache2/ssl/zoneminder.key \
       -out /etc/zm/apache2/ssl/zoneminder.crt

.. important::

   Set the **Common Name** to the hostname or IP you'll use to access the server
   (e.g. ``myserver.ddns.net``).

For zmNinja picture messaging, you need a real certificate (e.g. `LetsEncrypt <https://letsencrypt.org>`__) —
self-signed won't work for that.

Step 5: Configure
~~~~~~~~~~~~~~~~~

The installer creates these config files (all YAML):

- ``/etc/zm/zmeventnotification.yml`` — ES settings
- ``/etc/zm/objectconfig.yml`` — ML detection settings
- ``/etc/zm/secrets.yml`` — credentials (ZM portal, SSL paths)
- ``/etc/zm/es_rules.yml`` — notification rules

**At minimum**, edit ``/etc/zm/secrets.yml``:

::

    secrets:
      ZM_USER: your_username
      ZM_PASSWORD: your_password
      ZM_PORTAL: "https://your-server/zm"
      ZM_API_PORTAL: "https://your-server/zm/api"
      ES_CERT_FILE: /etc/zm/apache2/ssl/zoneminder.crt
      ES_KEY_FILE: /etc/zm/apache2/ssl/zoneminder.key

Then update the SSL paths in ``zmeventnotification.yml``:

::

    ssl:
      cert: /etc/zm/apache2/ssl/zoneminder.crt
      key: /etc/zm/apache2/ssl/zoneminder.key

If you are **not** using ML hooks, set ``use_hooks: "no"`` in the ``customize`` section
of ``zmeventnotification.yml``.

If you are behind a firewall, open port ``9000`` (TCP, bi-directional).

Step 6: Test manually
~~~~~~~~~~~~~~~~~~~~~

First, verify you have the right versions installed:

.. code:: bash

   sudo -u www-data /var/lib/zmeventnotification/bin/zm_detect.py --version

You should see **app:7.0.0** (or above) and **pyzm:2.0.0** (or above).
If either version is lower, update the corresponding package before continuing.

Then test the ES manually before enabling daemon mode:

.. code:: bash

   sudo -u www-data /usr/bin/zmeventnotification.pl --debug

This starts the ES in the foreground with debug output. Check that it loads without
errors, then Ctrl+C to stop.

The ``-u www-data`` is important — the ES must run as the same user as your web server
(may be ``apache`` on some systems).

Step 7: Enable auto-start
~~~~~~~~~~~~~~~~~~~~~~~~~~

In the ZoneMinder web interface, go to **Options -> Systems** and enable
``OPT_USE_EVENTNOTIFICATION``. The ES will now start automatically with ZoneMinder.

Step 8: Set up ML hooks
~~~~~~~~~~~~~~~~~~~~~~~

Follow **Steps 4–6** from :doc:`install_path1` to configure ``objectconfig.yml``
and test detection.

.. note::

   With the ES, you do **not** set ``EventStartCommand`` in ZoneMinder — the ES handles
   event detection itself. Don't configure both or you'll run detection twice.

Logging
~~~~~~~

For quick debugging, add ``--debug`` when running manually. For proper persistent logging,
see :ref:`es-hooks-logging`.

Optional: MQTT
~~~~~~~~~~~~~~

If you want MQTT notifications:

.. code:: bash

   sudo cpanm Net::MQTT::Simple

MQTT 3.1.1 or newer is required.
