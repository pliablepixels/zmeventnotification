import zmes_hook_helpers.common_params as g
from pyzm.log import setup_zm_logging


class wrapperLogger():
    def __init__(self, name, override, dump_console):
        override['dump_console'] = dump_console
        self._adapter = setup_zm_logging(name=name, override=override)

    def debug(self, msg, level=1):
        self._adapter.Debug(level, msg)

    def info(self, msg):
        self._adapter.Info(msg)

    def error(self, msg):
        self._adapter.Error(msg)

    def fatal(self, msg):
        self._adapter.Fatal(msg)

    def setLevel(self, level):
        pass


def init(process_name=None, override={}, dump_console=False):
    g.logger = wrapperLogger(name=process_name, override=override, dump_console=dump_console)
