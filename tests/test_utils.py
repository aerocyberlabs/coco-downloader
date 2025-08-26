from rd_client import RealDebridClient
from url_utils import URLClassifier


def test_classifier_direct():
    c = URLClassifier()
    assert c.classify_url("https://example.com/file.bin") == "direct"


def test_parse_cd_filename_basic():
    val = 'attachment; filename="test.bin"'
    name = RealDebridClient._parse_cd_filename(val)
    assert name == "test.bin"
