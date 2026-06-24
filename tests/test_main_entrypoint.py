import ast
import subprocess
import sys
from pathlib import Path

from src.crypto_demo import crypto_result


ROOT = Path(__file__).resolve().parents[1]


def test_main_delegates_to_command_module():
    tree = ast.parse((ROOT / "main.py").read_text(encoding="utf-8"))
    imports = [node for node in tree.body if isinstance(node, ast.ImportFrom)]
    assert len(imports) == 1
    assert imports[0].module == "src.commands"
    assert [alias.name for alias in imports[0].names] == ["main"]
    assert "src.md5_algo" not in ast.dump(tree)
    assert "src.sha1_algo" not in ast.dump(tree)


def test_main_default_runs_current_command():
    result = subprocess.run(
        [sys.executable, str(ROOT / "main.py")],
        check=True,
        capture_output=True,
        text=True,
    )
    assert result.stdout.strip() == crypto_result()
