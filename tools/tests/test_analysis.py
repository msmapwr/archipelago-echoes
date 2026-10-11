import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from echo_dev.analysis import bundle, filtered, native_diagnostics, read_logs, state_diff, summarize


class AnalysisTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.folder = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def write_log(self, values, ending=""):
        path = self.folder / "session.jsonl"
        path.write_text("\n".join(json.dumps(value) for value in values) + "\n" + ending, encoding="utf-8")
        return path

    def record(self, kind, **values):
        return {"schema_version": 1, "session_id": "session", "kind": kind, "details": {}, **values}

    def test_truncated_last_line_preserves_prior_records(self):
        path = self.write_log([self.record("session_start"), self.record("action_rejected", details={"message": "射界"})], '{"kind":')
        records, problems = read_logs(path)
        self.assertEqual(len(records), 2)
        self.assertEqual(len(problems), 1)
        self.assertIn(":3:", problems[0])
        self.assertEqual(summarize(records, problems)["unfinished_sessions"], ["session"])

    def test_invalid_schema_shape_and_empty_directory_are_reported(self):
        path = self.write_log([[], {"schema_version": 2, "kind": "new"}, self.record("bad", details=[]), self.record("bad", simulation_seconds="invalid")])
        records, problems = read_logs(path)
        self.assertEqual(records, [])
        self.assertEqual(len(problems), 4)
        empty = self.folder / "empty"
        empty.mkdir()
        self.assertTrue(read_logs(empty)[1])

    def test_correlation_filters_preserve_physical_order(self):
        records = [self.record("event.weapon_fired", details={"order_id": "order1", "shot_id": "shot1"}, level="info"), self.record("event.gun_projectile_impact", details={"order_id": "order1", "shot_id": "shot1"}, level="warning"), self.record("event.weapon_fired", details={"order_id": "order2", "shot_id": "shot2"}, level="info")]
        self.assertEqual(len(filtered(records, order="order1", shot="shot1")), 2)
        self.assertEqual(filtered(records, kind="impact", level="warning"), [records[1]])
        self.assertEqual(filtered(records, session="other"), [])
        self.assertEqual(filtered(records, order="absent"), [])

    def test_summary_tracks_each_session_and_latest_state(self):
        records = [self.record("checkpoint", state={"ammo": 6}), self.record("checkpoint", state={"ammo": 5}), self.record("session_end"), self.record("session_start", session_id="second")]
        summary = summarize(records, [])
        self.assertEqual(summary["latest_states"]["session"], {"ammo": 5})
        self.assertEqual(summary["unfinished_sessions"], ["second"])

    def test_recursive_diff_includes_added_removed_and_changed(self):
        changes = state_diff({"gun": {"ammo": 6}, "old": True}, {"gun": {"ammo": 5}, "new": True})
        self.assertEqual([value["path"] for value in changes], ["gun.ammo", "new", "old"])
        self.assertEqual(state_diff({"x": 1}, {"x": 1}), [])

    def test_native_errors_are_detected_without_working_autoload(self):
        (self.folder / "engine.log").write_text("SCRIPT ERROR: Parse Error: fail\nWARNING: existing\n", encoding="utf-8")
        result = native_diagnostics(self.folder)
        self.assertEqual(len(result["errors"]), 1)
        self.assertEqual(result["errors"][0]["line"], 1)
        self.assertEqual(len(result["warnings"]), 1)

    def test_bundle_excludes_settings_secrets_and_refuses_overwrite(self):
        (self.folder / "manifest.json").write_text('{"schema_version":1}')
        (self.folder / "stdout.txt").write_text("log")
        (self.folder / ".env").write_text("fake_secret=do_not_export")
        (self.folder / "preferences.cfg").write_text("player state")
        destination = self.folder / "bundle.zip"
        self.assertEqual(bundle(self.folder, destination), 2)
        with zipfile.ZipFile(destination) as archive:
            self.assertEqual(sorted(archive.namelist()), ["manifest.json", "stdout.txt"])
        with self.assertRaises(FileExistsError):
            bundle(self.folder, destination)
        with self.assertRaises(ValueError):
            bundle(self.folder / "missing", self.folder / "other.zip")


if __name__ == "__main__":
    unittest.main()
