"""Tests for the --SPLIT-- output format contract between zm_detect.py (Python) and the Perl ES consumer.

These tests validate the real format_detection_output function from utils.py.
"""
import json
import sys
import os
import pytest

# Add hook directory to path so we can import zmes_hook_helpers
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

# Stub out the logger before importing utils
import zmes_hook_helpers.common_params as g


class _FakeLogger:
    def Debug(self, *a, **kw): pass
    def Info(self, *a, **kw): pass
    def Error(self, *a, **kw): pass
    def Warning(self, *a, **kw): pass
    def Fatal(self, *a, **kw): pass

g.logger = _FakeLogger()

from zmes_hook_helpers.utils import format_detection_output


def _make_matched_data(labels, boxes=None, frame_id='alarm',
                       confidences=None, image_dimensions=None,
                       model_names=None):
    if boxes is None:
        boxes = [[0, 0, 1, 1]] * len(labels)
    if confidences is None:
        confidences = [0.95] * len(labels)
    if model_names is None:
        model_names = ['yolo'] * len(labels)
    return {
        'labels': labels,
        'boxes': boxes,
        'frame_id': frame_id,
        'confidences': confidences,
        'image_dimensions': image_dimensions,
        'model_names': model_names,
    }


class TestFormatDetectionOutput:
    def test_single_detection(self):
        data = _make_matched_data(['person'], [[100, 200, 300, 400]], 'alarm', [0.95])
        config = {'show_percent': 'no', 'show_models': 'no'}
        output = format_detection_output(data, config)
        assert '--SPLIT--' in output
        txt, json_str = output.split('--SPLIT--', 1)
        assert txt == '[a] detected:person'
        parsed = json.loads(json_str)
        assert parsed['labels'] == ['person']
        assert parsed['frame_id'] == 'alarm'

    def test_multiple_detections(self):
        data = _make_matched_data(['person', 'car'],
                                  [[100, 200, 300, 400], [10, 20, 30, 40]],
                                  'alarm', [0.95, 0.87])
        config = {'show_percent': 'no', 'show_models': 'no'}
        output = format_detection_output(data, config)
        txt, json_str = output.split('--SPLIT--', 1)
        assert 'person' in txt
        assert 'car' in txt
        parsed = json.loads(json_str)
        assert len(parsed['labels']) == 2

    def test_snapshot_frame(self):
        data = _make_matched_data(['dog'], frame_id='snapshot')
        config = {'show_percent': 'no', 'show_models': 'no'}
        output = format_detection_output(data, config)
        txt, _ = output.split('--SPLIT--', 1)
        assert txt.startswith('[s]')
        parsed = json.loads(output.split('--SPLIT--', 1)[1])
        assert parsed['frame_id'] == 'snapshot'

    def test_no_detections(self):
        data = _make_matched_data([], [], 'alarm', [])
        config = {'show_percent': 'no', 'show_models': 'no'}
        output = format_detection_output(data, config)
        assert output == ''

    def test_duplicate_labels_deduped(self):
        data = _make_matched_data(['person', 'person', 'car'],
                                  [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12]],
                                  'alarm', [0.9, 0.8, 0.7])
        config = {'show_percent': 'no', 'show_models': 'no'}
        output = format_detection_output(data, config)
        txt, _ = output.split('--SPLIT--', 1)
        assert txt.count('person') == 1

    def test_json_has_required_keys(self):
        data = _make_matched_data(['person'])
        config = {'show_percent': 'no', 'show_models': 'no'}
        output = format_detection_output(data, config)
        _, json_str = output.split('--SPLIT--', 1)
        parsed = json.loads(json_str)
        for key in ('labels', 'boxes', 'frame_id', 'confidences', 'image_dimensions'):
            assert key in parsed, f'Missing key: {key}'

    def test_special_chars_in_label(self):
        data = _make_matched_data(['person (hat)'])
        config = {'show_percent': 'no', 'show_models': 'no'}
        output = format_detection_output(data, config)
        txt, json_str = output.split('--SPLIT--', 1)
        assert 'person (hat)' in txt
        parsed = json.loads(json_str)
        assert parsed['labels'][0] == 'person (hat)'

    def test_unknown_frame_prefix(self):
        data = _make_matched_data(['cat'], frame_id='12345')
        config = {'show_percent': 'no', 'show_models': 'no'}
        output = format_detection_output(data, config)
        txt, _ = output.split('--SPLIT--', 1)
        assert txt.startswith('[x]')

    def test_show_percent_yes(self):
        data = _make_matched_data(['person'], confidences=[0.95])
        config = {'show_percent': 'yes', 'show_models': 'no'}
        output = format_detection_output(data, config)
        txt, _ = output.split('--SPLIT--', 1)
        assert '95%' in txt

    def test_show_percent_no(self):
        data = _make_matched_data(['person'], confidences=[0.95])
        config = {'show_percent': 'no', 'show_models': 'no'}
        output = format_detection_output(data, config)
        txt, _ = output.split('--SPLIT--', 1)
        assert '%' not in txt

    def test_show_models_yes(self):
        data = _make_matched_data(['person'], model_names=['yolov4'])
        config = {'show_percent': 'no', 'show_models': 'yes'}
        output = format_detection_output(data, config)
        txt, _ = output.split('--SPLIT--', 1)
        assert '(yolov4)' in txt

    def test_show_models_no(self):
        data = _make_matched_data(['person'], model_names=['yolov4'])
        config = {'show_percent': 'no', 'show_models': 'no'}
        output = format_detection_output(data, config)
        txt, _ = output.split('--SPLIT--', 1)
        assert 'yolov4' not in txt

    def test_show_frame_match_type_no(self):
        data = _make_matched_data(['person'], frame_id='alarm')
        config = {'show_percent': 'no', 'show_models': 'no', 'show_frame_match_type': 'no'}
        output = format_detection_output(data, config)
        txt, _ = output.split('--SPLIT--', 1)
        assert not txt.startswith('[a]')
        assert txt == 'detected:person'

    def test_show_frame_match_type_yes(self):
        data = _make_matched_data(['person'], frame_id='alarm')
        config = {'show_percent': 'no', 'show_models': 'no', 'show_frame_match_type': 'yes'}
        output = format_detection_output(data, config)
        txt, _ = output.split('--SPLIT--', 1)
        assert txt == '[a] detected:person'

    def test_show_frame_match_type_default_yes(self):
        """When show_frame_match_type is not specified, prefix is included (backward compat)."""
        data = _make_matched_data(['person'], frame_id='alarm')
        config = {'show_percent': 'no', 'show_models': 'no'}
        output = format_detection_output(data, config)
        txt, _ = output.split('--SPLIT--', 1)
        assert txt.startswith('[a]')
