"""Reproducible M0 source snapshots and Windows release acceptance."""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import shutil
import zipfile

from .runner import execute, godot_arguments, save_json

SOURCE_ROOTS = ("project.godot", "export_presets.cfg", "scenes", "scripts", "shaders", "data", "tests", "tools")
FORBIDDEN_ROOTS = {"tests", "tools", "docs", ".agents", ".git", "artifacts", "build", "exports"}


def copy_source(project: Path, destination: Path) -> dict:
    """Create a fresh cache-free source tree; never overwrite a destination."""
    project = project.resolve()
    destination = destination.resolve()
    if destination == project or project.is_relative_to(destination) or destination.exists():
        raise ValueError("source snapshot destination must be new and separate")
    files = {}
    for name in SOURCE_ROOTS:
        root = project / name
        candidates = root.rglob("*") if root.is_dir() else [root]
        for path in candidates:
            relative = path.relative_to(project)
            if any(part.startswith(".") or part == "__pycache__" for part in relative.parts) or path.suffix == ".pyc":
                continue
            if not path.resolve().is_relative_to(project):
                raise ValueError("source snapshot cannot follow paths outside project")
            if path.is_file():
                files[relative.as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    if not {"project.godot", "export_presets.cfg"}.issubset(files):
        raise ValueError("snapshot requires project and export preset")
    destination.mkdir(parents=True, exist_ok=False)
    for name in files:
        output = destination / name
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(project / name, output)
    save_json(destination.parent / (destination.name + "-sources.json"), files)
    return files


def audit_pack(path: Path) -> dict:
    with zipfile.ZipFile(path) as package:
        names = package.namelist()
        forbidden = [name for name in names if name.split("/")[0] in FORBIDDEN_ROOTS or Path(name).suffix.lower() in {".md", ".py", ".env"}]
        required = ["scenes/main/console_shell.tscn", "data/ships/escort_carrier.tres"]
        missing = [name for name in required if name not in names and name + ".remap" not in names]
        bad = package.testzip()
    return {"passed": not forbidden and not missing and bad is None, "entries": len(names), "forbidden": forbidden, "missing": missing, "bad_crc_entry": bad}


def export_windows(binary: Path, project: Path, folder: Path, timeout: float = 120) -> dict:
    folder.mkdir(parents=True, exist_ok=True)
    output = folder / "windows"
    output.mkdir(exist_ok=True)
    executable = (output / "EchoesOfTheArchipelago.exe").resolve()
    stages = []
    for name, extra in [
        ("release", ["--headless", "--export-release", "Windows Desktop", str(executable)]),
        ("pack", ["--headless", "--export-pack", "Windows Desktop", str((folder / "resources.zip").resolve())]),
    ]:
        result = execute(godot_arguments(binary, project, folder / name, extra), project, folder / name, timeout=timeout)
        stages.append(result)
        if not result["passed"]: break
    audit = {"passed": False}
    if all(stage["passed"] for stage in stages):
        audit = audit_pack(folder / "resources.zip")
    artifacts_ok = executable.is_file() and executable.with_suffix(".pck").is_file()
    if artifacts_ok and audit["passed"] and all(stage["passed"] for stage in stages):
        for name, flags in [("headless", ["--headless"]), ("graphics", [])]:
            log = folder / ("installed-" + name)
            result = execute([str(executable), "--log-file", str((log / "engine.log").resolve()), *flags, "--", "--verify-install"], output, log, timeout=45, marker=re.compile("Installation verification passed"))
            stages.append(result)
            if not result["passed"]: break
    passed = artifacts_ok and audit["passed"] and len(stages) == 4 and all(stage["passed"] for stage in stages)
    files = {path.name: {"bytes":path.stat().st_size, "sha256":hashlib.sha256(path.read_bytes()).hexdigest()} for path in output.iterdir() if path.is_file()}
    summary = {"passed":passed, "preset":"Windows Desktop", "package":str(output.resolve()), "files":files, "audit":audit, "results":stages}
    save_json(folder / "summary.json", summary)
    if passed:
        shutil.make_archive(str(folder / "EchoesOfTheArchipelago-Windows"), "zip", output)
    return summary
