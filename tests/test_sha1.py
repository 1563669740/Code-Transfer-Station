from src.sha1_algo import sha1


def test_sha1_123456():
    """Verify SHA1('123456') matches the well-known result."""
    assert sha1("123456") == "7c4a8d09ca3762af61e59520943dc26494f8941b"


def test_sha1_empty():
    """SHA1 of empty string."""
    assert sha1("") == "da39a3ee5e6b4b0d3255bfef95601890afd80709"


def test_sha1_hello():
    """SHA1 of 'hello'."""
    assert sha1("hello") == "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d"


def test_sha1_bytes():
    """SHA1 should work with bytes input."""
    assert sha1(b"123456") == "7c4a8d09ca3762af61e59520943dc26494f8941b"


def test_sha1_chinese():
    """SHA1 of Chinese characters (UTF-8)."""
    assert sha1("你好") == "440ee0853ad1e99f962b63e459ef992d7c211722"


def test_sha1_length():
    """SHA1 output is always 40 hex chars."""
    assert len(sha1("123456")) == 40
    assert len(sha1("short")) == 40
    assert len(sha1("a" * 1000)) == 40


def test_sha1_hex_chars():
    """SHA1 output contains only hex digits."""
    result = sha1("123456")
    assert all(c in "0123456789abcdef" for c in result)
