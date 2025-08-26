from core.download_manager import DownloadManager


class FakeClassifier:
    def __init__(self, direct_url=True):
        self.direct_url = direct_url

    def classify_url(self, link: str) -> str:
        return 'direct' if self.direct_url else 'realdebrid'

    def get_direct_file_info(self, link: str):
        return {
            'ok': True,
            'filename': 'file.bin',
            'filesize': 1234,
            'final_url': link,
        }


class FakeRD:
    def check_link(self, link: str):
        return {'ok': True, 'filesize': 2048}

    def unrestrict_link(self, link: str):
        return {'ok': True, 'download': 'https://host/file.dat', 'filename': 'file.dat', 'filesize': 2048}

    def head_filename(self, url: str):
        return 'file.dat'


def test_build_preview_direct():
    mgr = DownloadManager(outdir='.', cfg={}, rd_client=None, classifier=FakeClassifier(True))
    item = mgr.build_preview_item('https://example.com/a/file.bin')
    assert item['ok'] is True
    assert item['filename'] == 'file.bin'
    assert item['filesize'] == 1234
    assert item['type'] == 'bin'
    assert item['host'] == 'example.com'


def test_build_preview_rd():
    mgr = DownloadManager(outdir='.', cfg={}, rd_client=FakeRD(), classifier=FakeClassifier(False))
    item = mgr.build_preview_item('https://hostersite/abc')
    assert item['ok'] is True
    assert item['filename'] == 'file.dat'
    assert item['filesize'] == 2048
    assert item['type'] == 'dat'
