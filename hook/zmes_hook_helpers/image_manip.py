import io
import os
import time
import traceback
import urllib.parse

import requests

import zmes_hook_helpers.common_params as g
# Generic image related algorithms


def createAnimation(frametype, eid, fname, types):
    import imageio

    verify = g.config.get('allow_self_signed') != 'yes'

    url = '{}/index.php?view=image&width={}&eid={}&username={}&password={}'.format(g.config['portal'],g.config['animation_width'],eid,g.config['user'],urllib.parse.quote(g.config['password'], safe=''))
    api_url = '{}/events/{}.json?username={}&password={}'.format(g.config['api_portal'],eid,g.config['user'],urllib.parse.quote(g.config['password'], safe=''))
    disp_api_url='{}/events/{}.json?username={}&password=***'.format(g.config['api_portal'],eid,g.config['user'])

    rtries = g.config['animation_max_tries']
    sleep_secs = g.config['animation_retry_sleep']
    fid = None
    totframes = 0
    length = 0
    fps = 0

    target_fps = 2
    buffer_seconds = 5 #seconds
    fast_gif = False
    if g.config['fast_gif'] == 'yes':
        fast_gif = True

    while True and rtries:
        g.logger.Debug (1,'animation: Try:{} Getting {}'.format(g.config['animation_max_tries']-rtries+1,disp_api_url ))
        r = None
        try:
            resp = requests.get(api_url, verify=verify)
            resp.raise_for_status()
            r = resp.json()
        except requests.exceptions.RequestException as e:
            g.logger.Error('{}'.format(e))
            continue

        r_event = r['event']['Event']
        r_frame = r['event']['Frame']
        r_frame_len = len(r_frame)

        if frametype == 'alarm':
            fid  = int(r_event.get('AlarmFrameId'))
        elif frametype == 'snapshot':
            fid = int(r_event.get('MaxScoreFrameId'))
        else:
            fid = int(frametype)

        if r_frame is None or not r_frame_len:
            g.logger.Debug (1,'No frames found yet via API, deferring check for {} seconds...'.format(sleep_secs))
            rtries = rtries - 1
            time.sleep(sleep_secs)
            continue
    
        totframes=len(r_frame)
        total_time=round(float(r_frame[-1]['Delta']))
        if total_time <= 0:
            total_time = 1
        fps=round(totframes/total_time)

        if not r_frame_len >= fid+fps*buffer_seconds:
            g.logger.Debug (1,'I\'ve got {} frames, but that\'s not enough as anchor frame is type:{}:{}, deferring check for {} seconds...'.format(r_frame_len, frametype, fid, sleep_secs))
            rtries = rtries - 1
            time.sleep(sleep_secs)
            continue

        g.logger.Debug (1,'animation: Got {} frames'.format(r_frame_len))
        break
        # fid is the anchor frame
    if not rtries:
        g.logger.Error ('animation: Bailing, failed too many times')
        return
  

  
    g.logger.Debug (1,'animation: event fps={}'.format(fps))
    start_frame = int(max(fid - (buffer_seconds*fps),1))
    end_frame = int(min(totframes, fid + (buffer_seconds*fps)))
    skip = round(fps/target_fps)

    g.logger.Debug (1,'animation: anchor={} start={} end={} skip={}'.format(frametype, start_frame, end_frame, skip))
    g.logger.Debug(1,'animation: Grabbing frames...')
    images = []
    od_images = []

    # use frametype  (alarm/snapshot) to get od anchor, because fid can be wrong when translating from videos
    od_url= '{}/index.php?view=image&eid={}&fid={}&username={}&password={}&width={}'.format(g.config['portal'],eid,frametype,g.config['user'],urllib.parse.quote(g.config['password'], safe=''),g.config['animation_width'])
    g.logger.Debug (1,'Grabbing anchor frame: {}...'.format(frametype))
    try:
        od_resp = requests.get(od_url, verify=verify)
        od_resp.raise_for_status()
        od_frame = imageio.imread(io.BytesIO(od_resp.content))
        # 1 second @ 2fps
        od_images.append(od_frame)
        od_images.append(od_frame)
    except Exception as e:
        g.logger.Error ('Error downloading anchor  frame: Error:{}'.format(e))

    for i in range(start_frame, end_frame+1, skip):
        p_url=url+'&fid={}'.format(i)
        g.logger.Debug (2,'animation: Grabbing Frame:{}'.format(i))
        try:
            frame_resp = requests.get(p_url, verify=verify)
            frame_resp.raise_for_status()
            images.append(imageio.imread(io.BytesIO(frame_resp.content)))
        except Exception as e:
            g.logger.Error ('Error downloading frame {}: Error:{}'.format(i,e))

    g.logger.Debug (1,'animation: Saving {}...'.format(fname))
    try:
        if 'mp4' in types.lower():
            g.logger.Debug (1,'Creating MP4...')
            mp4_final = od_images.copy()
            mp4_final.extend(images)
            imageio.mimwrite(fname+'.mp4', mp4_final, format='mp4', fps=target_fps)
            size = os.stat(fname+'.mp4').st_size
            g.logger.Debug (1,'animation: saved to {}.mp4, size {} bytes, frames: {}'.format(fname, size, len(images)))

        if 'gif' in types.lower():
            from pygifsicle import optimize
            g.logger.Debug (1,'Creating GIF...')

            # Let's slice the right amount from images
            # GIF uses a +- 2 second buffer
            gif_buffer_seconds=2
            if fast_gif:
                gif_buffer_seconds = gif_buffer_seconds * 1.5
                target_fps = target_fps * 2
            gif_start_frame = int(max(fid - (gif_buffer_seconds*fps),1))
            gif_end_frame = int(min(totframes, fid + (gif_buffer_seconds*fps)))
            s1 = round((gif_start_frame - start_frame)/skip)
            s2 = round((end_frame - gif_end_frame)/skip)
            if s1 >=0 and s2 >=0:
                gif_images = None
                if fast_gif and 'gif' in types.lower():
                    gif_images = images[0+s1:-s2:2]
                else:
                    gif_images = images[0+s1:-s2]
                g.logger.Debug (1,'For GIF, slicing {} to -{} from a total of {}'.format(s1, s2, len(images)))
                g.logger.Debug (1,'animation:Saving...')
                gif_final = gif_images.copy()
                imageio.mimwrite(fname+'.gif', gif_final, format='gif', fps=target_fps)
                g.logger.Debug (1,'animation:Optimizing...')
                optimize(source=fname+'.gif', colors=256)
                size = os.stat(fname+'.gif').st_size
                g.logger.Debug (1,'animation: saved to {}.gif, size {} bytes, frames:{}'.format(fname, size, len(gif_images)))
            else:
                g.logger.Debug (1,'Bailing in GIF creation, range is weird start:{}:end offset {}'.format(s1, s2))

        
        
    except Exception as e:
        g.logger.Error('animation: Traceback:{}'.format(traceback.format_exc()))





