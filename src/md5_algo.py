"""
Pure Python MD5 algorithm implementation (RFC 1321).
No external libraries — implements the spec from scratch.
"""

import struct
import math


# ── MD5 constants ────────────────────────────────────────────
# Initial state (little-endian interpretation of the spec constants)
INIT_A = 0x67452301
INIT_B = 0xEFCDAB89
INIT_C = 0x98BADCFE
INIT_D = 0x10325476

# Per-round shift amounts
S = (
    # Round 1
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    # Round 2
    5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20,
    # Round 3
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    # Round 4
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
)

# K[i] = floor(2^32 * |sin(i+1)|) for i in 0..63
K = tuple(int((1 << 32) * abs(math.sin(i + 1))) & 0xFFFFFFFF for i in range(64))


# ── Helper: 32-bit left rotation ─────────────────────────────
def _left_rotate(n: int, b: int) -> int:
    """Left-rotate a 32-bit integer n by b bits."""
    return ((n << b) | (n >> (32 - b))) & 0xFFFFFFFF


# ── Helper: 32-bit addition ──────────────────────────────────
def _add32(a: int, b: int) -> int:
    return (a + b) & 0xFFFFFFFF


# ── Padding ──────────────────────────────────────────────────
def _pad(data: bytes) -> bytes:
    """Pad data per MD5 spec: append 0x80, then zeros, then 64-bit length (little-endian)."""
    original_len = len(data)
    # Length in bits, as 64-bit little-endian
    bit_len = (original_len * 8) & 0xFFFFFFFFFFFFFFFF

    # Append a single 0x80 byte
    data += b'\x80'

    # Pad with zeros until (len(data) % 64) == 56
    while (len(data) % 64) != 56:
        data += b'\x00'

    # Append 64-bit original length in little-endian
    data += struct.pack('<Q', bit_len)
    return data


# ── Process one 512-bit block ────────────────────────────────
def _process_block(block: bytes, a: int, b: int, c: int, d: int) -> tuple:
    """Process a single 64-byte block, returning updated (A, B, C, D)."""
    # Unpack block into 16 little-endian 32-bit words
    M = list(struct.unpack('<16I', block))

    A, B_i, C, D = a, b, c, d  # B_i to avoid shadowing builtin

    for i in range(64):
        if i < 16:
            # Round 1: F(B, C, D) = (B & C) | (~B & D)
            F = (B_i & C) | (~B_i & D)
            g = i
        elif i < 32:
            # Round 2: G(B, C, D) = (B & D) | (C & ~D)
            F = (B_i & D) | (C & ~D)
            g = (5 * i + 1) % 16
        elif i < 48:
            # Round 3: H(B, C, D) = B ^ C ^ D
            F = B_i ^ C ^ D
            g = (3 * i + 5) % 16
        else:
            # Round 4: I(B, C, D) = C ^ (B | ~D)
            F = C ^ (B_i | ~D)
            g = (7 * i) % 16

        F = (F + A + K[i] + M[g]) & 0xFFFFFFFF
        A = D
        D = C
        C = B_i
        B_i = _add32(B_i, _left_rotate(F, S[i]))

    return (
        _add32(a, A),
        _add32(b, B_i),
        _add32(c, C),
        _add32(d, D),
    )


# ── Main public API ──────────────────────────────────────────
def md5(data: str | bytes) -> str:
    """
    Compute MD5 hash of input string or bytes.
    Returns a 32-character lowercase hex string.

    >>> md5("123456")
    'e10adc3949ba59abbe56e057f20f883e'

    >>> md5("hello dudu666")
    '70fb7ec2c2debbc9e8fddcea2ba8f18c'
    """
    if isinstance(data, str):
        data = data.encode('utf-8')

    # Pad the message
    padded = _pad(data)

    # Initialize state
    a, b, c, d = INIT_A, INIT_B, INIT_C, INIT_D

    # Process each 64-byte block
    for i in range(0, len(padded), 64):
        a, b, c, d = _process_block(padded[i:i + 64], a, b, c, d)

    # Format result: 4 × 32-bit words in little-endian as hex
    result = struct.pack('<IIII', a, b, c, d)
    return result.hex()
