import argparse
from collections.abc import Sequence

from src.test import hello


def _run_hello(_args: argparse.Namespace) -> int:
    print(hello())
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Project command entrypoint")
    subparsers = parser.add_subparsers(dest="command")

    hello_parser = subparsers.add_parser("hello", help="Run the current hello demo")
    hello_parser.set_defaults(handler=_run_hello)

    parser.set_defaults(handler=_run_hello)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.handler(args)