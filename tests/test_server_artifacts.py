from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER_SCRIPTS = (
    ROOT / "scripts" / "server_pull_run.sh",
    ROOT / "scripts" / "server_pull_once.sh",
)


def test_server_scripts_export_fixed_run_artifact_dir():
    for script in SERVER_SCRIPTS:
        text = script.read_text(encoding="utf-8")
        assert 'RUN_ARTIFACT_DIR="${RUN_ARTIFACT_DIR:-$ARTIFACT_ROOT/latest}"' in text
        assert 'prepare_run_artifact_dir "$ts"' in text
        assert 'echo "[INFO] artifact_dir=$RUN_ARTIFACT_DIR"' in text
        assert 'find "$RUN_ARTIFACT_DIR" -type f -printf' in text
        assert 'append_artifact_summary' in text