"""Process execution, evidence collection and strict Godot result checking."""
from __future__ import annotations

import datetime as dt
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time
import uuid

ENGINE_ERROR = re.compile(r"(?:SCRIPT ERROR:|Parse Error:|^\s*ERROR:|^\s*FAIL:)", re.MULTILINE)
PASS_MARKER = re.compile(r"smoke.*passed", re.IGNORECASE)


def save_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def find_godot(explicit: str | None = None) -> Path:
    candidate = explicit or os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
    if not candidate:
        raise ValueError("找不到 Godot：使用 --godot 绝对路径，或设置 GODOT_BIN。")
    path = Path(candidate).expanduser().resolve()
    if not path.is_file():
        raise ValueError(f"Godot 可执行文件不存在：{path}")
    return path


def new_run(project: Path, command: str, output: Path | None = None) -> Path:
    parent = output or Path(tempfile.gettempdir()) / "echo-dev"
    run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    folder = parent.expanduser().resolve() / f"{command}-{run_id}"
    folder.mkdir(parents=True, exist_ok=False)
    git = {}
    for key, arguments in {"revision": ["rev-parse", "HEAD"], "branch": ["branch", "--show-current"], "status": ["status", "--short"]}.items():
        try:
            result = subprocess.run(["git", *arguments], cwd=project, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=10)
            git[key] = result.stdout.strip() if result.returncode == 0 else "unavailable"
        except (OSError, subprocess.TimeoutExpired):
            git[key] = "unavailable"
    save_json(folder / "manifest.json", {"schema_version": 1, "command": command, "utc": dt.datetime.now(dt.timezone.utc).isoformat(), "project": str(project), "git": git})
    return folder


def stop_process(process: subprocess.Popen) -> None:
    """Only terminate the process tree created by this tool."""
    if process.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
    else:
        os.killpg(process.pid, signal.SIGKILL)
    if process.poll() is None:
        process.kill()
    process.wait(timeout=10)


def execute(arguments: list[str], project: Path, folder: Path, *, timeout: float | None = 90,
            marker: re.Pattern | None = None, environment: dict[str, str] | None = None,
            visible: bool = False) -> dict:
    folder.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update({"ECHO_DEBUG_DIR": str((folder / "debug").resolve()), "ECHO_DEBUG_LEVEL": "debug"})
    env.update(environment or {})
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" and not visible else 0
    started = time.monotonic()
    returncode = None
    timed_out = interrupted = False
    launch_error = None
    stdout_path, stderr_path = folder / "stdout.txt", folder / "stderr.txt"
    # Stream to disk, rather than buffering an unbounded play session in RAM.
    with stdout_path.open("wb") as stdout, stderr_path.open("wb") as stderr:
        try:
            process = subprocess.Popen(arguments, cwd=project, stdout=stdout, stderr=stderr,
                                       env=env, creationflags=flags, start_new_session=os.name != "nt")
            try:
                returncode = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                stop_process(process)
                returncode = process.returncode
            except KeyboardInterrupt:
                interrupted = True
                stop_process(process)
                returncode = process.returncode
        except OSError as error:
            launch_error = str(error)
    text = stdout_path.read_text(encoding="utf-8", errors="replace") + "\n" + stderr_path.read_text(encoding="utf-8", errors="replace")
    engine_log = folder / "engine.log"
    if engine_log.is_file():
        text += "\n" + engine_log.read_text(encoding="utf-8", errors="replace")
    errors = list(dict.fromkeys(line.strip() for line in text.splitlines() if ENGINE_ERROR.search(line)))
    warnings = list(dict.fromkeys(line.strip() for line in text.splitlines() if "WARNING:" in line))
    marker_ok = marker is None or bool(marker.search(text))
    passed = returncode == 0 and not timed_out and not interrupted and not launch_error and not errors and marker_ok
    result = {"schema_version": 1, "arguments": arguments, "returncode": returncode, "duration_seconds": round(time.monotonic() - started, 3),
              "passed": passed, "timed_out": timed_out, "interrupted": interrupted, "launch_error": launch_error,
              "marker_ok": marker_ok, "errors": errors, "warnings": warnings, "artifacts": str(folder.resolve())}
    save_json(folder / "result.json", result)
    return result


def godot_arguments(binary: Path, project: Path, folder: Path, extra: list[str]) -> list[str]:
    return [str(binary), "--path", str(project), "--log-file", str((folder / "engine.log").resolve()), *extra]


def discover_tests(project: Path) -> list[str]:
    return sorted(path.stem.removesuffix("_smoke") for path in (project / "tests").glob("*_smoke.gd"))


def select_tests(project: Path, suite: str, cases: list[str] | None) -> list[str]:
    available = discover_tests(project)
    selected = cases or ([name for name in available if name.startswith("p2_")] if suite == "p2" else available)
    unknown = sorted(set(selected) - set(available))
    if unknown:
        raise ValueError("未知测试：" + ", ".join(unknown))
    if not selected:
        raise ValueError("没有可执行的 smoke 测试")
    return list(dict.fromkeys(selected))
