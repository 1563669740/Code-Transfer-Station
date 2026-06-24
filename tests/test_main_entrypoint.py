import ast
import os
import subprocess
import sys
from pathlib import Path

from src.rq4_plots import PLOT_FILENAMES


ROOT = Path(__file__).resolve().parents[1]


def test_main_delegates_to_latest_rq4_entrypoint():
    tree = ast.parse((ROOT / "main.py").read_text(encoding="utf-8"))
    imports = [node for node in tree.body if isinstance(node, ast.ImportFrom)]
    assert len(imports) == 1
    assert imports[0].module == "src.rq4_plots"
    assert [alias.name for alias in imports[0].names] == ["main"]
    assert "src.commands" not in ast.dump(tree)
    assert "src.crypto_demo" not in ast.dump(tree)
    assert "src.md5_algo" not in ast.dump(tree)
    assert "src.sha1_algo" not in ast.dump(tree)


def test_main_default_generates_rq4_plots(tmp_path):
    result = subprocess.run(
        [sys.executable, str(ROOT / "main.py")],
        check=True,
        capture_output=True,
        env={**os.environ, "RUN_ARTIFACT_DIR": str(tmp_path)},
        text=True,
    )
    assert "Generated RQ4 plots:" in result.stdout
    for filename in PLOT_FILENAMES:
        path = tmp_path / filename
        assert path.is_file()
        assert path.stat().st_size > 0