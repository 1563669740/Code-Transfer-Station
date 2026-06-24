import argparse
from collections.abc import Sequence

from src.crypto_demo import crypto_result
from src.test import hello


def _run_hello(_args: argparse.Namespace) -> int:
    print(hello())
    return 0


def _run_crypto(_args: argparse.Namespace) -> int:
    print(crypto_result())
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Project command entrypoint")
    subparsers = parser.add_subparsers(dest="command")

    hello_parser = subparsers.add_parser("hello", help="Run the current hello demo")
    hello_parser.set_defaults(handler=_run_hello)

    crypto_parser = subparsers.add_parser("crypto", help="Run MD5 + SHA1 demo on a123456")
    crypto_parser.set_defaults(handler=_run_crypto)

    parser.set_defaults(handler=_run_crypto)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.handler(args)
