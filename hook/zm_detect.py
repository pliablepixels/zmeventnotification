#!/usr/bin/python3

# Main detection script that loads different detection models
# look at pyzm.ml for different detectors

from __future__ import division
import sys
#lets do this _after_ log init so we log it
#import cv2
import argparse
import datetime
import os
import traceback
import imutils

# Modules that load cv2 will go later 
# so we can log misses
import pyzm.ZMLog as log 
import zmes_hook_helpers.common_params as g
from pyzm import __version__ as pyzm_version

auth_header = None

from zmes_hook_helpers import __version__ as __app_version__

def remote_detect(stream=None, options=None, api=None, args=None):
    # This uses mlapi (https://github.com/pliablepixels/mlapi) to run inferencing and converts format to what is required by the rest of the code.

    import numpy as np
    import requests
    import cv2
    import json
    import time
    
    bbox = []
    label = []
    conf = []
    model = 'object'
    files={}
    api_url = g.config['ml_gateway']
    if 'ml_timeout' in g.config:
        ml_timeout = int(g.config['ml_timeout'])
    else:
        ml_timeout = 5

    g.logger.Debug(1, 'Detecting using remote API Gateway {}'.format(api_url))
    login_url = api_url + '/login'
    object_url = api_url + '/detect/object?type='+model
    access_token = None
    cmdline_image = None 
    global auth_header

    data_file = g.config['base_data_path'] + '/zm_login.json'
    if os.path.exists(data_file):
        g.logger.Debug(2, 'Found token file, checking if token has not expired')
        with open(data_file) as json_file:
            try:
                data = json.load(json_file)
                json_file.close()
            except Exception as e: 
                g.logger.Error('Error loading login.json: {}'.format(e))
                os.remove(data_file)
                access_token = None
            else:
                generated = data['time']
                expires = data['expires']
                access_token = data['token']
                now = time.time()
                # lets make sure there is at least 30 secs left
                if int(now + 30 - generated) >= expires:
                    g.logger.Debug(1, 'Found access token, but it has expired (or is about to expire)')
                    access_token = None
                else:
                    g.logger.Debug(1, 'Access token is valid for {} more seconds'.format(int(now - generated)))
                    # Get API access token
    if not access_token:
        g.logger.Debug(1, 'Invoking remote API login')
        r = requests.post(url=login_url,
                          data=json.dumps({
                              'username': g.config['ml_user'],
                              'password': g.config['ml_password'],
                          }),
                          headers={'content-type': 'application/json'},
                          timeout = ml_timeout)
        data = r.json()
        access_token = data.get('access_token')
        if not access_token:
            raise ValueError('Error getting remote API token {}'.format(data))
            return
        g.logger.Debug(2, 'Writing new token for future use')
        with open(data_file, 'w') as json_file:
            wdata = {
                'token': access_token,
                'expires': data.get('expires'),
                'time': time.time()
            }
            json.dump(wdata, json_file)
            json_file.close()

    auth_header = {'Authorization': 'Bearer ' + access_token}
    
    params = {'delete': True, 'response_format': 'zm_detect'}

    if args.get('file'):
        g.logger.Debug(2, 'Reading image from {}'.format(args.get('file')))
        image = cv2.imread(args.get('file'))
        stream_resize = g.config.get('stream_sequence', {}).get('resize')
        if stream_resize and str(stream_resize) != 'no':
            neww = min(int(stream_resize), image.shape[1])
            g.logger.Debug(2 ,'Resizing --file image to {}'.format(neww))
            img_new = imutils.resize(image,width=neww)
            image = img_new
            cmdline_image = image
            ret, jpeg = cv2.imencode('.jpg', image)
            files = {'file': ('image.jpg', jpeg.tobytes())}

    else:
        files = {}
    
    ml_overrides = {
        'model_sequence':g.config['ml_sequence'].get('general',{}).get('model_sequence'),
        'object': {
            'pattern': g.config['ml_sequence'].get('object',{}).get('general',{}).get('pattern')
        },
         'face': {
            'pattern': g.config['ml_sequence'].get('face',{}).get('general',{}).get('pattern')
        },
         'alpr': {
            'pattern': g.config['ml_sequence'].get('alpr',{}).get('general',{}).get('pattern')
        },
    }
    mid = args.get('monitorid')
    reason = args.get('reason')
    g.logger.Debug(2, 'Invoking mlapi with url:{} and json: mid={} reason={} stream={}, stream_options={} ml_overrides={} headers={} params={} '.format(object_url,mid, reason, stream, options, ml_overrides, auth_header, params))
    
    start = datetime.datetime.now()
    try:
        r = requests.post(url=object_url,
                        headers=auth_header,
                        params=params,
                        files=files,
                        json = {
                            'version': __app_version__, 
                            'mid': mid,
                            'reason': reason,
                            'stream': stream,
                            'stream_options':options,
                            'ml_overrides':ml_overrides
                        },
                          timeout = ml_timeout)
        r.raise_for_status()
    except Exception as e:
        g.logger.Error('Error during remote post: {}'.format(str(e)))
        g.logger.Debug(2, traceback.format_exc())
        raise

    diff_time = (datetime.datetime.now() - start)
    g.logger.Debug(1, 'remote detection inferencing took: {}'.format(diff_time))
    data = r.json()
    #print(r)
    matched_data = data['matched_data']
    if args.get('file'):

        matched_data['image'] = cmdline_image
    if g.config['write_image_to_zm'] == 'yes'  and matched_data['frame_id']:
        url = '{}/index.php?view=image&eid={}&fid={}'.format(g.config['portal'], stream,matched_data['frame_id'] )
        g.logger.Debug(2, 'Grabbing image from {} as we need to write objdetect.jpg'.format(url))
        try:
            response = api._make_request(url=url,  type='get')
            img = np.asarray(bytearray(response.content), dtype='uint8')
            img = cv2.imdecode(img, cv2.IMREAD_COLOR)
           
            #newh =matched_data['image_dimensions']['resized'][0]
            if matched_data['image_dimensions'] and matched_data['image_dimensions']['resized']:
                neww =min(matched_data['image_dimensions']['resized'][1], img.shape[1])
                oldh, oldw = img.shape[:2]
                if oldw != neww:
                    g.logger.Debug(2, 'Resizing source image from width={} to width={} in zm_detect as that is the size mlapi used'.format(oldw, neww))
                    img = imutils.resize(img,width=neww)
                else:
                    g.logger.Debug(2, 'No need to resize as image widths are same from mlapi and zm_detect: {}'.format(neww))
            matched_data['image'] = img
        except Exception as e:
            g.logger.Error('Error during image grab: {}'.format(str(e)))
            g.logger.Debug(2, traceback.format_exc())
    return data['matched_data'], data['all_matches']


def append_suffix(filename, token):
    f, e = os.path.splitext(filename)
    if not e:
        e = '.jpg'
    return f + token + e


# main handler

def main_handler():
    # set up logging to syslog
    # construct the argument parse and parse the arguments
  
    ap = argparse.ArgumentParser()
    ap.add_argument('-c', '--config', help='config file with path')
    ap.add_argument('-e', '--eventid', help='event ID to retrieve')
    ap.add_argument('-p',
                    '--eventpath',
                    help='path to store object image file',
                    default='')
    ap.add_argument('-m', '--monitorid', help='monitor id - needed for mask')
    ap.add_argument('-v',
                    '--version',
                    help='print version and quit',
                    action='store_true')
    ap.add_argument(
                    '--bareversion',
                    help='print only app version and quit',
                    action='store_true')

    ap.add_argument('-o', '--output-path',
                    help='internal testing use only - path for debug images to be written')

    ap.add_argument('-f',
                    '--file',
                    help='internal testing use only - skips event download')


    ap.add_argument('-r', '--reason', help='reason for event (notes field in ZM)')

    ap.add_argument('-n', '--notes', help='updates notes field in ZM with detections', action='store_true')
    ap.add_argument('-d', '--debug', help='enables debug on console', action='store_true')

    args, u = ap.parse_known_args()
    args = vars(args)

    if args.get('version'):
        print('app:{}, pyzm:{}'.format(__app_version__,pyzm_version))
        exit(0)

    if args.get('bareversion'):
        print('{}'.format(__app_version__))
        exit(0)

    if not args.get('config'):
        print('--config required')
        exit(1)

    if not args.get('file')and not args.get('eventid'):
        print('--eventid required')
        exit(1)

    import zmes_hook_helpers.utils as utils
    import pyzm.helpers.utils as pyzmutils
    utils.get_pyzm_config(args)

    if args.get('debug'):
        g.config['pyzm_overrides']['dump_console'] = True
        g.config['pyzm_overrides']['log_debug'] = True
        g.config['pyzm_overrides']['log_level_debug'] = 5
        g.config['pyzm_overrides']['log_debug_target'] = None

    if args.get('monitorid'):
        log.init(name='zmesdetect_' + 'm' + args.get('monitorid'), override=g.config['pyzm_overrides'])
    else:
        log.init(name='zmesdetect',override=g.config['pyzm_overrides'])
    g.logger = log
    
    import re
    import ssl
    import pickle
    import json
    import time
    import requests
    import subprocess
    import ast

    es_version='(?)'
    try:
        es_version=subprocess.check_output(['/usr/bin/zmeventnotification.pl', '--version']).decode('ascii').strip()
    except:
        pass

    try:
        import cv2
    except ImportError as e:
        g.logger.Fatal('{}: You might not have installed OpenCV as per install instructions. Remember, it is NOT automatically installed'.format(e))

    g.logger.Debug(1, '---------| app:{}, pyzm:{}, ES:{} , OpenCV:{}|------------'.format(__app_version__, pyzm_version, es_version, cv2.__version__))

    # load modules that depend on cv2
    try:
        import zmes_hook_helpers.image_manip as img
    except Exception as e:
        g.logger.Error('{}'.format(e))
        exit(1)
    g.polygons = []

    # process config file
    g.ctx = ssl.create_default_context()
    utils.process_config(args, g.ctx)

    # misc came later, so lets be safe
    if not os.path.exists(g.config['base_data_path'] + '/misc/'):
        try:
            os.makedirs(g.config['base_data_path'] + '/misc/')
        except FileExistsError:
            pass  # if two detects run together with a race here

    if not g.config['ml_gateway']:
        g.logger.Debug(1, 'Importing local classes for Object/Face')
        import pyzm.ml.object as object_detection
       
    else:
        g.logger.Debug(1, 'Importing remote shim classes for Object/Face')
        from zmes_hook_helpers.apigw import ObjectRemote, FaceRemote, AlprRemote
    # now download image(s)

    start = datetime.datetime.now()

    obj_json = []

    import pyzm.api as zmapi
    api_options  = {
    'apiurl': g.config['api_portal'],
    'portalurl': g.config['portal'],
    'user': g.config['user'],
    'password': g.config['password'] ,
    'basic_auth_user': g.config['basic_user'],
    'basic_auth_password': g.config['basic_password'],
    'logger': g.logger, # use none if you don't want to log to ZM,
    'disable_ssl_cert_check': False if g.config['allow_self_signed']=='no' else True
    }

    zmapi = zmapi.ZMApi(options=api_options)
    stream = (args.get('eventid') or args.get('file') or '').strip()
    ml_options = {}
    stream_options = {}
    secrets = None 
    
    if not g.config['ml_sequence']:
        g.logger.Error('ml_sequence not found in config. Cannot proceed.')
        exit(1)

    g.logger.Debug(2, 'using ml_sequence')
    ml_options = g.config['ml_sequence']
    # ml_sequence is already a dict from YAML, but we still need secret substitution
    if g.config.get('secrets'):
        secrets_conf = pyzmutils.read_config(g.config['secrets'])
        secrets_flat = secrets_conf.get('secrets', {})
    else:
        secrets_flat = {}
    ml_options = pyzmutils.template_fill(input_str=str(ml_options), config=None, secrets=secrets_flat)
    ml_options = ast.literal_eval(ml_options)
    g.config['ml_sequence'] = ml_options

    if not g.config['stream_sequence']:
        g.logger.Error('stream_sequence not found in config. Cannot proceed.')
        exit(1)

    g.logger.Debug(2, 'using stream_sequence')
    stream_options = g.config['stream_sequence']
    if isinstance(stream_options, str):
        stream_options = ast.literal_eval(stream_options)


    # These are stream options that need to be set outside of supplied configs         
    stream_options['api'] = zmapi
    stream_options['polygons'] = g.polygons
    g.config['stream_sequence'] = stream_options


    '''
    stream_options = {
            'api': zmapi,
            'download': False,
            'frame_set': frame_set,
            'strategy': g.config['detection_mode'],
            'polygons': g.polygons,
            'resize': int(g.config['resize']) if g.config['resize'] != 'no' else None

    }
    '''

   
    m = None
    matched_data = None
    all_data = None

    if g.config['ml_gateway']:
        stream_options['api'] = None
        start = datetime.datetime.now()
        try:
            matched_data,all_data = remote_detect(stream=stream, options=stream_options, api=zmapi, args=args)
            diff_time = (datetime.datetime.now() - start)
            g.logger.Debug(1, 'Total remote detection detection took: {}'.format(diff_time))
        except Exception as e:
            g.logger.Error("Error with remote mlapi:{}".format(e))
            g.logger.Debug(2, traceback.format_exc())

            if g.config['ml_fallback_local'] == 'yes':
                g.logger.Debug(1, "Falling back to local detection")
                stream_options['api'] = zmapi
                from pyzm.ml.detect_sequence import DetectSequence
                m = DetectSequence(options=ml_options, global_config=g.config)
                matched_data,all_data = m.detect_stream(stream=stream, options=stream_options)
    

    else:
        if not args['file'] and int(g.config['wait']) > 0:
            g.logger.Debug(1, 'Sleeping for {} seconds before inferencing'.format(
            g.config['wait']))
            time.sleep(g.config['wait'])
        from pyzm.ml.detect_sequence import DetectSequence
        m = DetectSequence(options=ml_options, global_config=g.config)
        if args.get('monitorid'):
            stream_options['mid'] = args.get('monitorid')

        matched_data,all_data = m.detect_stream(stream=stream, options=stream_options)
    
    '''
     matched_data = {
            'boxes': matched_b,
            'labels': matched_l,
            'confidences': matched_c,
            'frame_id': matched_frame_id,
            'image_dimensions': self.media.image_dimensions(),
            'image': matched_frame_img
        }
    '''

    obj_json = {
        'labels': matched_data['labels'],
        'boxes': matched_data['boxes'],
        'frame_id': matched_data['frame_id'],
        'confidences': matched_data['confidences'],
        'image_dimensions': matched_data['image_dimensions']
    }

    output = utils.format_detection_output(matched_data, g.config)
    if output:
        pred, jos = output.split('--SPLIT--', 1)
        g.logger.Info('Prediction string:{}'.format(pred))
        g.logger.Debug(1, 'Prediction string JSON:{}'.format(jos))
        print(output)

        if (matched_data['image'] is not None) and (g.config['write_image_to_zm'] == 'yes' or g.config['write_debug_image'] == 'yes'):
            debug_image = pyzmutils.draw_bbox(image=matched_data['image'],boxes=matched_data['boxes'], 
                                              labels=matched_data['labels'], confidences=matched_data['confidences'],
                                              polygons=matched_data['polygons'], poly_thickness = g.config['poly_thickness'],
                                              write_conf=True if g.config['show_percent'] == 'yes' else False )

            if g.config['write_debug_image'] == 'yes':
                for _b in matched_data['error_boxes']:
                    cv2.rectangle(debug_image, (_b[0], _b[1]), (_b[2], _b[3]),
                        (0,0,255), 1)
                filename_debug = g.config['image_path']+'/'+os.path.basename(append_suffix(stream, '-{}-debug'.format(matched_data['frame_id'])))
                g.logger.Debug(1, 'Writing bound boxes to debug image: {}'.format(filename_debug))
                cv2.imwrite(filename_debug,debug_image)

            if g.config['write_image_to_zm'] == 'yes' and args.get('eventpath'):
                g.logger.Debug(1, 'Writing detected image to {}/objdetect.jpg'.format(
                    args.get('eventpath')))
                cv2.imwrite(args.get('eventpath') + '/objdetect.jpg', debug_image)
                jf = args.get('eventpath')+ '/objects.json'
                g.logger.Debug(1, 'Writing JSON output to {}'.format(jf))
                try:
                    with open(jf, 'w') as jo:
                        json.dump(obj_json, jo)
                        jo.close()
                except Exception as e:
                    g.logger.Error('Error creating {}:{}'.format(jf,e))
                    
        if args.get('notes'):
            url = '{}/events/{}.json'.format(g.config['api_portal'], args['eventid'])
            try:
                ev = zmapi._make_request(url=url,  type='get')
            except Exception as e:
                g.logger.Error('Error during event notes retrieval: {}'.format(str(e)))
                g.logger.Debug(2, traceback.format_exc())
                exit(0) # Let's continue with zmdetect

            new_notes = pred
            if ev.get('event',{}).get('Event',{}).get('Notes'): 
                old_notes = ev['event']['Event']['Notes']
                old_notes_split = old_notes.split('Motion:')
                old_d = old_notes_split[0] # old detection
                try:
                    old_m = old_notes_split[1] 
                except IndexError:
                    old_m = ''
                new_notes = pred + 'Motion:'+ old_m
                g.logger.Debug(1, 'Replacing old note:{} with new note:{}'.format(old_notes, new_notes))
                

            payload = {}
            payload['Event[Notes]'] = new_notes
            try:
                ev = zmapi._make_request(url=url, payload=payload, type='put')
            except Exception as e:
                g.logger.Error('Error during notes update: {}'.format(str(e)))
                g.logger.Debug(2, traceback.format_exc())

        if g.config['create_animation'] == 'yes':
            if not args.get('eventid'):
                g.logger.Error('Cannot create animation as you did not pass an event ID')
            else:
                g.logger.Debug(1, 'animation: Creating burst...')
                try:
                    img.createAnimation(matched_data['frame_id'], args.get('eventid'), args.get('eventpath')+'/objdetect', g.config['animation_types'])
                except Exception as e:
                    g.logger.Error('Error creating animation:{}'.format(e))
                    g.logger.Error('animation: Traceback:{}'.format(traceback.format_exc()))
                
            

if __name__ == '__main__':
    try:
        main_handler()
        g.logger.Debug(1, "Closing logs")
        g.logger.close()
    except Exception as e:
        if g.logger:
            g.logger.Fatal('Unrecoverable error:{} Traceback:{}'.format(e,traceback.format_exc()))
            g.logger.Debug(1, "Closing logs")
            g.logger.close()
        else:
            print('Unrecoverable error:{} Traceback:{}'.format(e,traceback.format_exc())) 
        exit(1)
