"""Tests for zmes_hook_helpers.log — wrapperLogger delegation."""
from unittest.mock import MagicMock, patch

import zmes_hook_helpers.common_params as g
from zmes_hook_helpers.log import wrapperLogger, init


class TestWrapperLogger:
    """wrapperLogger delegates to ZMLogAdapter methods correctly."""

    def _make_logger(self):
        """Create a wrapperLogger with a mocked setup_zm_logging."""
        mock_adapter = MagicMock()
        with patch("zmes_hook_helpers.log.setup_zm_logging", return_value=mock_adapter):
            logger = wrapperLogger(name="test", override={}, dump_console=False)
        return logger, mock_adapter

    def test_debug_delegates_with_level(self):
        logger, adapter = self._make_logger()
        logger.debug("hello", level=3)
        adapter.Debug.assert_called_once_with(3, "hello")

    def test_debug_default_level_is_1(self):
        logger, adapter = self._make_logger()
        logger.debug("msg")
        adapter.Debug.assert_called_once_with(1, "msg")

    def test_info_delegates(self):
        logger, adapter = self._make_logger()
        logger.info("info msg")
        adapter.Info.assert_called_once_with("info msg")

    def test_error_delegates(self):
        logger, adapter = self._make_logger()
        logger.error("err msg")
        adapter.Error.assert_called_once_with("err msg")

    def test_fatal_delegates(self):
        logger, adapter = self._make_logger()
        logger.fatal("fatal msg")
        adapter.Fatal.assert_called_once_with("fatal msg")

    def test_setLevel_is_noop(self):
        logger, _ = self._make_logger()
        # Should not raise
        logger.setLevel(10)

    def test_dump_console_passed_in_override(self):
        mock_adapter = MagicMock()
        with patch("zmes_hook_helpers.log.setup_zm_logging", return_value=mock_adapter) as mock_setup:
            wrapperLogger(name="test", override={}, dump_console=True)
            _, kwargs = mock_setup.call_args
            assert kwargs.get("override", {}).get("dump_console") is True or \
                   mock_setup.call_args[1].get("override", {}).get("dump_console") is True or \
                   mock_setup.call_args[0][1].get("dump_console") is True

    def test_dump_console_passed_correctly(self):
        """Verify dump_console is set in the override dict passed to setup_zm_logging."""
        mock_adapter = MagicMock()
        with patch("zmes_hook_helpers.log.setup_zm_logging", return_value=mock_adapter) as mock_setup:
            wrapperLogger(name="myproc", override={"log_level_db": -5}, dump_console=True)
            mock_setup.assert_called_once()
            call_kwargs = mock_setup.call_args
            # Could be positional or keyword — check the override dict
            if call_kwargs.kwargs:
                override = call_kwargs.kwargs.get("override", call_kwargs.args[1] if len(call_kwargs.args) > 1 else {})
            else:
                override = call_kwargs.args[1] if len(call_kwargs.args) > 1 else {}
            assert override["dump_console"] is True
            assert override["log_level_db"] == -5


class TestLogInit:
    """log.init() sets g.logger to a wrapperLogger."""

    def test_init_sets_global_logger(self):
        with patch("zmes_hook_helpers.log.setup_zm_logging", return_value=MagicMock()):
            init(process_name="zmdetect", override={}, dump_console=False)
            assert isinstance(g.logger, wrapperLogger)

    def test_init_passes_process_name(self):
        with patch("zmes_hook_helpers.log.setup_zm_logging", return_value=MagicMock()) as mock_setup:
            init(process_name="zmdetect_m5", override={"key": "val"}, dump_console=True)
            mock_setup.assert_called_once_with(
                name="zmdetect_m5",
                override={"key": "val", "dump_console": True},
            )
