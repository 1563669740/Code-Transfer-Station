from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER_SCRIPTS = (
    ROOT / "scripts" / "server_pull_run.sh",
    ROOT / "scripts" / "server_pull_once.sh",
)
STATUS_SCRIPT = ROOT / "scripts" / "server_status.sh"


def test_server_scripts_export_fixed_run_artifact_dir():
    for script in SERVER_SCRIPTS:
        text = script.read_text(encoding="utf-8")
        assert 'RUN_ARTIFACT_DIR="${RUN_ARTIFACT_DIR:-$ARTIFACT_ROOT/latest}"' in text
        assert "export RUN_ARTIFACT_DIR" in text
        assert 'prepare_run_artifact_dir "$ts"' in text
        assert 'echo "[INFO] artifact_dir=$RUN_ARTIFACT_DIR"' in text
        assert 'find "$RUN_ARTIFACT_DIR" -type f -printf' in text
        assert 'append_artifact_summary' in text

def test_server_scripts_publish_realtime_status():
    for script in SERVER_SCRIPTS:
        text = script.read_text(encoding="utf-8")
        assert 'STATUS_FILE="${STATUS_FILE:-$LOG_DIR/current_status.txt}"' in text
        assert 'write_status "fetching" "checking origin/$BRANCH"' in text
        assert 'write_status "running" "bash run.sh"' in text
        assert 'write_status "testing" "python3 -m pytest -q"' in text
        assert 'write_status "failed"' in text
        assert 'ln -sfn "$log" "$LOG_DIR/latest.log"' in text


def test_server_status_helper_shows_logs_and_artifacts():
    text = STATUS_SCRIPT.read_text(encoding="utf-8")
    assert 'STATUS_FILE="${STATUS_FILE:-$LOG_DIR/current_status.txt}"' in text
    assert 'server_pull_run.sh is not running' in text
    assert 'Latest artifacts' in text
    assert 'tail -n "$TAIL_LINES" --retry -F' in text
