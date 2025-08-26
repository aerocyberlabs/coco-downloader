from utils.categories import ext_from_name, categorize_extension, default_category_exts


def test_ext_from_name_compound():
    assert ext_from_name('archive.tar.gz') == 'tar.gz'
    assert ext_from_name('archive.tar.bz2') == 'tar.bz2'
    assert ext_from_name('archive.tar.xz') == 'tar.xz'
    assert ext_from_name('video.MP4').lower() == 'mp4'


def test_categorize_default_video():
    assert categorize_extension('mp4') == 'Video'
    assert categorize_extension('zip') == 'Compressed'

