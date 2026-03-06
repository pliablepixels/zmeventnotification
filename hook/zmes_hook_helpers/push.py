"""Push notification sender for zm_detect.

Reads registered tokens from ZM's Notifications table via pyzm,
filters by monitor, checks throttle, and sends via FCM cloud function proxy.
"""

import json
import requests
from datetime import datetime


def send_push_notifications(zm, config, monitor_id, event_id, monitor_name, cause, logger):
    """Send FCM push notifications to all qualifying registered tokens.

    Args:
        zm: pyzm ZMClient instance (already authenticated).
        config: dict from g.config (must have 'push' key with push settings).
        monitor_id: int, the monitor that triggered the event.
        event_id: int/str, the event ID.
        monitor_name: str, human-readable monitor name.
        cause: str, detection result string (e.g. "person detected").
        logger: pyzm logger instance.
    """
    push_cfg = config.get('push', {})
    if not push_cfg or push_cfg.get('enabled') != 'yes':
        logger.Debug(1, 'push: disabled in config, skipping')
        return

    fcm_url = push_cfg.get('fcm_v1_url')
    fcm_key = push_cfg.get('fcm_v1_key')

    if not fcm_url or not fcm_key:
        logger.Error('push: fcm_v1_url or fcm_v1_key not configured')
        return

    try:
        notifications = zm.notifications()
    except Exception as e:
        logger.Error('push: failed to fetch notifications from ZM API: {}'.format(e))
        return

    if not notifications:
        logger.Debug(1, 'push: no registered tokens found')
        return

    mid = int(monitor_id)
    sent_count = 0

    for notif in notifications:
        token_suffix = notif.token[-6:] if len(notif.token) > 6 else notif.token

        if not notif.should_notify(mid):
            logger.Debug(2, 'push: skipping token ...{} (monitor {} not in filter)'.format(token_suffix, mid))
            continue

        if notif.is_throttled():
            logger.Debug(2, 'push: skipping token ...{} (throttled, interval={}s)'.format(token_suffix, notif.interval))
            continue

        badge = notif.badge_count + 1
        title = '{} Alarm'.format(monitor_name)
        body = cause if cause else 'Event {} on {}'.format(event_id, monitor_name)

        payload = {
            'token': notif.token,
            'title': title,
            'body': body,
            'sound': 'default',
            'badge': badge,
            'data': {
                'mid': str(mid),
                'eid': str(event_id),
                'monitorName': monitor_name,
                'cause': cause or '',
                'notification_foreground': 'true',
            },
        }

        # Platform-specific fields (proxy format, matching ES FCM.pm proxy mode)
        if notif.platform == 'android':
            payload['android'] = {
                'icon': 'ic_stat_notification',
                'priority': push_cfg.get('android_priority', 'high'),
            }
            ttl = push_cfg.get('android_ttl')
            if ttl:
                payload['android']['ttl'] = str(ttl)
            if push_cfg.get('replace_push_messages') == 'yes':
                payload['android']['tag'] = 'zmninjapush'
            if notif.app_version and notif.app_version != 'unknown':
                payload['android']['channel'] = 'zmninja'

        elif notif.platform == 'ios':
            payload['ios'] = {
                'thread_id': 'zmninja_alarm',
                'headers': {
                    'apns-priority': '10',
                    'apns-push-type': 'alert',
                },
            }
            if push_cfg.get('replace_push_messages') == 'yes':
                payload['ios']['headers']['apns-collapse-id'] = 'zmninjapush'

        # Send via proxy
        try:
            logger.Debug(1, 'push: sending to token ...{} ({})'.format(token_suffix, notif.platform))

            resp = requests.post(
                fcm_url,
                headers={
                    'Content-Type': 'application/json',
                    'Authorization': fcm_key,
                },
                data=json.dumps(payload),
                timeout=10,
            )

            if resp.ok:
                logger.Debug(1, 'push: FCM proxy returned 200 for token ...{}'.format(token_suffix))
                try:
                    notif.update_last_sent(badge=badge)
                except Exception as e:
                    logger.Debug(1, 'push: failed to update LastNotifiedAt: {}'.format(e))
                sent_count += 1
            else:
                body_text = resp.text
                logger.Error('push: FCM proxy error for token ...{}: {}'.format(token_suffix, body_text))
                if 'not a valid FCM' in body_text or 'entity was not found' in body_text:
                    logger.Debug(1, 'push: removing invalid token ...{}'.format(token_suffix))
                    try:
                        notif.delete()
                    except Exception as e:
                        logger.Debug(1, 'push: failed to delete invalid token: {}'.format(e))

        except Exception as e:
            logger.Error('push: exception sending to token ...{}: {}'.format(token_suffix, e))

    logger.Debug(1, 'push: sent {} notifications for event {} on monitor {}'.format(
        sent_count, event_id, monitor_name))
