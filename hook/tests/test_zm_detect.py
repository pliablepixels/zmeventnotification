"""Tests for zm_detect.py argument validation.

These tests exercise the early-exit argument-parsing paths in main_handler.
The conftest.py stubs out pyzm so tests run without a ZoneMinder installation.
"""
import pytest
import sys
import os


class TestMainHandlerArgs:
    """Test main_handler argument parsing."""

    def _import_main_handler(self):
        # Force re-import so sys.argv changes take effect in argparse
        if "zm_detect" in sys.modules:
            del sys.modules["zm_detect"]
        from zm_detect import main_handler
        return main_handler

    def test_version_flag(self, capsys):
        """Test --version flag outputs version info."""
        old_argv = sys.argv
        sys.argv = ['zm_detect.py', '--version']
        try:
            main_handler = self._import_main_handler()
            with pytest.raises(SystemExit) as exc_info:
                main_handler()
            assert exc_info.value.code == 0
            captured = capsys.readouterr()
            assert 'app:' in captured.out
            assert 'pyzm:' in captured.out
        finally:
            sys.argv = old_argv

    def test_bareversion_flag(self, capsys):
        """Test --bareversion flag outputs only version number."""
        old_argv = sys.argv
        sys.argv = ['zm_detect.py', '--bareversion']
        try:
            main_handler = self._import_main_handler()
            with pytest.raises(SystemExit) as exc_info:
                main_handler()
            assert exc_info.value.code == 0
            captured = capsys.readouterr()
            assert captured.out.strip()
            assert 'app:' not in captured.out
        finally:
            sys.argv = old_argv

    def test_config_required(self, capsys):
        """Test that --config is required."""
        old_argv = sys.argv
        sys.argv = ['zm_detect.py']
        try:
            main_handler = self._import_main_handler()
            with pytest.raises(SystemExit) as exc_info:
                main_handler()
            assert exc_info.value.code == 1
        finally:
            sys.argv = old_argv

    def test_eventid_required_without_file(self, capsys):
        """Test that --eventid is required when --file not provided."""
        import tempfile
        old_argv = sys.argv
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yml', delete=False) as f:
            f.write('# empty config')
            config_file = f.name
        sys.argv = ['zm_detect.py', '--config', config_file]
        try:
            main_handler = self._import_main_handler()
            with pytest.raises(SystemExit) as exc_info:
                main_handler()
            assert exc_info.value.code == 1
        finally:
            sys.argv = old_argv
            os.unlink(config_file)
