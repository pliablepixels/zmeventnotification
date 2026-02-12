
Note
-----
This is a newer version of ES (7.x) that I'm redoing for zmNg support and better features.
Read about what is [different](CHANGES.md). 

What
----
The Event Notification Server sits along with ZoneMinder and offers real time notifications, support for push notifications as well as Machine Learning powered recognition.
As of today, it supports:
* detection of 80 types of objects (persons, cars, etc.) 
* face recognition
* deep license plate recognition

Getting Started (Development)
-----------------------------

ES 7.0 is in development stage at the moment, expect breakages. You may also need to manually fix some configurations after installations. The `install.sh` script attempts to migrate automatically but you should check. Given it is in development stage, it is not yet merged into mainstream ZM repos. If you find issues, please post them to this repo, and NOT ZM repos.

Both this repo and the [updated pyzm](https://github.com/pliablepixels/pyzm) library are needed. `pyzm` provides the ZoneMinder Python API, ML detection pipeline, and helper utilities that the hooks depend on.

### 1. Clone both repos

```bash
git clone https://github.com/pliablepixels/zmeventnotification.git
git clone https://github.com/pliablepixels/pyzm.git
```

### 2. Install pyzm

```bash
# do this from the directory you cloned pyzm into, don't change into pyzm/
sudo -H pip install pyzm/ --break-system-packages
```

### 3. Install the Event Server and hook helpers

```bash
cd zmeventnotification
sudo -H ./install.sh
cd ..
```

The installer handles Perl dependencies, hook helper setup, config file placement, model downloads, and automatic migration from older `.ini` configs to YAML.

Testing (Development)
----------------------
### 1. Run the test suites

Tests do **not** require a running ZoneMinder installation.

```bash
cd zmeventnotification

# Perl tests
prove -I t/lib -I . -r t/

# Python tests
pip install pytest pyyaml
cd hook && python3 -m pytest tests/ -v && cd ..

# Both in one shot
prove -I t/lib -I . -r t/ && (cd hook && python3 -m pytest tests/ -v)
```

### 2. Test Dependencies

- **Perl**: `Test::More`, `YAML::XS`, `JSON`, `Time::Piece` (typically included with Perl)
- **Python**: `pytest`, `pyyaml`

Running the Event Server
------------------------

```bash
sudo -u www-data ./zmeventnotification.pl --config /etc/zm/zmeventnotification.yml
```

Refer to the full [installation guide](https://zmeventnotificationv7.readthedocs.io/en/latest/guides/install.html) for production setup.

Requirements
-------------
- Python 3.6 or above

Screenshots
------------

Click each image for larger versions. Some of these images are from other users who have granted permission for use
###### (permissions received from: Rockedge/ZM Slack channel/Mar 15, 2019)

<img src="https://github.com/pliablepixels/zmeventnotification/blob/master/screenshots/person_face.jpg" width="300px" /> <img src="https://github.com/pliablepixels/zmeventnotification/blob/master/screenshots/delivery.jpg" width="300px" /> <img src="https://github.com/pliablepixels/zmeventnotification/blob/master/screenshots/car.jpg" width="300px" /> <img src="https://github.com/pliablepixels/zmeventnotification/blob/master/screenshots/alpr.jpg" width="300px" />
