"""Tests for zm_detect.py functions.

These tests focus on the append_suffix function and argument validation
which don't require heavy cv2 dependencies.
"""
import pytest
import sys
import os


class TestAppendSuffix:
    """Test the append_suffix function."""

    def test_append_suffix_with_extension(self):
        """Test appending suffix to filename with extension."""
        # Import directly the function we need
        sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
        from zm_detect import append_suffix

        result = append_suffix('/path/to/image.jpg', '_debug')
        assert result == '/path/to/image_debug.jpg'

    def test_append_suffix_without_extension(self):
        """Test appending suffix to filename without extension."""
        from zm_detect import append_suffix

        result = append_suffix('/path/to/image', '_debug')
        assert result == '/path/to/image_debug.jpg'

    def test_append_suffix_png_extension(self):
        """Test appending suffix preserves PNG extension."""
        from zm_detect import append_suffix

        result = append_suffix('/path/to/image.png', '_annotated')
        assert result == '/path/to/image_annotated.png'

    def test_append_suffix_complex_path(self):
        """Test appending suffix with complex path."""
        from zm_detect import append_suffix

        result = append_suffix('/var/cache/zoneminder/events/1/2024-01-01/frame.jpg', '_objdetect')
        assert result == '/var/cache/zoneminder/events/1/2024-01-01/frame_objdetect.jpg'

    def test_append_suffix_empty_token(self):
        """Test appending empty suffix."""
        from zm_detect import append_suffix

        result = append_suffix('/path/to/image.jpg', '')
        assert result == '/path/to/image.jpg'

    def test_append_suffix_double_extension(self):
        """Test filename with multiple dots."""
        from zm_detect import append_suffix

        result = append_suffix('/path/to/image.test.jpg', '_suffix')
        assert result == '/path/to/image.test_suffix.jpg'


class TestMainHandlerArgs:
    """Test main_handler argument parsing."""

    def test_version_flag(self, capsys):
        """Test --version flag outputs version info."""
        import sys
        old_argv = sys.argv
        sys.argv = ['zm_detect.py', '--version']

        from zm_detect import main_handler

        with pytest.raises(SystemExit) as exc_info:
            main_handler()

        assert exc_info.value.code == 0
        captured = capsys.readouterr()
        assert 'app:' in captured.out
        assert 'pyzm:' in captured.out
        sys.argv = old_argv

    def test_bareversion_flag(self, capsys):
        """Test --bareversion flag outputs only version number."""
        import sys
        old_argv = sys.argv
        sys.argv = ['zm_detect.py', '--bareversion']

        from zm_detect import main_handler

        with pytest.raises(SystemExit) as exc_info:
            main_handler()

        assert exc_info.value.code == 0
        captured = capsys.readouterr()
        # Should just print version number, no 'app:' or 'pyzm:'
        assert captured.out.strip()
        assert 'app:' not in captured.out
        sys.argv = old_argv

    def test_config_required(self, capsys):
        """Test that --config is required."""
        import sys
        old_argv = sys.argv
        sys.argv = ['zm_detect.py']

        from zm_detect import main_handler

        with pytest.raises(SystemExit) as exc_info:
            main_handler()

        assert exc_info.value.code == 1
        sys.argv = old_argv

    def test_eventid_required_without_file(self, capsys):
        """Test that --eventid is required when --file not provided."""
        import sys
        import tempfile
        old_argv = sys.argv

        # Create temp config file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yml', delete=False) as f:
            f.write('# empty config')
            config_file = f.name

        sys.argv = ['zm_detect.py', '--config', config_file]

        from zm_detect import main_handler

        with pytest.raises(SystemExit) as exc_info:
            main_handler()

        assert exc_info.value.code == 1
        sys.argv = old_argv
        os.unlink(config_file)
