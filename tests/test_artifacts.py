from pathlib import Path

from src.artifacts import ARTIFACT_DIR_ENV, DEFAULT_ARTIFACT_DIR, get_artifact_dir


def test_get_artifact_dir_defaults_to_outputs(monkeypatch, tmp_path):
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv(ARTIFACT_DIR_ENV, raising=False)

    artifact_dir = get_artifact_dir()

    assert artifact_dir == Path(DEFAULT_ARTIFACT_DIR)
    assert artifact_dir.is_dir()


def test_get_artifact_dir_uses_run_artifact_env(monkeypatch, tmp_path):
    expected_dir = tmp_path / "server-artifacts" / "commit-sha"
    monkeypatch.setenv(ARTIFACT_DIR_ENV, str(expected_dir))

    artifact_dir = get_artifact_dir()

    assert artifact_dir == expected_dir
    assert artifact_dir.is_dir()