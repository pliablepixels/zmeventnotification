#!/usr/bin/python3
import argparse
import ssl
from pyzm.log import setup_zm_logging
import zmes_hook_helpers.common_params as g
import zmes_hook_helpers.utils as utils

if __name__ == "__main__":
    g.logger = setup_zm_logging(name='zm_train_faces', override={'dump_console': True})
# needs to be after log init

import pyzm.ml.face_train_dlib as train

if __name__ == "__main__":
    g.ctx = ssl.create_default_context()
    ap = argparse.ArgumentParser()
    ap.add_argument('-c',
                    '--config',
                    default='/etc/zm/objectconfig.yml',
                    help='config file with path')

    ap.add_argument('-s',
                    '--size',
                    type=int,
                    help='resize amount (if you run out of memory)')

    args, u = ap.parse_known_args()
    args = vars(args)

    utils.process_config(args, g.ctx)
    train.FaceTrain(options=g.config).train(size=args['size'])
