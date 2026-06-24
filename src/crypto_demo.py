"""Compute md5(sha1(plaintext)) for the plaintext 'a123456'."""

from src.md5_algo import md5
from src.sha1_algo import sha1

PLAINTEXT = "a123456"


def inscription_hash(plaintext: str = PLAINTEXT) -> str:
    """Return md5(sha1(plaintext)) using the project hash implementations."""
    return md5(sha1(plaintext))


def crypto_result() -> str:
    """Return formatted output for the inscription hash demo."""
    return f"MD5(SHA1('{PLAINTEXT}')) = {inscription_hash()}"
