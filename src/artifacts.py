"""Helpers for writing generated run artifacts to a predictable directory."""

from pathlib import Path
import os


DEFAULT_ARTIFACT_DIR = "outputs"
ARTIFACT_DIR_ENV = "RUN_ARTIFACT_DIR"


def get_artifact_dir(create: bool = True) -> Path:
    """Return the directory where generated files should be written."""
    artifact_dir = Path(os.environ.get(ARTIFACT_DIR_ENV, DEFAULT_ARTIFACT_DIR))
    if create:
        artifact_dir.mkdir(parents=True, exist_ok=True)
    return artifact_dir
