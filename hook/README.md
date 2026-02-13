### What

Kung-fu machine learning goodness. 

This is an example of how you can use the `hook` feature of the notification server
to invoke a custom script on the event before it generates an alarm. 
I currently support object detection and face recognition. 

Please don't ask me questions on how to use them. Please read the comments and figure it out.

### Installation

Read the official docs [here](https://zmeventnotificationv7.readthedocs.io/en/latest/guides/hooks.html)

### Testing

**Unit tests** (no ML models or pyzm needed — pyzm is mocked):
```bash
pip install pytest pyyaml
python3 -m pytest tests/ -m "not e2e" -v
```

**End-to-end tests** (require real pyzm + YOLO models on disk):
```bash
# Requires: pyzm installed, models in /var/lib/zmeventnotification/models/
python3 -m pytest tests/test_e2e/ -v
```

**All tests:**
```bash
python3 -m pytest tests/ -v
```
