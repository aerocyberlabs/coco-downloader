from core.download_manager import DownloadManager


class FakeClassifier:
    def classify_url(self, link: str) -> str:
        return 'realdebrid'


class FakeRDNoName:
    def check_link(self, link: str):
        return {'ok': True, 'filesize': 111}

    def unrestrict_link(self, link: str):
        # No filename returned
        return {'ok': True, 'download': 'https://host/path/data.bin', 'filesize': 111}

    def head_filename(self, url: str):
        return 'inferred.bin'


def test_rd_preview_infers_filename_from_head():
    mgr = DownloadManager(outdir='.', cfg={}, rd_client=FakeRDNoName(), classifier=FakeClassifier())
    item = mgr.build_preview_item('https://host/some')
    assert item['ok'] is True
    assert item['filename'] == 'inferred.bin'
    assert item['filesize'] == 111

