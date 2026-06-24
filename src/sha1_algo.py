"""
Pure Python SHA-1 algorithm implementation (RFC 3174 / FIPS 180-1).
No external libraries — implements the spec from scratch.
"""

import struct


# ── SHA-1 constants ────────────────────────────────────────────
# Initial hash values (big-endian interpretation of the spec constants)
H0 = 0x67452301
H1 = 0xEFCDAB89
H2 = 0x98BADCFE
H3 = 0x10325476
H4 = 0xC3D2E1F0

# Round constants
K = (
    0x5A827999,  # Round 1:  0 <= t <= 19
    0x6ED9EBA1,  # Round 2: 20 <= t <= 39
    0x8F1BBCDC,  # Round 3: 40 <= t <= 59
    0xCA62C1D6,  # Round 4: 60 <= t <= 79
)


# ── Helper: 32-bit left rotation ─────────────────────────────
def _left_rotate(n: int, b: int) -> int:
    """Left-rotate a 32-bit integer n by b bits."""
    return ((n << b) | (n >> (32 - b))) & 0xFFFFFFFF


# ── Padding ──────────────────────────────────────────────────
def _pad(data: bytes) -> bytes:
    """
    Pad data per SHA-1 spec:
    append 0x80, then zeros until (len % 64) == 56,
    then 64-bit big-endian original bit length.
    """
    original_len = len(data)
    bit_len = original_len * 8

    # Append a single 0x80 byte
    data += b'\x80'

    # Pad with zeros until (len(data) % 64) == 56
    while (len(data) % 64) != 56:
        data += b'\x00'

    # Append 64-bit original length in big-endian
    data += struct.pack('>Q', bit_len)
    return data


# ── Process one 512-bit block ────────────────────────────────
def _process_block(block: bytes, h: tuple) -> tuple:
    """Process a single 64-byte block, returning updated (H0, H1, H2, H3, H4)."""
    # Unpack block into 16 big-endian 32-bit words
    W = list(struct.unpack('>16I', block))

    # Extend to 80 words
    for t in range(16, 80):
        W.append(_left_rotate(W[t - 3] ^ W[t - 8] ^ W[t - 14] ^ W[t - 16], 1))

    a, b, c, d, e = h

    for t in range(80):
        if t < 20:
            # Round 1: (B & C) | (~B & D)
            f = (b & c) | (~b & d)
            k = K[0]
        elif t < 40:
            # Round 2: B ^ C ^ D
            f = b ^ c ^ d
            k = K[1]
        elif t < 60:
            # Round 3: (B & C) | (B & D) | (C & D)
            f = (b & c) | (b & d) | (c & d)
            k = K[2]
        else:
            # Round 4: B ^ C ^ D
            f = b ^ c ^ d
            k = K[3]

        temp = (_left_rotate(a, 5) + f + e + k + W[t]) & 0xFFFFFFFF
        e = d
        d = c
        c = _left_rotate(b, 30)
        b = a
        a = temp

    return (
        (h[0] + a) & 0xFFFFFFFF,
        (h[1] + b) & 0xFFFFFFFF,
        (h[2] + c) & 0xFFFFFFFF,
        (h[3] + d) & 0xFFFFFFFF,
        (h[4] + e) & 0xFFFFFFFF,
    )


# ── Main public API ──────────────────────────────────────────
def sha1(data: str | bytes) -> str:
    """
    Compute SHA-1 hash of input string or bytes.
    Returns a 40-character lowercase hex string.

    >>> sha1("123456")
    '7c4a8d09ca3762af61e59520943dc26494f8941b'

    >>> sha1("")
    'da39a3ee5e6b4b0d3255bfef95601890afd80709'
    """
    if isinstance(data, str):
        data = data.encode('utf-8')

    # Pad the message
    padded = _pad(data)

    # Initialize state
    h = (H0, H1, H2, H3, H4)

    # Process each 64-byte block
    for i in range(0, len(padded), 64):
        h = _process_block(padded[i:i + 64], h)

    # Format result: 5 × 32-bit words in big-endian as hex
    result = struct.pack('>IIIII', h[0], h[1], h[2], h[3], h[4])
    return result.hex()
