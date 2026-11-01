import tempfile
from pathlib import Path
import unittest
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import zipfile
from echo_dev.foundation import copy_source, audit_pack

class FoundationTests(unittest.TestCase):
    def test_fresh_snapshot_preserves_source_and_excludes_cache(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)/"source"; root.mkdir()
            (root/"project.godot").write_text("config_version=5")
            (root/"export_presets.cfg").write_text("preset")
            (root/".godot").mkdir(); (root/".godot/private").write_text("cache")
            target=Path(folder)/"snapshot"
            manifest=copy_source(root,target)
            self.assertEqual((target/"project.godot").read_text(),"config_version=5")
            self.assertIn("project.godot",manifest)
            self.assertFalse((target/".godot").exists())
            with self.assertRaises(ValueError): copy_source(root,target)
    def test_pack_rejects_developer_files(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/"pack.zip"
            with zipfile.ZipFile(path,"w") as z:
                z.writestr("scenes/main/console_shell.tscn","scene")
                z.writestr("data/ships/escort_carrier.tres","ship")
            self.assertTrue(audit_pack(path)["passed"])
            with zipfile.ZipFile(path,"a") as z: z.writestr("tests/cheat.gd","test")
            self.assertFalse(audit_pack(path)["passed"])
    def test_missing_runtime_resources_fail_audit(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/"empty.zip"
            with zipfile.ZipFile(path,"w"): pass
            self.assertFalse(audit_pack(path)["passed"])
