"""Tests for apigw.py API gateway classes."""
import pytest
import sys
import os
import tempfile


class StubLogger:
    """Stub logger that satisfies g.logger interface."""
    def Debug(self, level, msg): pass
    def Info(self, msg): pass
    def Error(self, msg): pass
    def Fatal(self, msg): raise SystemExit(msg)
    def close(self): pass


class TestObjectRemote:
    """Test the ObjectRemote class."""

    @pytest.fixture
    def labels_file(self):
        """Create a temporary labels file."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
            f.write('person\n')
            f.write('car\n')
            f.write('dog\n')
            f.write('cat\n')
            f.write('bicycle\n')
            return f.name

    @pytest.fixture
    def setup_config(self, labels_file):
        """Setup config with labels file path."""
        import zmes_hook_helpers.common_params as g
        g.config = {'object_labels': labels_file}
        g.logger = StubLogger()
        yield g
        os.unlink(labels_file)

    def test_init_loads_classes(self, setup_config, labels_file):
        """Test that ObjectRemote loads classes from file."""
        from zmes_hook_helpers.apigw import ObjectRemote

        obj = ObjectRemote()

        assert len(obj.classes) == 5
        assert 'person' in obj.classes
        assert 'car' in obj.classes
        assert 'dog' in obj.classes

    def test_set_classes(self, setup_config):
        """Test setting classes manually."""
        from zmes_hook_helpers.apigw import ObjectRemote

        obj = ObjectRemote()
        new_classes = ['truck', 'bus', 'motorcycle']
        obj.set_classes(new_classes)

        assert obj.get_classes() == new_classes

    def test_get_classes(self, setup_config, labels_file):
        """Test getting classes."""
        from zmes_hook_helpers.apigw import ObjectRemote

        obj = ObjectRemote()
        classes = obj.get_classes()

        assert isinstance(classes, list)
        assert len(classes) == 5

    def test_init_missing_file_raises(self):
        """Test that ObjectRemote raises when file is missing."""
        import zmes_hook_helpers.common_params as g
        g.config = {'object_labels': '/nonexistent/labels.txt'}
        g.logger = StubLogger()

        from zmes_hook_helpers.apigw import ObjectRemote

        with pytest.raises(FileNotFoundError):
            ObjectRemote()


class TestFaceRemote:
    """Test the FaceRemote class."""

    @pytest.fixture
    def setup_config(self):
        """Setup config."""
        import zmes_hook_helpers.common_params as g
        g.config = {}
        g.logger = StubLogger()
        return g

    def test_init_empty_classes(self, setup_config):
        """Test that FaceRemote starts with empty classes."""
        from zmes_hook_helpers.apigw import FaceRemote

        face = FaceRemote()

        assert face.classes == []

    def test_set_classes(self, setup_config):
        """Test setting face classes."""
        from zmes_hook_helpers.apigw import FaceRemote

        face = FaceRemote()
        names = ['John', 'Jane', 'Bob']
        face.set_classes(names)

        assert face.get_classes() == names

    def test_get_classes_empty(self, setup_config):
        """Test getting empty classes."""
        from zmes_hook_helpers.apigw import FaceRemote

        face = FaceRemote()

        assert face.get_classes() == []


class TestAlprRemote:
    """Test the AlprRemote class."""

    @pytest.fixture
    def setup_config(self):
        """Setup config."""
        import zmes_hook_helpers.common_params as g
        g.config = {}
        g.logger = StubLogger()
        return g

    def test_init_empty_classes(self, setup_config):
        """Test that AlprRemote starts with empty classes."""
        from zmes_hook_helpers.apigw import AlprRemote

        alpr = AlprRemote()

        assert alpr.classes == []

    def test_set_classes(self, setup_config):
        """Test setting ALPR patterns."""
        from zmes_hook_helpers.apigw import AlprRemote

        alpr = AlprRemote()
        patterns = ['ABC123', 'XYZ789', '.*TEST.*']
        alpr.set_classes(patterns)

        assert alpr.get_classes() == patterns

    def test_get_classes_empty(self, setup_config):
        """Test getting empty classes."""
        from zmes_hook_helpers.apigw import AlprRemote

        alpr = AlprRemote()

        assert alpr.get_classes() == []


class TestAPIGatewayIntegration:
    """Integration tests for API gateway classes."""

    @pytest.fixture
    def labels_file(self):
        """Create COCO-style labels file."""
        labels = [
            'person', 'bicycle', 'car', 'motorcycle', 'airplane',
            'bus', 'train', 'truck', 'boat', 'traffic light'
        ]
        with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
            for label in labels:
                f.write(label + '\n')
            return f.name

    @pytest.fixture
    def setup_all(self, labels_file):
        """Setup all configs."""
        import zmes_hook_helpers.common_params as g
        g.config = {'object_labels': labels_file}
        g.logger = StubLogger()
        yield g
        os.unlink(labels_file)

    def test_multiple_instances_independent(self, setup_all):
        """Test that multiple instances maintain independent state."""
        from zmes_hook_helpers.apigw import FaceRemote, AlprRemote

        face1 = FaceRemote()
        face2 = FaceRemote()
        alpr = AlprRemote()

        face1.set_classes(['Alice', 'Bob'])
        face2.set_classes(['Charlie'])
        alpr.set_classes(['.*'])

        assert face1.get_classes() == ['Alice', 'Bob']
        assert face2.get_classes() == ['Charlie']
        assert alpr.get_classes() == ['.*']

    def test_object_remote_coco_labels(self, setup_all, labels_file):
        """Test ObjectRemote with COCO-style labels."""
        from zmes_hook_helpers.apigw import ObjectRemote

        obj = ObjectRemote()
        classes = obj.get_classes()

        assert 'person' in classes
        assert 'car' in classes
        assert 'truck' in classes
        assert len(classes) == 10
