#!/usr/bin/python3

version = 0.1


'''
Author: Brian P
Contact: 0n3man (github)

Intended trigger: "event_start_hook_notify_userscript"
Description: 

This script pushes images with detected objects to a designated FTP server.

It was developed to allow an alternative to MQTT integration between ZM and 
home assistant (HA).  FTP was used because most cameras support an FTP interface, and so if you’ve 
stared with cameras pushing pictures to HA via FTP, this script allows you to integrate ZM with HA 
in the similar fashion.  My work flow is ZM detects objects, this script pushes images with things 
I care about to HA, HA has a file watcher that kicks off events which can be used in automations.  
My primary use case is for HA to send me pictures containing people when my HA home alarm is turned on.  
That said, this script can be used to push any ZM pictures with detected objects over to an FTP sever.

The script pulls the following parameters from your ZM secrects.ini file:

FTP_USERNAME=yourFTPusername
FTP_PASSWORD=PasswordForYourFTPuser
FTP_SERVER=IPorDomainNameOfFTPSerever
FTP_CAREABOUT=CommaSeparatedListOfObject
FTP_BASEDIR=directyExtentionUsedOnFTPfilename

For a picture to be pushed to the FTP server an object from the FTP_CAREABOUT parameter must have been 
identified in the picture.  An example of FTP_CAREABOUT might be “person,car”.  So if a person or a 
car is detect in the picture it is sent out via FTP. The file is stored on the FTP server with a
filename of /FTP_BASEDIR/MONITOR_NAME/detectedObjects-YY-MM-DD-HH-SS.jpg

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
from datetime import datetime
#import requests
from pyzm.log import setup_zm_logging
import os
import ftplib


# ES passes the image path, this routine figures out which image
# to use inside that path
def get_image(path, cause):
    # as of Mar 2020, pushover doesn't support
    # mp4
    if os.path.exists(path+'/objdetect.gif'):
        return path+'/objdetect.gif'
    elif os.path.exists(path+'/objdetect.jpg'):
        return path+'/objdetect.jpg'
    prefix = cause[0:2]
    if prefix == '[a]':
        return path+'/alarm.jpg'
    else:
        return path+'/snapshot.jpg'

# Simple function to read variables from secret file
def read_secrets(config='/etc/zm/secrets.yml'):
    import yaml
    zmlog.Debug(1, 'eid:{} Reading secrets from {}'.format(eid,config))
    with open(config) as f:
        data = yaml.safe_load(f)
    return data.get('secrets', {})

# -------- MAIN ---------------
zmlog = setup_zm_logging(name='ftp_selective_upload')
zmlog.Info('--------| Selective FTP Plugin v{} |--------'.format(version))
#zmlog.Info ("I got {} arguments".format(len(sys.argv)))
#zmlog.Info ("Arguments:  {}".format(sys.argv[1:]))

if len(sys.argv) != 8:
    zmlog.Error ('Missing arguments, got {} arguments, was expecting 8: {}'.format(len(sys.argv)-1, sys.argv))
    zmlog.close()
    exit(1)

eid = sys.argv[2]
mid = sys.argv[3]
mname = sys.argv[4]
cause = sys.argv[5]
image_path =  sys.argv[7]
fname=get_image(image_path, cause)

# read parameters from secrets
secrets = read_secrets()
passwd = secrets.get('FTP_PASSWORD')
user = secrets.get('FTP_USERNAME')
server = secrets.get('FTP_SERVER')
careaboutlist = secrets.get('FTP_CAREABOUT').split(',')
dirBase = secrets.get('FTP_BASEDIR')

zmlog.Debug(1,"eid:{} FTP {} to {} as {}".format(eid,fname,server,user))

preExt,fileExt= os.path.splitext(fname)

#See if object we care about is in the list
reason = None
for item in careaboutlist:
    if item in cause:
        if reason is None:
            reason = item
        else:
            reason = reason + "-" + item

# Only FTP if file matches something we care about
if not reason:
    zmlog.Info('eid:{} File not transfered as cause[{}] did not match care about list [{}]'.format(eid,cause, careaboutlist))
    exit()

#Build the FTP command and file path
ftpcmd = 'STOR ' + dirBase + mname + '/' + reason + '-' + datetime.now().strftime('%x-%X').replace('/','-',3) + fileExt

# create FTP session and execute command to store file
session = ftplib.FTP(server,user,passwd)
file = open(fname,'rb')                         # file to send
zmlog.Info("eid:{} FTP cmd: {}".format(eid,ftpcmd))
session.storbinary(ftpcmd, file)     # send the file
file.close()                                    # close file and FTP
session.quit()

zmlog.Debug(1,"eid:{} FTP upload done".format(eid))
zmlog.close()
