from utils.urltools import guess_name_from_link


def test_guess_name_from_link_percent():
    name = guess_name_from_link('https://host/path/My%20File%20(1).zip')
    assert 'My File (1).zip' in name


def test_guess_name_from_link_empty():
    name = guess_name_from_link('https://host/')
    assert name

