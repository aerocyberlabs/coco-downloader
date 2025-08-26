from url_utils import URLClassifier


class FakeResp:
    def __init__(self, url, headers, status_code=200):
        self.url = url
        self.headers = headers
        self.status_code = status_code

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(f"HTTP {self.status_code}")


class FakeSession:
    def __init__(self, head_headers=None, get_headers=None):
        self._head_headers = head_headers or {}
        self._get_headers = get_headers or {}
        self.proxies = {}
        self.headers = {}

    def head(self, url, allow_redirects=True, timeout=10):
        return FakeResp(url, self._head_headers, 200)

    def get(self, url, headers=None, timeout=10, allow_redirects=True):
        return FakeResp(url, self._get_headers, 206)


def test_probe_content_range_when_no_length():
    # HEAD lacks content-length; GET returns Content-Range
    head_headers = {"content-type": "application/octet-stream"}
    get_headers = {"content-range": "bytes 0-0/9999"}
    c = URLClassifier()
    c._session = FakeSession(head_headers=head_headers, get_headers=get_headers)
    info = c.get_direct_file_info("https://example.com/file.bin")
    assert info["ok"] is True
    assert info["filesize"] == 9999
    assert info["filename"].endswith("file.bin")

