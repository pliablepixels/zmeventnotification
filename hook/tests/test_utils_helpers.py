"""Tests for pure utility functions in zmes_hook_helpers.utils."""
import pytest
from zmes_hook_helpers.utils import str2tuple, str_split, findWholeWord


class TestStr2Tuple:
    def test_basic_polygon(self):
        result = str2tuple("0,0 100,0 100,100 0,100")
        assert result == [(0, 0), (100, 0), (100, 100), (0, 100)]

    def test_three_points(self):
        result = str2tuple("10,20 30,40 50,60")
        assert result == [(10, 20), (30, 40), (50, 60)]

    def test_whitespace_in_coords(self):
        # str2tuple splits on single space; extra spaces cause ValueError
        with pytest.raises(ValueError):
            str2tuple("0,0  100,0  100,100")

    def test_too_few_points_raises(self):
        with pytest.raises(ValueError, match="invalid polygon"):
            str2tuple("0,0 100,100")

    def test_single_point_raises(self):
        with pytest.raises(ValueError, match="invalid polygon"):
            str2tuple("0,0")

    def test_float_coords(self):
        """Percentage-based coords must parse. Ref: pliablepixels/zmeventnotification#18"""
        result = str2tuple("26.41,33.5 75.2,33.5 75.2,90.1 26.41,90.1")
        assert result == [(26.41, 33.5), (75.2, 33.5), (75.2, 90.1), (26.41, 90.1)]

    def test_mixed_int_float_coords(self):
        """Integer coords still work (parsed as float)."""
        result = str2tuple("0,0 100,0 100,100 0,100")
        assert result == [(0, 0), (100, 0), (100, 100), (0, 100)]


class TestStrSplit:
    def test_basic_split(self):
        assert str_split("a, b, c") == ["a", "b", "c"]

    def test_no_spaces(self):
        assert str_split("x,y,z") == ["x", "y", "z"]

    def test_single_item(self):
        assert str_split("only") == ["only"]

    def test_extra_whitespace(self):
        assert str_split("  a , b  , c  ") == ["a", "b", "c"]


class TestFindWholeWord:
    def test_match_found(self):
        searcher = findWholeWord("person")
        assert searcher("detected:person in yard") is not None

    def test_no_match(self):
        searcher = findWholeWord("car")
        assert searcher("detected:person") is None

    def test_case_insensitive(self):
        searcher = findWholeWord("Person")
        assert searcher("PERSON detected") is not None

    def test_word_boundary(self):
        searcher = findWholeWord("cat")
        assert searcher("scatter") is None
