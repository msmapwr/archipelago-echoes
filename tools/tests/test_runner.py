import os
from pathlib import Path
import re
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from echo_dev.runner import execute, find_godot, new_run, select_tests, PASS_MARKER


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="echo tools with spaces ")
        self.folder = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def run_code(self, source, **options):
        return execute([sys.executable, "-c", source], self.folder, self.folder / "case", **options)

    def test_exit_zero_with_script_error_fails(self):
        result = self.run_code("print('Smoke passed'); print('SCRIPT ERROR: invalid call')", marker=PASS_MARKER)
        self.assertFalse(result["passed"])
        self.assertEqual(result["returncode"], 0)
        self.assertTrue(result["errors"])

    def test_nonzero_and_missing_pass_marker_fail(self):
        self.assertFalse(self.run_code("raise SystemExit(3)")["passed"])
        result = self.run_code("print('engine started')", marker=PASS_MARKER)
        self.assertFalse(result["passed"])
        self.assertFalse(result["marker_ok"])

    def test_clean_success_and_warning_are_distinct(self):
        result = self.run_code("print('P2 smoke test passed'); print('WARNING: existing signal')", marker=PASS_MARKER)
        self.assertTrue(result["passed"])
        self.assertEqual(result["warnings"], ["WARNING: existing signal"])

    def test_stderr_parse_error_and_engine_log_error_are_detected(self):
        result = self.run_code("import sys; print('Parse Error: syntax', file=sys.stderr)")
        self.assertFalse(result["passed"])
        (self.folder / "case" / "engine.log").write_text("ERROR: resource missing\n", encoding="utf-8")
        self.assertFalse(self.run_code("print('done')")["passed"])

    def test_timeout_preserves_partial_output(self):
        result = self.run_code("import time; print('started', flush=True); time.sleep(10)", timeout=0.3)
        self.assertTrue(result["timed_out"])
        self.assertFalse(result["passed"])
        self.assertIn("started", (self.folder / "case/stdout.txt").read_text())
        self.assertTrue((self.folder / "case/result.json").is_file())

    def test_missing_executable_is_reported(self):
        result = execute([str(self.folder / "missing.exe")], self.folder, self.folder / "missing")
        self.assertFalse(result["passed"])
        self.assertIsNotNone(result["launch_error"])
        with self.assertRaises(ValueError):
            find_godot(str(self.folder / "missing.exe"))

    def test_path_with_spaces_and_literal_arguments(self):
        result = execute([sys.executable, "-c", "import sys; print(sys.argv[1])", "literal $(unsafe) & `text`"], self.folder, self.folder / "literal")
        self.assertTrue(result["passed"])
        self.assertIn("literal $(unsafe) & `text`", (self.folder / "literal/stdout.txt").read_text())

    def test_discovery_rejects_path_traversal_and_deduplicates(self):
        (self.folder / "tests").mkdir()
        for name in ("p2_alpha", "menu_ui"):
            (self.folder / "tests" / f"{name}_smoke.gd").touch()
        self.assertEqual(select_tests(self.folder, "p2", None), ["p2_alpha"])
        self.assertEqual(select_tests(self.folder, "all", ["menu_ui", "menu_ui"]), ["menu_ui"])
        with self.assertRaises(ValueError):
            select_tests(self.folder, "all", ["../private"])
        with self.assertRaises(ValueError):
            select_tests(self.folder / "missing", "all", None)

    def test_unique_artifact_directories_preserve_existing_files(self):
        first = new_run(self.folder, "test", self.folder / "reports")
        (first / "marker.txt").write_text("keep")
        second = new_run(self.folder, "test", self.folder / "reports")
        self.assertNotEqual(first, second)
        self.assertEqual((first / "marker.txt").read_text(), "keep")
        self.assertTrue((second / "manifest.json").is_file())


if __name__ == "__main__":
    unittest.main()
