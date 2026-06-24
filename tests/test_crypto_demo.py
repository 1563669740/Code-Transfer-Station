from src.crypto_demo import crypto_result, PLAINTEXT
from src.md5_algo import md5
from src.sha1_algo import sha1


def test_crypto_result_contains_plaintext():
    """Output should include the plaintext being hashed."""
    output = crypto_result()
    assert PLAINTEXT in output


def test_crypto_result_contains_md5_label():
    """Output should contain an MD5 label."""
    assert "MD5" in crypto_result()


def test_crypto_result_contains_sha1_label():
    """Output should contain an SHA1 label."""
    assert "SHA1" in crypto_result()


def test_crypto_result_matches_manual_computation():
    """Verify the output embeds the correct hash values, not hardcoded strings."""
    output = crypto_result()
    assert md5(PLAINTEXT) in output
    assert sha1(PLAINTEXT) in output


def test_crypto_result_not_empty():
    """Result should be a non-empty string."""
    assert len(crypto_result()) > 0
