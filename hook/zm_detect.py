#!/usr/bin/python3
# zm_detect.py -- Main detection script for ZoneMinder events.
#
# Two invocation modes:
# 1. Traditional: called by zmeventnotification.pl via hook
#      zm_detect.py -c config.yml -e <eid> -m <mid> -r "cause" -n
# 2. ZM EventStartCommand / EventEndCommand (ZM 1.37+):
#      Configure in ZM Options -> Config -> EventStartCommand:
#        /path/to/zm_detect.py -c /path/to/config.yml -e %EID% -m %MID% -r "%EC%" -n
#      ZM substitutes %EID%, %MID%, %EC% tokens at runtime (same as zmfilter.pl).

import argparse, ast, json, os, ssl, sys, time, traceback

from pyzm import __version__ as pyzm_version
from pyzm import Detector, ZMClient
from pyzm.models.config import StreamConfig
from pyzm.models.zm import Zone
import zmes_hook_helpers.common_params as g
from zmes_hook_helpers import __version__ as __app_version__
import zmes_hook_helpers.utils as utils


def remote_detect(stream, stream_options, zm_client, args):
    """Detect via remote mlapi gateway. Returns (matched_data, all_matches)."""
    import cv2, imutils, numpy as np, requests
    api_url, ml_timeout = g.config['ml_gateway'], int(g.config.get('ml_timeout', 5))
    data_file = g.config['base_data_path'] + '/zm_login.json'

    # Token management
    access_token = None
    if os.path.exists(data_file):
        try:
            with open(data_file) as f: data = json.load(f)
            if time.time() + 30 - data['time'] < data['expires']: access_token = data['token']
        except Exception: os.remove(data_file)
    if not access_token:
        r = requests.post(api_url + '/login', json={'username': g.config['ml_user'], 'password': g.config['ml_password']},
                          headers={'content-type': 'application/json'}, timeout=ml_timeout)
        data = r.json(); access_token = data.get('access_token')
        if not access_token: raise ValueError('Error getting remote API token: {}'.format(data))
        with open(data_file, 'w') as f: json.dump({'token': access_token, 'expires': data.get('expires'), 'time': time.time()}, f)
    auth = {'Authorization': 'Bearer ' + access_token}

    # Build request files
    files, cmdline_image = {}, None
    if args.get('file'):
        image = cv2.imread(args['file'])
        resize = g.config.get('stream_sequence', {}).get('resize')
        if resize and str(resize) != 'no': image = imutils.resize(image, width=min(int(resize), image.shape[1]))
        cmdline_image = image
        _, jpeg = cv2.imencode('.jpg', image); files = {'file': ('image.jpg', jpeg.tobytes())}

    ml_seq = g.config['ml_sequence']
    ml_overrides = {'model_sequence': ml_seq.get('general',{}).get('model_sequence'),
        'object': {'pattern': ml_seq.get('object',{}).get('general',{}).get('pattern')},
        'face':   {'pattern': ml_seq.get('face',{}).get('general',{}).get('pattern')},
        'alpr':   {'pattern': ml_seq.get('alpr',{}).get('general',{}).get('pattern')}}

    r = requests.post(api_url + '/detect/object?type=object', headers=auth,
                      params={'delete': True, 'response_format': 'zm_detect'}, files=files,
                      json={'version': __app_version__, 'mid': args.get('monitorid'), 'reason': args.get('reason'),
                            'stream': stream, 'stream_options': stream_options, 'ml_overrides': ml_overrides},
                      timeout=ml_timeout)
    r.raise_for_status(); resp = r.json(); matched_data = resp['matched_data']

    if args.get('file'):
        matched_data['image'] = cmdline_image
    elif g.config['write_image_to_zm'] == 'yes' and matched_data.get('frame_id'):
        try:
            url = '{}/index.php?view=image&eid={}&fid={}'.format(g.config['portal'], stream, matched_data['frame_id'])
            img_resp = zm_client.api._make_request(url=url, type='get')
            img = cv2.imdecode(np.asarray(bytearray(img_resp.content), dtype='uint8'), cv2.IMREAD_COLOR)
            dims = matched_data.get('image_dimensions') or {}
            if dims.get('resized') and img.shape[1] != min(dims['resized'][1], img.shape[1]):
                img = imutils.resize(img, width=min(dims['resized'][1], img.shape[1]))
            matched_data['image'] = img
        except Exception as e: g.logger.Error('Error grabbing image: {}'.format(e))
    return matched_data, resp['all_matches']


def _get_event_path(zm_client, event_id, retries=5, delay=2):
    """Look up event path from ZM API, retrying since it may not be set yet at event start."""
    for attempt in range(retries):
        try:
            data = zm_client.api.get('events/{}.json'.format(event_id))
            ev = data.get('event', {}).get('Event', {})
            base = data.get('event', {}).get('Storage', {}).get('Path', '')
            relative = ev.get('RelativePath', '')
            if base and relative:
                path = os.path.join(base, relative)
                if os.path.isdir(path):
                    g.logger.Debug(1, 'Event path resolved: {}'.format(path))
                    return path
        except Exception:
            pass
        if attempt < retries - 1:
            g.logger.Debug(2, 'Event path not ready, retry {}/{}'.format(attempt + 1, retries))
            time.sleep(delay)
    g.logger.Debug(1, 'Could not resolve event path after {} retries'.format(retries))
    return None


def main_handler():
    ap = argparse.ArgumentParser()
    ap.add_argument('-c', '--config', help='config file with path')
    ap.add_argument('-e', '--eventid', help='event ID to retrieve')
    ap.add_argument('-p', '--eventpath', help='path to store object image file', default='')
    ap.add_argument('-m', '--monitorid', help='monitor id - needed for mask')
    ap.add_argument('-v', '--version', action='store_true')
    ap.add_argument('--bareversion', action='store_true')
    ap.add_argument('-o', '--output-path', help='path for debug images')
    ap.add_argument('-f', '--file', help='skip event download, use local file')
    ap.add_argument('-r', '--reason', help='reason for event')
    ap.add_argument('-n', '--notes', action='store_true', help='update ZM notes')
    ap.add_argument('-d', '--debug', action='store_true')
    ap.add_argument('--fakeit', help='override detection results with fake labels for testing (comma-separated, e.g. "dog,person")')
    ap.add_argument('--pyzm-debug', action='store_true', help='route pyzm library debug logs through ZMLog')
    args = vars(ap.parse_known_args()[0])

    if args.get('version'):  print('app:{}, pyzm:{}'.format(__app_version__, pyzm_version)); sys.exit(0)
    if args.get('bareversion'): print(__app_version__); sys.exit(0)
    if not args.get('config'): print('--config required'); sys.exit(1)
    if not args.get('file') and not args.get('eventid'): print('--eventid required'); sys.exit(1)

    # Config + logging (legacy helpers)
    import pyzm.helpers.utils as pyzmutils, pyzm.ZMLog as zmlog
    utils.get_pyzm_config(args)
    if args.get('debug'):
        g.config['pyzm_overrides'].update(dump_console=True, log_debug=True, log_level_debug=5, log_debug_target=None)
    mid = args.get('monitorid')
    zmlog.init(name='zmesdetect_m{}'.format(mid) if mid else 'zmesdetect', override=g.config['pyzm_overrides'])
    g.logger = zmlog

    # Route pyzm's stdlib logging through ZMLog when --pyzm-debug is passed
    if args.get('pyzm_debug'):
        import logging as _logging

        class _ZMLogBridge(_logging.Handler):
            def emit(self, record):
                msg = 'pyzm: ' + self.format(record)
                if record.levelno <= _logging.DEBUG:
                    g.logger.Debug(1, msg)
                elif record.levelno <= _logging.INFO:
                    g.logger.Info(msg)
                elif record.levelno <= _logging.WARNING:
                    g.logger.Warning(msg)
                else:
                    g.logger.Error(msg)

        _pyzm_logger = _logging.getLogger('pyzm')
        _pyzm_logger.setLevel(_logging.DEBUG)
        _pyzm_logger.addHandler(_ZMLogBridge())

    import cv2
    g.logger.Debug(1, 'zm_detect invoked: {}'.format(' '.join(sys.argv)))
    g.logger.Debug(1, '---------| app:{}, pyzm:{}, OpenCV:{}|------------'.format(__app_version__, pyzm_version, cv2.__version__))

    g.polygons, g.ctx = [], ssl.create_default_context()
    utils.process_config(args, g.ctx)
    os.makedirs(g.config['base_data_path'] + '/misc/', exist_ok=True)

    if not g.config['ml_sequence']:  g.logger.Error('ml_sequence missing'); sys.exit(1)
    if not g.config['stream_sequence']: g.logger.Error('stream_sequence missing'); sys.exit(1)

    # Secret substitution
    ml_options = g.config['ml_sequence']
    secrets_flat = pyzmutils.read_config(g.config['secrets']).get('secrets', {}) if g.config.get('secrets') else {}
    ml_options = ast.literal_eval(pyzmutils.template_fill(input_str=str(ml_options), config=None, secrets=secrets_flat))
    g.config['ml_sequence'] = ml_options

    stream_options = g.config['stream_sequence']
    if isinstance(stream_options, str): stream_options = ast.literal_eval(stream_options)

    # Connect to ZM via pyzm v2
    zm = ZMClient(url=g.config['api_portal'], user=g.config['user'], password=g.config['password'],
                  portal_url=g.config['portal'], verify_ssl=(g.config['allow_self_signed'] != 'yes'))
    stream_options['api'], stream_options['polygons'] = zm.api, g.polygons
    g.config['stream_sequence'] = stream_options
    stream = (args.get('eventid') or args.get('file') or '').strip()

    # --- Detection ---
    stream_cfg = StreamConfig.from_dict(stream_options)
    zones = [Zone(name=p['name'], points=p['value'], pattern=p.get('pattern')) for p in g.polygons]
    matched_data = None

    if g.config['ml_gateway']:
        try:
            so = dict(stream_options); so['api'] = None
            matched_data, _ = remote_detect(stream, so, zm, args)
        except Exception as e:
            g.logger.Error('Remote mlapi error: {}'.format(e)); g.logger.Debug(2, traceback.format_exc())
            if g.config['ml_fallback_local'] == 'yes':
                g.logger.Debug(1, 'Falling back to local detection')
                result = Detector.from_dict(ml_options).detect_event(zm, int(stream), zones=zones, stream_config=stream_cfg)
                matched_data = result.to_dict(); matched_data['polygons'] = g.polygons
    else:
        if not args.get('file') and int(g.config.get('wait', 0)) > 0: time.sleep(g.config['wait'])
        detector = Detector.from_dict(ml_options)
        if args.get('file'):
            result = detector.detect(args['file'], zones=zones)
            matched_data = result.to_dict(); matched_data['polygons'] = g.polygons
        else:
            result = detector.detect_event(zm, int(stream), zones=zones, stream_config=stream_cfg)
            matched_data = result.to_dict(); matched_data['polygons'] = g.polygons

    if not matched_data: g.logger.Debug(1, 'No detection data'); matched_data = {}

    # --- Fake override ---
    if args.get('fakeit'):
        fake_labels = [l.strip() for l in args['fakeit'].split(',') if l.strip()]
        g.logger.Debug(1, 'Overriding detection with fake labels: {}'.format(fake_labels))
        matched_data['labels'] = fake_labels
        matched_data['boxes'] = [[50 + i * 100, 50, 150 + i * 100, 200] for i in range(len(fake_labels))]
        matched_data['confidences'] = [0.996] * len(fake_labels)
        matched_data.setdefault('frame_id', 'snapshot')
        matched_data.setdefault('polygons', g.polygons)
        matched_data.setdefault('image_dimensions', {})

    if not matched_data.get('labels'): g.logger.Debug(1, 'No detection data'); return

    # --- Output ---
    output = utils.format_detection_output(matched_data, g.config)
    if not output: return
    pred, jos = output.split('--SPLIT--', 1)
    g.logger.Info('Prediction string:{}'.format(pred)); print(output)

    # --- Write images ---
    if matched_data.get('image') is not None and (g.config['write_image_to_zm'] == 'yes' or g.config['write_debug_image'] == 'yes'):
        debug_image = pyzmutils.draw_bbox(image=matched_data['image'], boxes=matched_data['boxes'],
            labels=matched_data['labels'], confidences=matched_data['confidences'],
            polygons=matched_data.get('polygons', []), poly_thickness=g.config['poly_thickness'],
            write_conf=(g.config['show_percent'] == 'yes'))
        if g.config['write_debug_image'] == 'yes':
            for _b in matched_data.get('error_boxes', []):
                cv2.rectangle(debug_image, (_b[0], _b[1]), (_b[2], _b[3]), (0, 0, 255), 1)
            cv2.imwrite(os.path.join(g.config['image_path'], '{}-{}-debug.jpg'.format(os.path.basename(stream), matched_data['frame_id'])), debug_image)
        if g.config['write_image_to_zm'] == 'yes':
            eventpath = args.get('eventpath')
            if not eventpath and args.get('eventid'):
                eventpath = _get_event_path(zm, args['eventid'])
            if eventpath:
                cv2.imwrite(os.path.join(eventpath, 'objdetect.jpg'), debug_image)
                try:
                    with open(os.path.join(eventpath, 'objects.json'), 'w') as f:
                        json.dump({k: matched_data[k] for k in ('labels','boxes','frame_id','confidences','image_dimensions') if k in matched_data}, f)
                except Exception as e: g.logger.Error('Error writing objects.json: {}'.format(e))
            else:
                g.logger.Debug(1, 'No event path available, skipping write_image_to_zm')

    # --- Update ZM event notes ---
    if args.get('notes') and args.get('eventid'):
        try:
            ev = zm.api.get('events/{}.json'.format(args['eventid']))
            old = ev.get('event',{}).get('Event',{}).get('Notes','')
            parts = old.split('Motion:') if old else ['']
            zm.update_event_notes(int(args['eventid']), pred + ('Motion:' + parts[1] if len(parts) > 1 else ''))
        except Exception as e: g.logger.Error('Error updating notes: {}'.format(e))

    # --- Tag detected objects in ZM ---
    if g.config.get('tag_detected_objects') == 'yes' and args.get('eventid') and matched_data.get('labels'):
        try:
            g.logger.Debug(1, 'Tagging event {} with labels: {}'.format(args['eventid'], matched_data['labels']))
            zm.tag_event(int(args['eventid']), matched_data['labels'])
            g.logger.Debug(1, 'Tagging complete for event {}'.format(args['eventid']))
        except Exception as e: g.logger.Error('Error tagging event: {}'.format(e))

    # --- Animation ---
    if g.config.get('create_animation') == 'yes' and args.get('eventid'):
        try:
            import zmes_hook_helpers.image_manip as img_manip
            img_manip.createAnimation(matched_data['frame_id'], args['eventid'], args.get('eventpath','') + '/objdetect', g.config['animation_types'])
        except Exception as e: g.logger.Error('Animation error: {}'.format(e))


if __name__ == '__main__':
    try:
        main_handler()
        if g.logger: g.logger.Debug(1, 'Closing logs'); g.logger.close()
    except Exception as e:
        if g.logger: g.logger.Fatal('Unrecoverable error:{} Traceback:{}'.format(e, traceback.format_exc())); g.logger.close()
        else: print('Unrecoverable error:{} Traceback:{}'.format(e, traceback.format_exc()))
        sys.exit(1)
