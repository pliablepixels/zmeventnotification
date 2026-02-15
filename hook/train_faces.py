
#!/usr/bin/python3
import argparse
import ssl
from pyzm.log import setup_zm_logging
import zmes_hook_helpers.common_params as g
import zmes_hook_helpers.utils as utils
import pyzm.ml.face_train_dlib as train


if __name__ == "__main__":
    g.ctx = ssl.create_default_context()
    ap = argparse.ArgumentParser()
    ap.add_argument('-c', '--config',default='/etc/zm/objectconfig.yml' , help='config file with path')

    args, u = ap.parse_known_args()
    args = vars(args)

    g.logger = setup_zm_logging(name='zm_face_train', override={'dump_console': True})
    utils.process_config(args, g.ctx)

    train.FaceTrain(options=g.config).train()

