"""Compute MD5 and SHA1 hashes for the plaintext 'a123456' using the project's pure-Python implementations."""

from src.md5_algo import md5
from src.sha1_algo import sha1

PLAINTEXT = "a123456"


def crypto_result() -> str:
    """Return formatted string with both hash results."""
    return (
        f"MD5('{PLAINTEXT}') = {md5(PLAINTEXT)}\n"
        f"SHA1('{PLAINTEXT}') = {sha1(PLAINTEXT)}"
    )
