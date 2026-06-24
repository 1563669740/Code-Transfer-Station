from src.md5_algo import md5


def test_md5_123456():
    """Verify MD5('123456') matches the well-known result."""
    assert md5("123456") == "e10adc3949ba59abbe56e057f20f883e"


def test_md5_empty():
    """MD5 of empty string."""
    assert md5("") == "d41d8cd98f00b204e9800998ecf8427e"


def test_md5_bytes():
    """MD5 should work with bytes input."""
    assert md5(b"123456") == "e10adc3949ba59abbe56e057f20f883e"


def test_md5_chinese():
    """MD5 of Chinese characters (UTF-8)."""
    assert md5("你好") == "7eca689f0d3389d9dea66ae112e5cfd7"


def test_md5_length():
    """MD5 output is always 32 hex chars."""
    assert len(md5("123456")) == 32
    assert len(md5("short")) == 32
    assert len(md5("a" * 1000)) == 32


def test_md5_hex_chars():
    """MD5 output contains only hex digits."""
    result = md5("123456")
    assert all(c in "0123456789abcdef" for c in result)
