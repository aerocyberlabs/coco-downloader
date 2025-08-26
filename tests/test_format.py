from utils.format import format_eta, format_speed, human_size


def test_human_size():
    assert human_size(0).endswith("B")
    assert human_size(1024).startswith("1.0")


def test_format_eta():
    assert format_eta(59) == "0:59"
    assert format_eta(61).startswith("1:01")


def test_format_speed():
    assert format_speed(0).endswith("B/s")
    assert "KiB/s" in format_speed(2048)
