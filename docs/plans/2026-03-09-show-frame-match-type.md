# Move frame-match-type display control from ES to hook

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the ES-side `keep_frame_match_type` setting with a hook-side `show_frame_match_type` setting in `objectconfig.yml`, and refactor `buildPictureUrl` to use `frame_id` from the JSON portion instead of parsing the `[a]`/`[s]` text prefix.

**Architecture:** The hook (`format_detection_output` in `utils.py`) currently always emits `[a]`/`[s]`/`[x]` prefixes. The ES (`stripFrameMatchType` in `Util.pm`) optionally strips them. We move the control to the hook so the prefix is only emitted when `show_frame_match_type: "yes"`. The ES's `buildPictureUrl` switches from parsing the text prefix to reading `frame_id` from the JSON portion (already present in the `--SPLIT--` payload). The ES-side `keep_frame_match_type` config, `stripFrameMatchType` function, and its constant are removed.

**Tech Stack:** Python (hook), Perl (ES), YAML config, RST docs

---

### Task 1: Add `show_frame_match_type` to hook config

**Files:**
- Modify: `hook/zmes_hook_helpers/common_params.py:103-108` (after `show_models`)
- Modify: `hook/objectconfig.example.yml:37` (after `show_percent`)

**Step 1: Write the failing test**

Add to `hook/tests/test_output_format.py`:

```python
def test_show_frame_match_type_no(self):
    data = _make_matched_data(['person'], frame_id='alarm')
    config = {'show_percent': 'no', 'show_models': 'no', 'show_frame_match_type': 'no'}
    output = format_detection_output(data, config)
    txt, _ = output.split('--SPLIT--', 1)
    assert not txt.startswith('[a]')
    assert txt == 'detected:person'

def test_show_frame_match_type_yes(self):
    data = _make_matched_data(['person'], frame_id='alarm')
    config = {'show_percent': 'no', 'show_models': 'no', 'show_frame_match_type': 'yes'}
    output = format_detection_output(data, config)
    txt, _ = output.split('--SPLIT--', 1)
    assert txt == '[a] detected:person'

def test_show_frame_match_type_default_yes(self):
    """When show_frame_match_type is not specified, prefix is included (backward compat)."""
    data = _make_matched_data(['person'], frame_id='alarm')
    config = {'show_percent': 'no', 'show_models': 'no'}
    output = format_detection_output(data, config)
    txt, _ = output.split('--SPLIT--', 1)
    assert txt.startswith('[a]')
```

**Step 2: Run tests to verify they fail**

Run: `cd /home/arjunrc/fiddle/zmeventnotification && python -m pytest hook/tests/test_output_format.py::TestFormatDetectionOutput::test_show_frame_match_type_no -v`
Expected: FAIL — `[a]` prefix is still present because `format_detection_output` doesn't check this config key yet.

**Step 3: Implement**

In `hook/zmes_hook_helpers/utils.py`, change `format_detection_output` (lines 52-59):

```python
    prefix = ''
    show_prefix = config.get('show_frame_match_type', 'yes')

    if show_prefix != 'no':
        if matched_data['frame_id'] == 'snapshot':
            prefix = '[s] '
        elif matched_data['frame_id'] == 'alarm':
            prefix = '[a] '
        else:
            prefix = '[x] '
```

In `hook/zmes_hook_helpers/common_params.py`, add after `show_models` entry (~line 108):

```python
        'show_frame_match_type': {
            'section': 'general',
            'default': 'yes',
            'type': 'string'
        },
```

In `hook/objectconfig.example.yml`, add after `show_percent: "yes"` (line 37):

```yaml
  # Show frame match type prefix in detection output:
  # [a] = alarm frame, [s] = snapshot frame, [x] = other
  # Useful for debugging which frame matched. Default: yes
  show_frame_match_type: "yes"
```

**Step 4: Run tests to verify they pass**

Run: `cd /home/arjunrc/fiddle/zmeventnotification && python -m pytest hook/tests/test_output_format.py -v`
Expected: ALL PASS (including existing tests, which don't set the key so get default "yes" behavior).

**Step 5: Commit**

```bash
git add hook/zmes_hook_helpers/utils.py hook/zmes_hook_helpers/common_params.py hook/objectconfig.example.yml hook/tests/test_output_format.py
git commit -m "feat(hook): add show_frame_match_type config to control [a]/[s]/[x] prefix

Refs #<issue>"
```

---

### Task 2: Refactor ES `buildPictureUrl` to use JSON `frame_id`

**Files:**
- Modify: `ZmEventNotification/Util.pm:142-174`
- Modify: `ZmEventNotification/HookProcessor.pm:35` (pass JSON to buildPictureUrl)
- Modify: `ZmEventNotification/FCM.pm:177` (pass JSON to buildPictureUrl)
- Modify: `t/02-util.t:77-101` (update buildPictureUrl tests)

**Step 1: Write the failing test**

Update `t/02-util.t` buildPictureUrl tests. Replace the `[a]`/`[s]` cause-based tests with `frame_id` parameter tests:

```perl
# ===== buildPictureUrl =====
{
    # Set up required config
    local $hooks_config{event_start_hook} = '/usr/bin/detect';
    local $hooks_config{enabled} = 1;
    local $notify_config{picture_url} = 'https://zm/index.php?view=image&eid=EVENTID&fid=BESTMATCH';
    local $notify_config{picture_portal_username} = 'user1';
    local $notify_config{picture_portal_password} = 'p@ss';

    my $url = buildPictureUrl(12345, 'detected:person', 0, 'test', 'alarm');
    like($url, qr/eid=12345/, 'buildPictureUrl: EVENTID replaced');
    like($url, qr/fid=alarm/, 'buildPictureUrl: BESTMATCH replaced with alarm for frame_id=alarm');
    like($url, qr/username=user1/, 'buildPictureUrl: username appended');
    like($url, qr/password=p%40ss/, 'buildPictureUrl: password url-encoded');

    my $url_s = buildPictureUrl(999, 'detected:car', 0, 'test', 'snapshot');
    like($url_s, qr/fid=snapshot/, 'buildPictureUrl: BESTMATCH replaced with snapshot for frame_id=snapshot');

    # Hook failed — should fall back to snapshot regardless of frame_id
    local $hooks_config{event_start_hook} = '/usr/bin/detect';
    my $url_fail = buildPictureUrl(999, 'motion', 1, 'test', 'alarm');
    like($url_fail, qr/fid=snapshot/, 'buildPictureUrl: objdetect -> snapshot on hook fail');
}
```

**Step 2: Run test to verify it fails**

Run: `cd /home/arjunrc/fiddle/zmeventnotification && prove -v t/02-util.t`
Expected: FAIL — `buildPictureUrl` doesn't accept 5th argument yet.

**Step 3: Implement**

In `ZmEventNotification/Util.pm`, change `buildPictureUrl`:

```perl
sub buildPictureUrl {
  my ($eid, $cause, $resCode, $label, $frame_id) = @_;
  $label //= '';
  $frame_id //= '';

  my $base_url = $notify_config{picture_url} // '';
  return '' if $base_url eq '';

  my $pic = $base_url =~ s/EVENTID/$eid/gr;

  if ($resCode == 1) {
    main::Debug(2, "$label: called when hook failed, not using objdetect in url");
    $pic = $pic =~ s/objdetect(_...)?/snapshot/gr;
  }

  if (!$hooks_config{event_start_hook} || !$hooks_config{enabled}) {
    main::Debug(2, "$label: no start hook or hooks disabled, not using objdetect in url");
    $pic = $pic =~ s/objdetect(_...)/snapshot/gr;
  }

  $pic .= '&username=' . $notify_config{picture_portal_username} if $notify_config{picture_portal_username};
  $pic .= '&password=' . uri_escape($notify_config{picture_portal_password}) if $notify_config{picture_portal_password};

  if ($frame_id eq 'alarm') {
    $pic = $pic =~ s/BESTMATCH/alarm/gr;
    main::Debug(2, "$label: Alarm frame matched, picture url: " . maskPassword($pic));
  } elsif ($frame_id eq 'snapshot') {
    $pic = $pic =~ s/BESTMATCH/snapshot/gr;
    main::Debug(2, "$label: Snapshot frame matched, picture url: $pic");
  }

  return $pic;
}
```

Update callers to extract `frame_id` from the JSON and pass it:

In `ZmEventNotification/HookProcessor.pm` line 35, the websocket caller needs `frame_id`. The `$alarm` hash has `DetectionJson` set at line 367, but `sendOverWebSocket` is called later. We need to parse `frame_id` from the cause or from the stored detection JSON. The detection JSON is available on `$alarm->{Start}->{DetectionJson}` or `$alarm->{End}->{DetectionJson}`.

Actually, the simplest approach: extract `frame_id` from the `[a]`/`[s]`/`[x]` prefix if still present in cause, OR from `DetectionJson` if available. But since we're removing the prefix control from ES, the prefix may or may not be in the cause depending on the hook's `show_frame_match_type` setting. So we need a reliable source.

The `DetectionJson` is set on `$alarm->{Start}->{DetectionJson}` at line 367 (after `parseDetectResults`). The `sendEvent` function is called later with this alarm. Let's trace the flow:

In `HookProcessor.pm`, after `parseDetectResults` returns `$resJsonString`, add a helper to extract `frame_id`:

```perl
# After line 367 in HookProcessor.pm:
$alarm->{Start}->{DetectionJson} = decode_json($resJsonString);
```

The `sendEvent` function receives `$alarm` which has `$alarm->{Start}->{DetectionJson}->{frame_id}` or `$alarm->{End}->{DetectionJson}->{frame_id}`.

In `sendOverWebSocket` (HookProcessor.pm:26):
```perl
sub sendOverWebSocket {
  my $alarm      = shift;
  my $ac         = shift;
  my $event_type = shift;
  my $resCode    = shift;

  my $eid = $alarm->{EventId};
  my $det_key = ($event_type eq 'event_end') ? 'End' : 'Start';
  my $frame_id = '';
  if ($alarm->{$det_key} && $alarm->{$det_key}->{DetectionJson}) {
    $frame_id = $alarm->{$det_key}->{DetectionJson}->{frame_id} // '';
  }

  if ( $notify_config{picture_url} && $notify_config{include_picture} ) {
    $alarm->{Picture} = buildPictureUrl($eid, $alarm->{Cause}, $resCode, 'websocket', $frame_id);
  }
  ...
```

In `FCM.pm:168` (`_prepare_fcm_common`):
```perl
sub _prepare_fcm_common {
  my ($alarm, $obj, $event_type, $resCode, $label) = @_;
  ...
  my $det_key = ($event_type eq 'event_end') ? 'End' : 'Start';
  my $frame_id = '';
  if ($alarm->{$det_key} && $alarm->{$det_key}->{DetectionJson}) {
    $frame_id = $alarm->{$det_key}->{DetectionJson}->{frame_id} // '';
  }

  my $pic = buildPictureUrl($eid, $alarm->{Cause}, $resCode, $label, $frame_id);
  ...
```

**Step 4: Run tests to verify they pass**

Run: `cd /home/arjunrc/fiddle/zmeventnotification && prove -v t/02-util.t`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add ZmEventNotification/Util.pm ZmEventNotification/HookProcessor.pm ZmEventNotification/FCM.pm t/02-util.t
git commit -m "refactor(ES): buildPictureUrl uses frame_id param instead of parsing prefix

Refs #<issue>"
```

---

### Task 3: Remove ES `keep_frame_match_type` and `stripFrameMatchType`

**Files:**
- Modify: `ZmEventNotification/Util.pm:12-16,136-140` (remove from exports, remove function)
- Modify: `ZmEventNotification/Constants.pm:61` (remove DEFAULT_HOOK_KEEP_FRAME_MATCH_TYPE)
- Modify: `ZmEventNotification/Config.pm:236-237,361` (remove config loading and display)
- Modify: `ZmEventNotification/FCM.pm:11,178` (remove import and call)
- Modify: `ZmEventNotification/MQTT.pm:8,19` (remove import and call)
- Modify: `ZmEventNotification/HookProcessor.pm:10,38` (remove import and call)
- Modify: `zmeventnotification.example.yml:318-322` (remove setting)
- Modify: `t/fixtures/test_es.yml:57` (remove setting)
- Modify: `t/02-util.t:59-75` (remove stripFrameMatchType tests)
- Modify: `t/08-websocket-payload.t:154-166` (remove stripFrameMatchType test)

**Step 1: Remove `stripFrameMatchType` function and export**

In `ZmEventNotification/Util.pm`:
- Remove `stripFrameMatchType` from `@EXPORT_OK` (line 15)
- Remove the `stripFrameMatchType` sub (lines 136-140)

**Step 2: Remove all call sites**

In `ZmEventNotification/FCM.pm`:
- Line 11: remove `stripFrameMatchType` from import list
- Line 178: remove `$alarm->{Cause} = stripFrameMatchType($alarm->{Cause});`

In `ZmEventNotification/MQTT.pm`:
- Line 8: remove `stripFrameMatchType` from import (remove the entire use line if it was the only import, or adjust)
- Line 19: remove `$alarm->{Cause} = stripFrameMatchType($alarm->{Cause});`

In `ZmEventNotification/HookProcessor.pm`:
- Line 10: remove `stripFrameMatchType` from import list
- Line 38: remove `$alarm->{Cause} = stripFrameMatchType($alarm->{Cause});`

**Step 3: Remove config loading and constant**

In `ZmEventNotification/Constants.pm`:
- Line 61: remove `DEFAULT_HOOK_KEEP_FRAME_MATCH_TYPE => 'yes',`

In `ZmEventNotification/Config.pm`:
- Lines 236-237: remove `$hooks_config{keep_frame_match_type} = ...`
- Line 361: remove `Keep frame match type.................` display line

**Step 4: Remove from config files**

In `zmeventnotification.example.yml`:
- Remove lines 318-322 (the `keep_frame_match_type` setting and its comments)

In `t/fixtures/test_es.yml`:
- Remove line 57: `keep_frame_match_type: "yes"`

**Step 5: Remove old tests**

In `t/02-util.t`:
- Remove the entire `stripFrameMatchType` test block (lines 59-75)

In `t/08-websocket-payload.t`:
- Remove the `stripFrameMatchType applied` test block (lines 154-166)

**Step 6: Run all tests**

Run: `cd /home/arjunrc/fiddle/zmeventnotification && prove -v t/ && python -m pytest hook/tests/ -v`
Expected: ALL PASS

**Step 7: Commit**

```bash
git add ZmEventNotification/Util.pm ZmEventNotification/Constants.pm ZmEventNotification/Config.pm ZmEventNotification/FCM.pm ZmEventNotification/MQTT.pm ZmEventNotification/HookProcessor.pm zmeventnotification.example.yml t/fixtures/test_es.yml t/02-util.t t/08-websocket-payload.t
git commit -m "refactor(ES): remove keep_frame_match_type — replaced by hook-side show_frame_match_type

Refs #<issue>"
```

---

### Task 4: Update pushover plugin and contrib script

**Files:**
- Modify: `pushapi_plugins/pushapi_pushover.py:61-65`
- Modify: `contrib/ftp_selective_upload.py:70-74`

These scripts parse `[a]` from the cause to pick alarm vs snapshot image. With the prefix now optional, they need a fallback. The cause string passed to these plugins comes from the ES, which may no longer have the prefix.

**Step 1: Update both files to handle missing prefix**

Both files have the same pattern. Update to check for prefix and default to snapshot:

```python
    prefix = cause[0:3] if len(cause) >= 3 else ''
    if prefix == '[a]':
        return path+'/alarm.jpg'
    elif prefix == '[s]':
        return path+'/snapshot.jpg'
    else:
        return path+'/snapshot.jpg'
```

This is backward compatible — works with or without the prefix.

**Step 2: Run lint/syntax check**

Run: `python -c "import py_compile; py_compile.compile('pushapi_plugins/pushapi_pushover.py', doraise=True)"`

**Step 3: Commit**

```bash
git add pushapi_plugins/pushapi_pushover.py contrib/ftp_selective_upload.py
git commit -m "fix(plugins): handle missing frame match prefix in pushover and ftp plugins

Refs #<issue>"
```

---

### Task 5: Update documentation

**Files:**
- Modify: `docs/guides/config.rst` (add `show_frame_match_type` to config reference, remove `keep_frame_match_type` from ES section if present)
- Modify: `docs/guides/es_faq.rst:251-253` (update `keep_frame_match_type` reference)

**Step 1: Add to config reference table**

In `docs/guides/config.rst`, after the `show_models` row (around line 239), add:

```rst
   * - ``show_frame_match_type``
     - ``yes``
     - Show frame match prefix in detection output: ``[a]`` (alarm), ``[s]`` (snapshot), ``[x]`` (other)
```

**Step 2: Update es_faq.rst**

Replace the `keep_frame_match_type` paragraph (lines 251-253) with updated text referencing the new `show_frame_match_type` in `objectconfig.yml`.

**Step 3: Commit**

```bash
git add docs/guides/config.rst docs/guides/es_faq.rst
git commit -m "docs: update config reference for show_frame_match_type, remove keep_frame_match_type

Refs #<issue>"
```

---

### Task 6: Final integration test

**Step 1: Run all Perl tests**

Run: `cd /home/arjunrc/fiddle/zmeventnotification && prove -v t/`
Expected: ALL PASS

**Step 2: Run all Python tests**

Run: `cd /home/arjunrc/fiddle/zmeventnotification && python -m pytest hook/tests/ -v`
Expected: ALL PASS

**Step 3: Verify no stale references**

Run: `grep -r 'keep_frame_match_type' --include='*.pm' --include='*.pl' --include='*.py' --include='*.yml' --include='*.rst' .`
Expected: Only `legacy/zmeventnotification.ini` (which we don't touch).
