"""Read versioned JSONL logs, including the surviving prefix of a crashed write."""
from __future__ import annotations

from collections import Counter
import json
from pathlib import Path
import zipfile

from .runner import ENGINE_ERROR


def read_logs(path: Path) -> tuple[list[dict], list[str]]:
    files = [path] if path.is_file() else sorted(path.rglob("*.jsonl"))
    records, problems = [], []
    for file in files:
        with file.open(encoding="utf-8", errors="replace") as stream:
            for number, line in enumerate(stream, 1):
                if not line.strip():
                    continue
                try:
                    value = json.loads(line)
                    if not isinstance(value, dict) or value.get("schema_version") != 1 or not isinstance(value.get("kind"), str):
                        raise ValueError("unknown schema or invalid record")
                    if not isinstance(value.get("details", {}), dict) or not isinstance(value.get("state", {}), dict):
                        raise ValueError("details/state must be objects")
                    if not isinstance(value.get("simulation_seconds", 0), (int, float)):
                        raise ValueError("simulation_seconds must be numeric")
                    records.append(value)
                except (ValueError, TypeError) as error:
                    problems.append(f"{file}:{number}: {error}")
    if not files:
        problems.append(f"没有 JSONL 日志：{path}")
    return records, problems


def filtered(records: list[dict], *, session: str | None = None, order: str | None = None,
             shot: str | None = None, kind: str | None = None, level: str | None = None) -> list[dict]:
    return [record for record in records
            if (not session or record.get("session_id") == session)
            and (not order or record.get("details", {}).get("order_id") == order)
            and (not shot or record.get("details", {}).get("shot_id") == shot)
            and (not kind or kind in record.get("kind", ""))
            and (not level or record.get("level") == level)]


def summarize(records: list[dict], problems: list[str]) -> dict:
    sessions = sorted({str(record.get("session_id", "unknown")) for record in records})
    latest = {}
    for record in records:
        if "state" in record:
            latest[str(record.get("session_id", "unknown"))] = record["state"]
    return {"records": len(records), "sessions": sessions, "levels": dict(Counter(record.get("level", "unknown") for record in records)),
            "kinds": dict(Counter(record["kind"] for record in records)), "problems": problems,
            "unfinished_sessions": [session for session in sessions if not any(record.get("session_id") == session and record["kind"] == "session_end" for record in records)],
            "latest_states": latest}


def state_diff(before: dict, after: dict, prefix: str = "") -> list[dict]:
    changes = []
    for key in sorted(set(before) | set(after)):
        path = f"{prefix}.{key}" if prefix else key
        if key not in before:
            changes.append({"path": path, "change": "added", "after": after[key]})
        elif key not in after:
            changes.append({"path": path, "change": "removed", "before": before[key]})
        elif isinstance(before[key], dict) and isinstance(after[key], dict):
            changes.extend(state_diff(before[key], after[key], path))
        elif before[key] != after[key]:
            changes.append({"path": path, "change": "changed", "before": before[key], "after": after[key]})
    return changes


def bundle(source: Path, destination: Path) -> int:
    source = source.resolve()
    manifest = source / "manifest.json"
    if not manifest.is_file():
        raise ValueError("bundle 需要工具生成的运行目录及 manifest.json")
    metadata = json.loads(manifest.read_text(encoding="utf-8"))
    if not isinstance(metadata, dict) or metadata.get("schema_version") != 1:
        raise ValueError("诊断 manifest 版本无效")
    allowed = {"manifest.json", "result.json", "summary.json", "stdout.txt", "stderr.txt", "engine.log"}
    files = [file for file in source.rglob("*") if file.is_file() and not file.is_symlink()
             and (file.name in allowed or file.suffix in {".jsonl", ".png"})]
    if not files:
        raise ValueError("诊断目录为空")
    # Exclusive creation preserves a previously exported diagnostic bundle.
    with zipfile.ZipFile(destination, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for file in files:
            if not file.resolve().is_relative_to(source):
                continue
            archive.write(file, file.relative_to(source).as_posix())
    return len(files)


def native_diagnostics(path: Path) -> dict:
    """Native parser/runtime errors remain in engine logs even if autoload fails."""
    folder = path if path.is_dir() else path.parent
    errors, warnings = [], []
    files = list(folder.rglob("*.log")) + list(folder.rglob("stdout.txt")) + list(folder.rglob("stderr.txt"))
    for file in files:
        with file.open(encoding="utf-8", errors="replace") as stream:
            for number, line in enumerate(stream, 1):
                if ENGINE_ERROR.search(line):
                    errors.append({"file": str(file), "line": number, "message": line.strip()})
                elif "WARNING:" in line:
                    warnings.append({"file": str(file), "line": number, "message": line.strip()})
    return {"errors": errors, "warnings": warnings}
