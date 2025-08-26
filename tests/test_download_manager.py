from core.download_manager import DownloadManager


def test_policy_exclude_and_target_dir(tmp_path):
    cfg = {
        'exclude_ext': ['exe'],
        'auto_categorize': True,
        'category_folders': {'Video': 'Vids'}
    }
    mgr = DownloadManager(outdir=str(tmp_path), cfg=cfg, rd_client=None, classifier=None)
    assert mgr.is_excluded('setup.exe') is True
    assert mgr.is_excluded('movie.mp4') is False
    # Default category Video and custom folder mapping
    td = mgr.target_dir_for_name('clip.mp4')
    assert td.endswith('Vids')

def test_aria2_options_for_entry(tmp_path):
    cfg = {'auto_categorize': True, 'category_folders': {'Audio': 'Music'}}
    mgr = DownloadManager(outdir=str(tmp_path), cfg=cfg, rd_client=None, classifier=None)
    ent = {'name': 'song.mp3', 'url': 'https://example.com/song.mp3'}
    opts = mgr.aria2_options_for_entry(ent)
    assert opts['out'] == 'song.mp3'
    assert opts['dir'].endswith('Music')
