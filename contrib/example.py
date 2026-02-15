#!/usr/bin/python3

# This is an example of a properly commented contribution. 
# Please follow this template in your contrib PRs

'''
Author: John Appleseed
Contact: <put your github ID here, or a link to your issue tracker>

Intended trigger: <put the appropriate ES trigger that should be used for your script, like "event_start_hook", "event_end_hook", "event_start_hook_notify_userscript", "event_end_hook_notify_userscript" or others

Description: <add a meaningful description of what your script does>

'''


# Arguments:
# All scripts invoked with the xxx_userscript tags
# get the following args passed
#   ARG1: Hook result - 0 if object was detected, 1 if not. 
#         Always check this FIRST  as the json/text string 
#         will be empty if this is 1
#
#   ARG2: Event ID
#   ARG3: Monitor ID
#   ARG4: Monitor Name
#   ARG5: object detection string
#   ARG6: object detection JSON string
#   ARG7: event path (if hook_pass_image_path is yes)

import sys
from pyzm.log import setup_zm_logging

zmlog = setup_zm_logging(name='zmeventnotification_userscript_example')
zmlog.Info("This is a dummy script. Only for your testing. I got {} as arguments".format(sys.argv[1:]))