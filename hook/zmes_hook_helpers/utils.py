# utility functions that are not generic to a specific model


from __future__ import division
import logging
import logging.handlers
import sys
import datetime
import ssl
import urllib
import json
import time
import re
import ast
import os
import urllib.parse
import traceback

import yaml
import zmes_hook_helpers.common_params as g

from urllib.error import HTTPError


def _deep_merge(base, override):
    """Recursively merge *override* into *base* (both dicts).

    - Dict values are merged recursively.
    - All other types in *override* replace the corresponding key in *base*.
    Returns a new dict; neither input is mutated.
    """
    merged = dict(base)
    for k, v in override.items():
        if k in merged and isinstance(merged[k], dict) and isinstance(v, dict):
            merged[k] = _deep_merge(merged[k], v)
        else:
            merged[k] = v
    return merged


def format_detection_output(matched_data, config=None):
    """Format detection results into PREFIX detected:labels--SPLIT--JSON.

    Returns: formatted string, or "" if no detections.
    """
    if config is None:
        config = getattr(g, 'config', {})

    obj_json = {
        'labels': matched_data['labels'],
        'boxes': matched_data['boxes'],
        'frame_id': matched_data['frame_id'],
        'confidences': matched_data['confidences'],
        'image_dimensions': matched_data['image_dimensions']
    }

    detections = []
    seen = {}
    pred = ''
    prefix = ''

    if matched_data['frame_id'] == 'snapshot':
        prefix = '[s] '
    elif matched_data['frame_id'] == 'alarm':
        prefix = '[a] '
    else:
        prefix = '[x] '

    for idx, l in enumerate(matched_data['labels']):
        if l not in seen:
            label_txt = ''
            if config.get('show_percent') == 'no':
                label_txt = l + ','
            else:
                label_txt = l + ':{:.0%}'.format(matched_data['confidences'][idx]) + ' '
            if config.get('show_models') == 'yes':
                model_txt = '({}) '.format(matched_data['model_names'][idx])
            else:
                model_txt = ''
            pred = pred + model_txt + label_txt
            seen[l] = 1

    if pred != '':
        pred = pred.rstrip(',')
        pred = prefix + 'detected:' + pred
        jos = json.dumps(obj_json)
        return pred + '--SPLIT--' + jos

    return ''


#resize polygons based on analysis scale


def rescale_polygons(xfactor, yfactor):
    newps = []
    for p in g.polygons:
        newp = []
        for x, y in p['value']:
            newx = int(x * xfactor)
            newy = int(y * yfactor)
            newp.append((newx, newy))
        newps.append({'name': p['name'], 'value': newp, 'pattern': p['pattern'], 'ignore_pattern': p.get('ignore_pattern')})
    g.logger.Debug(2,'resized polygons x={}/y={}: {}'.format(
        xfactor, yfactor, newps))
    g.polygons = newps


# converts a string of coordinates 'x1,y1 x2,y2 ...' to a tuple set. We use this
# to parse the polygon parameters in the config file


def str2tuple(str):
    m = [tuple(map(float, x.strip().split(','))) for x in str.split(' ')]
    if len(m) < 3:
        raise ValueError ('{} formed an invalid polygon. Needs to have at least 3 points'.format(m))
    else:
        return m

def str2arr(str):
    return [map(int, x.strip().split(',')) for x in str.split(' ')]


def str_split(my_str):
    return [x.strip() for x in my_str.split(',')]



# credit: https://stackoverflow.com/a/5320179
def findWholeWord(w):
    return re.compile(r'\b({0})\b'.format(w), flags=re.IGNORECASE).search


# Imports zone definitions from ZM
def import_zm_zones(mid, reason):

    match_reason = False
    if reason:
        match_reason = True if g.config['only_triggered_zm_zones']=='yes' else False
    g.logger.Debug(2,'import_zm_zones: match_reason={} and reason={}'.format(match_reason, reason))

    url = g.config['api_portal'] + '/zones/forMonitor/' + mid + '.json'
    g.logger.Debug(2,'Getting ZM zones using {}?username=xxx&password=yyy&user=xxx&pass=yyy'.format(url))
    url = url + '?username=' + g.config['user']
    url = url + '&password=' + urllib.parse.quote(g.config['password'], safe='')
    url = url + '&user=' + g.config['user']
    url = url + '&pass=' + urllib.parse.quote(g.config['password'], safe='')

    if g.config['api_portal'].lower().startswith('https://'):
        main_handler = urllib.request.HTTPSHandler(context=g.ctx)
    else:
        main_handler = urllib.request.HTTPHandler()

    if g.config['basic_user']:
        g.logger.Debug(2,'Basic auth config found, associating handlers')
        password_mgr = urllib.request.HTTPPasswordMgrWithDefaultRealm()
        top_level_url = g.config['api_portal']
        password_mgr.add_password(None, top_level_url, g.config['basic_user'],
                                  g.config['basic_password'])
        handler = urllib.request.HTTPBasicAuthHandler(password_mgr)
        opener = urllib.request.build_opener(handler, main_handler)

    else:
        opener = urllib.request.build_opener(main_handler)
    try:
        input_file = opener.open(url)
    except HTTPError as e:
        g.logger.Error('HTTP Error in import_zm_zones:{}'.format(e))
        raise
    except Exception as e:
        g.logger.Error('General error in import_zm_zones:{}'.format(e))
        raise

    c = input_file.read()
    j = json.loads(c)

    for item in j['zones']:
        if item['Zone']['Type'] == 'Inactive':
            g.logger.Debug(2, 'Skipping {} as it is inactive'.format(item['Zone']['Name']))
            continue
        if  match_reason:
            if not findWholeWord(item['Zone']['Name'])(reason):
                g.logger.Debug(1,'dropping {} as zones in alarm cause is {}'.format(item['Zone']['Name'], reason))
                continue
        item['Zone']['Name'] = item['Zone']['Name'].replace(' ','_').lower()
        g.logger.Debug(2,'importing zoneminder polygon: {} [{}]'.format(item['Zone']['Name'], item['Zone']['Coords']))
        coords = item['Zone']['Coords']
        if item['Zone'].get('Units') == 'Percent':
            # ZoneMinder now stores zone coordinates as percentages (0-100).
            # Convert to pixels using the monitor resolution from the API.
            try:
                mon_url = g.config['api_portal'] + '/monitors/' + mid + '.json'
                mon_url += '?username=' + g.config['user']
                mon_url += '&password=' + urllib.parse.quote(g.config['password'], safe='')
                mon_input = opener.open(mon_url)
                mon_j = json.loads(mon_input.read())
                mon_w = int(mon_j['monitor']['Monitor']['Width'])
                mon_h = int(mon_j['monitor']['Monitor']['Height'])
                g.logger.Debug(1, 'Converting percent zone coords to pixels using monitor {}x{}'.format(mon_w, mon_h))
                pixel_coords = [(int(round(pt[0] * mon_w / 100.0)), int(round(pt[1] * mon_h / 100.0))) for pt in str2tuple(coords)]
                g.polygons.append({'name': item['Zone']['Name'], 'value': pixel_coords, 'pattern': None})
            except Exception as e:
                g.logger.Error('Failed to convert percent zone coords to pixels: {}'.format(e))
                g.polygons.append({'name': item['Zone']['Name'], 'value': str2tuple(coords), 'pattern': None})
        else:
            g.polygons.append({'name': item['Zone']['Name'], 'value': str2tuple(coords), 'pattern': None})



def get_pyzm_config(args):
    g.config['pyzm_overrides'] = {}
    with open(args.get('config')) as f:
        yml = yaml.safe_load(f)
    if yml and 'general' in yml:
        pyzm_overrides = yml['general'].get('pyzm_overrides')
        if pyzm_overrides and isinstance(pyzm_overrides, dict):
            g.config['pyzm_overrides'] = pyzm_overrides
        elif pyzm_overrides and isinstance(pyzm_overrides, str):
            g.config['pyzm_overrides'] = ast.literal_eval(pyzm_overrides) if pyzm_overrides else {}


def process_config(args, ctx):
    # parse YAML config file into a dictionary with defaults

    has_secrets = False
    secrets_file = None

    def _correct_type(val, t):
        if val is None:
            return None
        if t == 'int':
            return int(val)
        elif t == 'eval':
            if isinstance(val, (dict, list, tuple)):
                return val
            return ast.literal_eval(val) if val else None
        elif t == 'dict':
            if isinstance(val, dict):
                return val
            if isinstance(val, str):
                return ast.literal_eval(val) if val else None
            return val
        elif t == 'str_split':
            if isinstance(val, list):
                return val
            return str_split(val) if val else None
        elif t == 'string':
            return str(val) if val is not None else val
        elif t == 'float':
            return float(val)
        else:
            g.logger.Error(
                'Unknown conversion type {} for config key'.format(t))
            return val

    def _resolve_secret(val):
        """If val starts with '!', replace with secret token value."""
        if not isinstance(val, str) or not val or val[0] != '!':
            return val
        g.logger.Debug(2, 'Secret token found in config: {}'.format(val))
        if not has_secrets:
            raise ValueError('Secret token found, but no secret file specified')
        token = val[1:]
        if token in secrets_file.get('secrets', {}):
            return secrets_file['secrets'][token]
        else:
            raise ValueError('secret token {} not found in secrets file'.format(val))

    try:
        g.logger.Info('Reading config from: {}'.format(args.get('config')))
        with open(args.get('config')) as f:
            yml = yaml.safe_load(f)

        if not yml:
            raise ValueError('Config file is empty or invalid YAML')

        # Handle secrets file (YAML format)
        secrets_filename = None
        if yml.get('general', {}).get('secrets'):
            secrets_filename = yml['general']['secrets']
            if not os.path.isfile(secrets_filename):
                raise FileNotFoundError('Secrets file not found: {}'.format(secrets_filename))
            g.logger.Info('Reading secrets from: {}'.format(secrets_filename))
            has_secrets = True
            g.config['secrets'] = secrets_filename
            with open(secrets_filename) as f:
                secrets_file = yaml.safe_load(f)
            if not secrets_file:
                raise ValueError('Secrets file is empty or invalid YAML')
        else:
            g.logger.Debug(1, 'No secrets file configured')

        # First, fill in config with default values from config_vals
        for k, v in g.config_vals.items():
            val = v.get('default', None)
            g.config[k] = _correct_type(val, v['type'])

        # Flatten YAML sections into g.config
        flat_sections = ['general', 'animation', 'remote']
        for section in flat_sections:
            if section not in yml:
                continue
            for k, v in yml[section].items():
                # Resolve secret tokens for string values
                v = _resolve_secret(v)
                if k in g.config_vals:
                    g.config[k] = _correct_type(v, g.config_vals[k]['type'])
                else:
                    g.config[k] = v

        # Handle [ml] section
        if 'ml' in yml:
            ml_section = yml['ml']
            for k, v in ml_section.items():
                if k in ('ml_sequence', 'stream_sequence'):
                    # These are native dicts from YAML - store directly
                    g.config[k] = v
                else:
                    v = _resolve_secret(v)
                    if k in g.config_vals:
                        g.config[k] = _correct_type(v, g.config_vals[k]['type'])
                    else:
                        g.config[k] = v

        # SSL settings
        if g.config['allow_self_signed'] == 'yes':
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            g.logger.Debug(1, 'allowing self-signed certs to work...')
        else:
            g.logger.Debug(1, 'strict SSL cert checking is on...')

        g.polygons = []

        # Check if we have custom overrides for this monitor
        g.logger.Debug(2, 'Now checking for monitor overrides')
        if 'monitorid' in args and args.get('monitorid'):
            mid = args.get('monitorid')
            monitors = yml.get('monitors', {})

            # Try both int and string keys
            monitor_cfg = monitors.get(int(mid)) if mid.isdigit() else None
            if monitor_cfg is None:
                monitor_cfg = monitors.get(mid)
            if monitor_cfg is None:
                monitor_cfg = monitors.get(str(mid))

            if monitor_cfg:
                # Process zone definitions
                zones = monitor_cfg.get('zones', {})
                for zone_name, zone_data in zones.items():
                    coords_str = zone_data.get('coords', '')
                    if coords_str:
                        if g.config['only_triggered_zm_zones'] != 'yes':
                            p = str2tuple(coords_str)
                            pattern = zone_data.get('detection_pattern', None)
                            ignore_pattern = zone_data.get('ignore_pattern', None)
                            g.polygons.append({
                                'name': zone_name,
                                'value': p,
                                'pattern': pattern,
                                'ignore_pattern': ignore_pattern,
                            })
                            g.logger.Debug(2, 'adding polygon: {} [{}] pattern={} ignore_pattern={}'.format(
                                zone_name, coords_str, pattern, ignore_pattern))
                        else:
                            g.logger.Debug(2, 'ignoring polygon: {} as only_triggered_zm_zones is true'.format(zone_name))

                # Apply config overrides from monitor section (deep-merge dicts)
                for k, v in monitor_cfg.items():
                    if k in ('zones',):
                        continue
                    v = _resolve_secret(v)
                    if isinstance(v, dict) and isinstance(g.config.get(k), dict):
                        g.config[k] = _deep_merge(g.config[k], v)
                        g.logger.Debug(3, '[monitor-{}] deep-merged key:{} result:{}'.format(mid, k, g.config[k]))
                    elif k in g.config_vals:
                        g.logger.Debug(3, '[monitor-{}] overrides key:{} with value:{}'.format(mid, k, v))
                        g.config[k] = _correct_type(v, g.config_vals[k]['type'])
                    else:
                        g.logger.Debug(3, '[monitor-{}] overrides key:{} with value:{}'.format(mid, k, v))
                        g.config[k] = v

            # Import ZM zones if needed
            if g.config['only_triggered_zm_zones'] == 'yes':
                g.config['import_zm_zones'] = 'yes'
            if g.config['import_zm_zones'] == 'yes':
                import_zm_zones(args.get('monitorid'), args.get('reason'))
        else:
            g.logger.Info(
                'Ignoring monitor specific settings, as you did not provide a monitor id'
            )
    except Exception as e:
        g.logger.Error('Error parsing config:{}'.format(args.get('config')))
        g.logger.Error('Error was:{}'.format(e))
        g.logger.Fatal('error: Traceback:{}'.format(traceback.format_exc()))
        exit(0)

    # Path substitution: replace ${base_data_path} (and legacy {{base_data_path}})
    # in all string values throughout the config, including nested ml_sequence.
    g.logger.Debug(3, 'Doing path substitution for base_data_path')
    base_data_path = str(g.config.get('base_data_path', '/var/lib/zmeventnotification'))

    def _substitute_paths(obj):
        """Recursively replace ${base_data_path} and legacy {{base_data_path}} in strings."""
        if isinstance(obj, str):
            obj = obj.replace('${base_data_path}', base_data_path)
            obj = obj.replace('{{base_data_path}}', base_data_path)
            return obj
        elif isinstance(obj, dict):
            return {k: _substitute_paths(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [_substitute_paths(item) for item in obj]
        return obj

    # Substitute flat string config values
    for gk, gv in g.config.items():
        if isinstance(gv, str):
            g.config[gk] = _substitute_paths(gv)

    # Substitute nested structures (ml_sequence, stream_sequence)
    for gk in ('ml_sequence', 'stream_sequence'):
        if gk in g.config and isinstance(g.config[gk], dict):
            g.config[gk] = _substitute_paths(g.config[gk])

    # Now munge config if testing args provide
    if args.get('file'):
        g.config['write_image_to_zm'] = 'no'
        g.logger.Debug(1, '--file mode: disabled write_image_to_zm')

    if args.get('output_path'):
        g.logger.Debug(1, 'Output path modified to {}'.format(args.get('output_path')))
        g.config['image_path'] = args.get('output_path')
        g.config['write_debug_image'] = 'yes'
