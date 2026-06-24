from src.crypto_demo import PLAINTEXT, crypto_result, inscription_hash
from src.md5_algo import md5
from src.sha1_algo import sha1


def test_crypto_result_contains_plaintext():
    """Output should include the plaintext being hashed."""
    output = crypto_result()
    assert PLAINTEXT in output


def test_crypto_result_contains_nested_hash_label():
    """Output should describe the md5(sha1(...)) order."""
    output = crypto_result()
    assert "MD5(SHA1" in output


def test_inscription_hash_matches_nested_computation():
    """Verify the result is md5(sha1(plaintext)), not two separate hashes."""
    assert inscription_hash() == md5(sha1(PLAINTEXT))


def test_crypto_result_matches_manual_computation():
    """Verify the output embeds the correct nested hash value."""
    expected_hash = md5(sha1(PLAINTEXT))
    assert crypto_result() == f"MD5(SHA1('{PLAINTEXT}')) = {expected_hash}"


def test_inscription_hash_accepts_custom_plaintext():
    """Nested hashing should work for any provided plaintext."""
    assert inscription_hash("hello") == md5(sha1("hello"))


def test_crypto_result_not_empty():
    """Result should be a non-empty string."""
    assert len(crypto_result()) > 0
