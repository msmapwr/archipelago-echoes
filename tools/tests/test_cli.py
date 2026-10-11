import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from echo_dev.cli import main


class CliTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.folder = Path(self.temporary.name)
        (self.folder / "project.godot").touch()
        (self.folder / "tests").mkdir()
        (self.folder / "tests/p2_fixture_smoke.gd").touch()
        self.arguments = ["--project", str(self.folder), "--godot", sys.executable, "--output", str(self.folder / "reports")]

    def tearDown(self):
        self.temporary.cleanup()

    def invoke(self, extra):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return main(self.arguments + extra)

    def result(self, passed=True):
        return {"passed": passed, "returncode": 0 if passed else 1, "duration_seconds": 0.1, "errors": [], "warnings": [], "timed_out": False, "interrupted": False, "launch_error": None, "marker_ok": True}

    def test_invalid_case_is_rejected_before_any_execution(self):
        with patch("echo_dev.cli.execute") as execute:
            with self.assertRaises(SystemExit) as error:
                self.invoke(["test", "--case", "../private"])
            self.assertEqual(error.exception.code, 2)
            execute.assert_not_called()
        self.assertFalse((self.folder / "reports").exists())

    def test_scene_escape_and_unbounded_headless_run_are_rejected(self):
        for options in (["run", "--scene", "res://../outside.tscn"], ["run", "--headless"]):
            with patch("echo_dev.cli.execute") as execute:
                with self.assertRaises(SystemExit):
                    self.invoke(options)
                execute.assert_not_called()

    def test_import_failure_stops_tests_and_preserves_report(self):
        with patch("echo_dev.cli.import_project", return_value=self.result(False)), patch("echo_dev.cli.execute") as execute:
            self.assertEqual(self.invoke(["test"]), 1)
            execute.assert_not_called()
        summary = json.loads(next((self.folder / "reports").rglob("summary.json")).read_text())
        self.assertFalse(summary["passed"])
        self.assertEqual(summary["requested_cases"], ["p2_fixture"])

    def test_capture_without_png_is_not_success(self):
        def missing_png(arguments, project, folder, **options):
            folder.mkdir(parents=True)
            return self.result()
        with patch("echo_dev.cli.import_project", return_value=self.result()), patch("echo_dev.cli.execute", side_effect=missing_png):
            self.assertEqual(self.invoke(["capture", "groups-control"]), 1)
        summary = json.loads(next((self.folder / "reports").rglob("summary.json")).read_text())
        self.assertFalse(summary["passed"])

    def test_log_filters_do_not_hide_session_end_in_summary(self):
        path = self.folder / "session.jsonl"
        records = [{"schema_version": 1, "session_id": "s", "kind": "event.weapon_fired", "details": {"order_id": "o"}}, {"schema_version": 1, "session_id": "s", "kind": "session_end", "details": {}}]
        path.write_text("\n".join(json.dumps(record) for record in records))
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(main(["analyze", str(path), "--order", "o", "--json"]), 0)
        summary = json.loads(output.getvalue())
        self.assertEqual(summary["selected_records"], 1)
        self.assertEqual(summary["unfinished_sessions"], [])

    def test_compare_requires_one_session_per_side(self):
        path = self.folder / "two.jsonl"
        path.write_text("\n".join(json.dumps({"schema_version": 1, "kind": "checkpoint", "session_id": session, "state": {"ammo": 1}}) for session in ("one", "two")))
        with self.assertRaises(SystemExit) as error:
            self.invoke(["compare", str(path), str(path)])
        self.assertEqual(error.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
