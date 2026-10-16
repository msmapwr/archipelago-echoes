"""One command line interface for local development, without shell interpolation."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import platform
import re
import subprocess
import sys

from .analysis import bundle, filtered, native_diagnostics, read_logs, state_diff, summarize
from .runner import discover_tests, execute, find_godot, godot_arguments, new_run, save_json, select_tests, PASS_MARKER

CAPTURE_MODES = ("menu", "preparation", "settings", "generation", "tutorial", "background", "harbor", "harbor-east", "game", "chart-wide", "chart-stale", "chart-silent", "damage", "archive", "fire-control", "fire-archive", "lead-control", "lead-archive", "projectile", "splash", "splash-archive", "lock-control", "ammo-impact", "groups-control", "groups-archive", "enemy-withdrawal", "library", "guide-return", "sortie", "flight-nav")


def positive(value: str) -> float:
    number = float(value)
    if not 0 < number < float("inf"):
        raise argparse.ArgumentTypeError("必须是有限正数")
    return number


def positive_int(value: str) -> int:
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("必须是正整数")
    return number


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description="群岛回波：运行、测试、截图及诊断（Python 标准库）")
    result.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    result.add_argument("--godot", help="Godot executable; defaults to GODOT_BIN or PATH")
    result.add_argument("--output", type=Path, help="artifacts parent; every invocation creates a unique subdirectory")
    result.add_argument("--debug-level", choices=("debug", "info", "warning", "error", "off"), default="debug")
    result.add_argument("--log-budget-mb", type=positive_int, default=32)
    commands = result.add_subparsers(dest="command", required=True)
    commands.add_parser("doctor", help="检查 Godot、项目与测试目录")
    commands.add_parser("list-tests", help="列出可执行 smoke 测试")
    commands.add_parser("import", help="导入资源并检查脚本")
    for name in ("test", "check"):
        command = commands.add_parser(name, help="运行测试" if name == "test" else "Python 工具测试 → 导入 → Godot 回归")
        command.add_argument("--suite", choices=("all", "p2"), default="all")
        command.add_argument("--case", action="append", help="case name without _smoke.gd; repeatable")
        command.add_argument("--graphics", action="store_true")
        command.add_argument("--timeout", type=positive, default=90, help="seconds per process")
    run = commands.add_parser("run", help="启动游戏，退出／Ctrl+C 后保存诊断报告")
    run.add_argument("--headless", action="store_true")
    run.add_argument("--frames", type=positive_int)
    run.add_argument("--timeout", type=positive)
    run.add_argument("--scene", help="project-local res:// scene")
    capture = commands.add_parser("capture", help="生成指定 CRT 场景截图")
    capture.add_argument("mode", choices=CAPTURE_MODES)
    capture.add_argument("--timeout", type=positive, default=45)
    capture.add_argument("--resolution", choices=("1280x720", "1600x900", "1920x1080"), default="1600x900")
    capture.add_argument("--weak-crt", action="store_true", help="仅在截图进程内弱化 CRT，不保存玩家设置")
    analyze = commands.add_parser("analyze", help="分析会话／炮弹／命令日志，可处理崩溃后的残缺行")
    analyze.add_argument("path", type=Path)
    for option in ("session", "order", "shot", "kind", "level"):
        analyze.add_argument("--" + option)
    analyze.add_argument("--tail", type=positive_int, default=20)
    analyze.add_argument("--json", action="store_true")
    compare = commands.add_parser("compare", help="比较两份 JSONL 日志的最后状态")
    compare.add_argument("before", type=Path)
    compare.add_argument("after", type=Path)
    export = commands.add_parser("bundle", help="打包工具生成的诊断目录，不包含项目源码或玩家存档")
    export.add_argument("path", type=Path)
    export.add_argument("destination", type=Path)
    return result


def report(label: str, result: dict) -> None:
    print(f"{'PASS' if result['passed'] else 'FAIL'} {label} ({result['duration_seconds']:.3f}s, exit={result['returncode']}, warnings={len(result['warnings'])})", flush=True)
    for error in result["errors"][:8]:
        print("  " + error)
    if result["timed_out"]:
        print("  超时，已终止本工具创建的进程树")
    if not result["marker_ok"]:
        print("  缺少测试成功标记")
    if result["launch_error"]:
        print("  " + result["launch_error"])


def import_project(binary: Path, project: Path, run: Path, timeout: float = 90, environment: dict | None = None) -> dict:
    folder = run / "import"
    result = execute(godot_arguments(binary, project, folder, ["--headless", "--editor", "--quit"]), project, folder, timeout=timeout, environment=environment)
    report("import", result)
    return result


def analyze_logs(args: argparse.Namespace) -> int:
    if not args.path.exists():
        raise ValueError("诊断路径不存在")
    records, problems = read_logs(args.path)
    selected = filtered(records, session=args.session, order=args.order, shot=args.shot, kind=args.kind, level=args.level)
    summary = summarize(records, problems)
    summary["selected_records"] = len(selected)
    summary["timeline"] = selected[-args.tail:]
    summary["native_diagnostics"] = native_diagnostics(args.path)
    if args.json:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    else:
        print(f"记录 {summary['records']} · 会话 {len(summary['sessions'])} · 等级 {summary['levels']}")
        for issue in problems:
            print("日志问题：" + issue)
        for error in summary["native_diagnostics"]["errors"]:
            print(f"引擎错误 {error['file']}:{error['line']} {error['message']}")
        for session in summary["unfinished_sessions"]:
            print("未见正常结束记录（可能崩溃／强制终止／等级过滤）：" + session)
        for record in summary["timeline"]:
            details = json.dumps(record.get("details", {}), ensure_ascii=False)
            print(f"#{record.get('sequence', '?')} T+{record.get('simulation_seconds', 0):.3f} {record.get('level', '?')} {record['kind']} {details}")
        for session, state in summary["latest_states"].items():
            print("最后状态 " + session + ": " + json.dumps(state, ensure_ascii=False))
    return 1 if problems or summary["native_diagnostics"]["errors"] else 0


def main(arguments: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    command_parser = parser()
    args = command_parser.parse_args(arguments)
    try:
        if args.command == "analyze":
            return analyze_logs(args)
        if args.command == "bundle":
            count = bundle(args.path, args.destination)
            print(f"已打包 {count} 个诊断文件：{args.destination.resolve()}")
            return 0
        if args.command == "compare":
            states = []
            for path in (args.before, args.after):
                records, issues = read_logs(path)
                if issues:
                    raise ValueError("; ".join(issues))
                values = [record["state"] for record in records if "state" in record]
                if not values:
                    raise ValueError(f"没有状态快照：{path}")
                sessions = {record.get("session_id") for record in records}
                if len(sessions) != 1:
                    raise ValueError("compare 每侧需选择单个会话 JSONL 文件")
                states.append(values[-1])
            print(json.dumps(state_diff(*states), ensure_ascii=False, indent=2))
            return 0
        project = args.project.expanduser().resolve()
        if not (project / "project.godot").is_file():
            raise ValueError(f"不是 Godot 项目：{project}")
        if args.command == "list-tests":
            print("\n".join(discover_tests(project)))
            return 0
        cases = select_tests(project, args.suite, args.case) if args.command in ("test", "check") else []
        binary = find_godot(args.godot)
        if args.command == "doctor":
            version = subprocess.run([str(binary), "--version"], capture_output=True, text=True, timeout=10, creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0)
            print(json.dumps({"python": platform.python_version(), "project": str(project), "godot": str(binary), "godot_version": version.stdout.strip(), "tests": discover_tests(project)}, ensure_ascii=False, indent=2))
            return 0 if version.returncode == 0 else 1
        if args.command == "run" and args.headless and not args.frames and not args.timeout:
            raise ValueError("headless run 需要 --frames 或 --timeout，避免无限运行")
        if args.command == "run" and args.scene:
            scene = args.scene.removeprefix("res://")
            candidate = (project / scene).resolve()
            if not candidate.is_relative_to(project) or not candidate.is_file() or candidate.suffix != ".tscn":
                raise ValueError("--scene 必须是项目内已有 .tscn 场景")
            args.scene = "res://" + candidate.relative_to(project).as_posix()
        run = new_run(project, args.command, args.output)
        print("诊断目录：" + str(run), flush=True)
        results = []
        diagnostic_env = {"ECHO_DEBUG_LEVEL": args.debug_level, "ECHO_DEBUG_MAX_MB": str(args.log_budget_mb)}
        if args.command == "check":
            folder = run / "python-tests"
            result = execute([sys.executable, "-m", "unittest", "discover", "-s", str(project / "tools/tests"), "-v"], project, folder, timeout=args.timeout, environment={"PYTHONPATH": str(project / "tools")}, marker=re.compile(r"\bOK\b"))
            results.append(result)
            report("python tests", result)
        if all(result["passed"] for result in results):
            results.append(import_project(binary, project, run, getattr(args, "timeout", None) or 90, diagnostic_env))
        if all(result["passed"] for result in results) and args.command in ("test", "check"):
            # Serial execution avoids existing user:// fixtures racing one another.
            for case in cases:
                folder = run / case
                extra = ([] if args.graphics else ["--headless"]) + ["--script", f"res://tests/{case}_smoke.gd"]
                result = execute(godot_arguments(binary, project, folder, extra), project, folder, timeout=args.timeout, marker=PASS_MARKER, environment=diagnostic_env)
                results.append(result)
                report(case, result)
                if result["interrupted"]:
                    break
        elif all(result["passed"] for result in results) and args.command == "capture":
            folder = run / "capture"
            png = folder / (args.mode + ".png")
            env = {**diagnostic_env, "CONSOLE_CAPTURE_MODE": "" if args.mode == "menu" else args.mode, "CONSOLE_CAPTURE_PATH": str(png.resolve()), "CONSOLE_CAPTURE_RESOLUTION": args.resolution, "CONSOLE_CAPTURE_WEAK_CRT": "1" if args.weak_crt else "0"}
            save_json(run / "capture-settings.json", {"mode": args.mode, "resolution": args.resolution, "weak_crt": args.weak_crt})
            result = execute(godot_arguments(binary, project, folder, ["--script", "res://tests/render_console.gd"]), project, folder, timeout=args.timeout, marker=re.compile("Console capture saved:"), environment=env)
            result["passed"] = result["passed"] and png.is_file() and png.stat().st_size > 8 and png.read_bytes()[:8] == b"\x89PNG\r\n\x1a\n"
            save_json(folder / "result.json", result)
            results.append(result)
            report("capture " + args.mode, result)
        elif all(result["passed"] for result in results) and args.command == "run":
            folder = run / "game"
            extra = ["--headless"] if args.headless else []
            if args.frames:
                extra += ["--quit-after", str(args.frames)]
            if args.scene:
                extra.append(args.scene)
            result = execute(godot_arguments(binary, project, folder, extra), project, folder, timeout=args.timeout, visible=not args.headless, environment=diagnostic_env)
            results.append(result)
            report("run", result)
        passed = bool(results) and all(result["passed"] for result in results)
        save_json(run / "summary.json", {"schema_version": 1, "passed": passed, "requested_cases": cases, "results": results})
        print("报告：" + str(run / "summary.json"))
        return 0 if passed else 1
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        command_parser.error(str(error))
        return 2
