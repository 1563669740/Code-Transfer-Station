import ast
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "docs" / "CURRENT_BUSINESS.json"


def _manifest() -> dict:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def _repo_path(path: str) -> Path:
    return ROOT / path


def test_current_business_manifest_paths_exist():
    manifest = _manifest()
    assert manifest["entrypoint"] == {"module": "src.rq4_plots", "function": "main"}

    for key in ("src_files", "test_files"):
        for path in manifest[key]:
            assert _repo_path(path).is_file(), path


def test_main_imports_current_business_entrypoint_only():
    manifest = _manifest()
    tree = ast.parse((ROOT / "main.py").read_text(encoding="utf-8"))
    imports = [node for node in tree.body if isinstance(node, ast.ImportFrom)]

    assert len(imports) == 1
    assert imports[0].module == manifest["entrypoint"]["module"]
    assert [alias.name for alias in imports[0].names] == [manifest["entrypoint"]["function"]]


def test_src_contains_only_current_business_files():
    manifest = _manifest()
    expected = {Path(path) for path in manifest["src_files"]}
    actual = {path.relative_to(ROOT) for path in (ROOT / "src").glob("*.py")}

    assert actual == expected


def test_tests_contain_only_current_business_and_infrastructure_tests():
    manifest = _manifest()
    expected = {Path(path) for path in manifest["test_files"]}
    actual = {path.relative_to(ROOT) for path in (ROOT / "tests").glob("test_*.py")}

    assert actual == expected
