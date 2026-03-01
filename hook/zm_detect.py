#!/usr/bin/python3
# zm_detect.py -- Main detection script for ZoneMinder events.
#
# Two invocation modes:
# 1. Traditional: called by zmeventnotification.pl via hook
#      zm_detect.py -e <eid> -m <mid> -r "cause" -n
#      (uses /etc/zm/objectconfig.yml by default; override with -c)
# 2. ZM EventStartCommand / EventEndCommand (ZM 1.37+):
#      Configure in ZM Options -> Config -> EventStartCommand:
#        /path/to/zm_detect.py -c /path/to/config.yml -e %EID% -m %MID% -r "%EC%" -n
#      ZM substitutes %EID%, %MID%, %EC% tokens at runtime (same as zmfilter.pl).

import argparse, ast, json, os, re, ssl, sys, time, traceback

import cv2
import numpy as np
import yaml

from pyzm import __version__ as pyzm_version
from pyzm import Detector, ZMClient
from pyzm.models.config import StreamConfig
from pyzm.models.zm import Zone
import zmes_hook_helpers.common_params as g
from zmes_hook_helpers import __version__ as __app_version__
import zmes_hook_helpers.utils as utils


# ---------------------------------------------------------------------------
# Utility helpers (inlined from removed pyzm.helpers.utils)
# ---------------------------------------------------------------------------

def _read_config(path):
    """Read a YAML config file and return a dict."""
    with open(path) as f:
        data = yaml.safe_load(f)
    return data if data else {}


def _template_fill(input_str, config=None, secrets=None):
    """Replace ${key} and !key placeholders with config/secret values."""
    res = input_str
    if config:
        res = re.sub(r'\$\{(\w+?)\}', lambda m: config.get(m.group(1), 'MISSING-{}'.format(m.group(1))), res)
    if secrets:
        res = re.sub(r'!(\w+)', lambda m: secrets.get(m.group(1).lower(), '!{}'.format(m.group(1).lower())), res)
    return res


def _draw_bbox(image, boxes, labels, confidences=None, polygons=None,
               poly_color=(255, 255, 255), poly_thickness=1, write_conf=True):
    """Draw bounding boxes, labels, and zone polygons on *image*."""
    slate_colors = [(39, 174, 96), (142, 68, 173), (0, 129, 254),
                    (254, 60, 113), (243, 134, 48), (91, 177, 47)]
    bgr_slate_colors = slate_colors[::-1]
    image = image.copy()

    if poly_thickness and polygons:
        for ps in polygons:
            cv2.polylines(image, [np.asarray(ps['value'], dtype=np.int32)], True,
                          poly_color, thickness=poly_thickness)

    arr_len = len(bgr_slate_colors)
    for i, label in enumerate(labels):
        box_color = bgr_slate_colors[i % arr_len]
        if write_conf and confidences:
            label += ' {:.2f}%'.format(confidences[i] * 100)
        cv2.rectangle(image, (boxes[i][0], boxes[i][1]),
                       (boxes[i][2], boxes[i][3]), box_color, 2)
        font_scale, font_type, font_thickness = 0.8, cv2.FONT_HERSHEY_SIMPLEX, 1
        text_size = cv2.getTextSize(label, font_type, font_scale, font_thickness)[0]
        r_top_left = (boxes[i][0], boxes[i][1] - text_size[1] - 4)
        r_bottom_right = (boxes[i][0] + text_size[0] + 4, boxes[i][1])
        cv2.rectangle(image, r_top_left, r_bottom_right, box_color, -1)
        cv2.putText(image, label, (boxes[i][0] + 2, boxes[i][1] - 2),
                    font_type, font_scale, (255, 255, 255), font_thickness)
    return image


def main_handler():
    ap = argparse.ArgumentParser()
    ap.add_argument('-c', '--config', default='/etc/zm/objectconfig.yml', help='config file with path')
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
    args = vars(ap.parse_known_args()[0])

    if args.get('version'):  print('app:{}, pyzm:{}'.format(__app_version__, pyzm_version)); sys.exit(0)
    if args.get('bareversion'): print(__app_version__); sys.exit(0)
    if not os.path.isfile(args['config']):
        print('Config file not found: {}'.format(args['config'])); sys.exit(1)
    if not args.get('file') and not args.get('eventid'): print('--eventid required'); sys.exit(1)

    # Config + logging
    from pyzm.log import setup_zm_logging
    utils.get_pyzm_config(args)
    if args.get('debug'):
        g.config['pyzm_overrides'].update(dump_console=True, log_debug=True, log_level_debug=5, log_debug_target=None)
    mid = args.get('monitorid')
    g.logger = setup_zm_logging(name='zmesdetect_m{}'.format(mid) if mid else 'zmesdetect', override=g.config['pyzm_overrides'])

    g.logger.Debug(1, 'zm_detect invoked: {}'.format(' '.join(sys.argv)))
    g.logger.Debug(1, '---------| app:{}, pyzm:{}, OpenCV:{}|------------'.format(__app_version__, pyzm_version, cv2.__version__))

    g.polygons, g.ctx = [], ssl.create_default_context()
    utils.process_config(args, g.ctx)
    os.makedirs(g.config['base_data_path'] + '/misc/', exist_ok=True)

    if not g.config['ml_sequence']:  g.logger.Error('ml_sequence missing'); sys.exit(1)
    if not g.config['stream_sequence']: g.logger.Error('stream_sequence missing'); sys.exit(1)

    # Secret substitution
    ml_options = g.config['ml_sequence']
    secrets_flat = _read_config(g.config['secrets']).get('secrets', {}) if g.config.get('secrets') else {}
    ml_options = ast.literal_eval(_template_fill(str(ml_options), config=None, secrets=secrets_flat))
    g.config['ml_sequence'] = ml_options

    stream_options = g.config['stream_sequence']
    if isinstance(stream_options, str): stream_options = ast.literal_eval(stream_options)

    # Connect to ZM via pyzm v2
    zm = ZMClient(api_url=g.config['api_portal'], user=g.config['user'], password=g.config['password'],
                  portal_url=g.config['portal'], verify_ssl=(g.config['allow_self_signed'] != 'yes'))

    # Import ZM zones via pyzm client (ref: pliablepixels/zmeventnotification#18)
    if g.config.get('import_zm_zones') == 'yes':
        mid = args.get('monitorid')
        if mid:
            utils.import_zm_zones(mid, args.get('reason'), zm)

    stream_options['api'], stream_options['polygons'] = zm.api, g.polygons
    g.config['stream_sequence'] = stream_options
    stream = (args.get('eventid') or args.get('file') or '').strip()

    # --- Detection ---
    stream_cfg = StreamConfig.from_dict(stream_options)
    zones = [Zone(name=p['name'], points=p['value'], pattern=p.get('pattern'), ignore_pattern=p.get('ignore_pattern')) for p in g.polygons]
    matched_data = None

    # Inject remote gateway settings into ml_options so Detector.from_dict() picks them up
    if g.config.get('ml_gateway'):
        ml_options.setdefault('general', {})['ml_gateway'] = g.config['ml_gateway']
        ml_options['general']['ml_user'] = g.config.get('ml_user')
        ml_options['general']['ml_password'] = g.config.get('ml_password')
        ml_options['general']['ml_timeout'] = g.config.get('ml_timeout', 60)
        ml_options['general']['ml_gateway_mode'] = g.config.get('ml_gateway_mode', 'image')

    wait_secs = int(g.config.get('wait', 0))
    if wait_secs > 0:
        g.logger.Debug(1, 'Waiting {} seconds before detection...'.format(wait_secs))
        time.sleep(wait_secs)
    detector = Detector.from_dict(ml_options)

    try:
        if args.get('file'):
            result = detector.detect(args['file'], zones=zones)
        else:
            result = detector.detect_event(zm, int(stream), zones=zones, stream_config=stream_cfg)
        matched_data = result.to_dict(); matched_data['polygons'] = g.polygons
    except Exception as e:
        if detector._gateway and g.config.get('ml_fallback_local') == 'yes':
            g.logger.Debug(1, 'Remote failed ({}), falling back to local'.format(e))
            ml_options['general']['ml_gateway'] = None
            local = Detector.from_dict(ml_options)
            if args.get('file'):
                result = local.detect(args['file'], zones=zones)
            else:
                result = local.detect_event(zm, int(stream), zones=zones, stream_config=stream_cfg)
            matched_data = result.to_dict(); matched_data['polygons'] = g.polygons
        else:
            raise

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
        debug_image = _draw_bbox(image=matched_data['image'], boxes=matched_data['boxes'],
            labels=matched_data['labels'], confidences=matched_data['confidences'],
            polygons=matched_data.get('polygons', []), poly_thickness=g.config['poly_thickness'],
            write_conf=(g.config['show_percent'] == 'yes'))
        if g.config['write_debug_image'] == 'yes':
            for _b in matched_data.get('error_boxes', []):
                cv2.rectangle(debug_image, (_b[0], _b[1]), (_b[2], _b[3]), (0, 0, 255), 1)
            cv2.imwrite(os.path.join(g.config['image_path'], '{}-{}-debug.jpg'.format(os.path.basename(stream), matched_data['frame_id'])), debug_image)
        if g.config['write_image_to_zm'] == 'yes':
            ev = zm.event(int(args['eventid'])) if args.get('eventid') else None
            eventpath = args.get('eventpath') or (ev.path() if ev else None)
            if eventpath:
                os.makedirs(eventpath, exist_ok=True)
                objdetect_path = os.path.join(eventpath, 'objdetect.jpg')
                cv2.imwrite(objdetect_path, debug_image)
                g.logger.Debug(1, 'Wrote objdetect image to {}'.format(objdetect_path))
                try:
                    with open(os.path.join(eventpath, 'objects.json'), 'w') as f:
                        json.dump({k: matched_data[k] for k in ('labels','boxes','frame_id','confidences','image_dimensions') if k in matched_data}, f)
                except Exception as e: g.logger.Error('Error writing objects.json: {}'.format(e))
            else:
                g.logger.Debug(1, 'No event path available, skipping write_image_to_zm')

    # --- Update ZM event notes ---
    if args.get('notes') and args.get('eventid'):
        try:
            ev = zm.event(int(args['eventid']))
            old = ev.notes or ''
            parts = old.split('Motion:') if old else ['']
            ev.update_notes(pred + ('Motion:' + parts[1] if len(parts) > 1 else ''))
        except Exception as e: g.logger.Error('Error updating notes: {}'.format(e))

    # --- Tag detected objects in ZM ---
    if g.config.get('tag_detected_objects') == 'yes' and args.get('eventid') and matched_data.get('labels'):
        try:
            g.logger.Debug(1, 'Tagging event {} with labels: {}'.format(args['eventid'], matched_data['labels']))
            ev = zm.event(int(args['eventid']))
            ev.tag(matched_data['labels'])
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
