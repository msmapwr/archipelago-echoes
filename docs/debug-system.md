# 调试系统与 Python 开发工具

适用于群岛回波当前 Godot 4.7.2 项目。Python 需要 **3.10 或更新版本**，只用标准库，不需要 pip 安装。入口是 `tools/dev.py`；内部模块可独立复用。诊断日志是开发数据，不是玩家情报，也不是可恢复存档。

## 1. 快速开始

在项目目录打开 PowerShell，指定本机 Godot：

```powershell
$env:GODOT_BIN = 'H:\Godot_v4.7.2-stable_win64.exe'
python tools/dev.py doctor
python tools/dev.py list-tests
python tools/dev.py check
```

其他机器替换 Godot 路径。也可用 `python tools/dev.py --godot "C:\Tools\Godot\godot.exe" check`；若 Godot 已在 PATH，无需指定。入口可从其他目录执行，默认项目根目录由脚本位置确定。

`check` 顺序执行 Python 工具测试、Godot 资源导入、全部 `tests/*_smoke.gd` 回归。前置步骤失败会停止后续阶段；单个玩法回归失败仍收集其他回归结果。默认串行，避免现有 `user://` 测试配置互相竞争。

每次执行打印独立的“诊断目录”和 `summary.json` 路径。默认存放系统临时目录的 `echo-dev` 下。可以用 `--output artifacts` 指定父目录，每次仍创建唯一子目录，保留之前结果；仓库忽略 `artifacts` 与 Python 缓存，不自动删除旧报告。

## 2. 日常开发命令

全局参数放在子命令之前。

| 任务 | 命令 |
|---|---|
| 检查环境／发现测试 | `python tools/dev.py doctor` / `list-tests` |
| 只检查脚本及资源导入 | `python tools/dev.py import` |
| 运行全部玩法回归 | `python tools/dev.py test` |
| 运行火控系列 | `python tools/dev.py test --suite p2` |
| 指定回归，可重复 `--case` | `python tools/dev.py test --case debug_log --case p2_groups` |
| 图形回归 | `python tools/dev.py test --case p2_groups --graphics` |
| 启动游戏并收集日志 | `python tools/dev.py run` |
| 有限帧启动检查 | `python tools/dev.py run --headless --frames 5` |
| 运行项目内场景 | `python tools/dev.py run --scene res://scenes/unit_showcase.tscn` |
| 截图 | `python tools/dev.py capture groups-control` |
| 工具自身回归 | `python -m unittest discover -s tools/tests -v` |

工具启动时先导入资源。`test/check` 默认每个进程超时 90 秒，可用 `--timeout 120` 调整；截图默认 45 秒。交互式 `run` 默认等待玩家退出，可设置超时；无界面运行必须指定帧数或超时，避免无限等待。Ctrl+C／超时只终止本工具创建的进程树，保留已有日志；不会关闭用户原有编辑器或游戏。

测试通过必须同时满足：正常退出、没有脚本／解析／原生 ERROR 或 FAIL、存在 `smoke ... passed` 标记。**Godot 退出码 0 不能单独证明测试通过。** Warning 单独计入报告，已有未使用信号／seed 命名告警不被伪装为零告警。

截图模式还支持 `menu`、`preparation`、`settings`、`generation`、`tutorial`、`background`、`harbor`、`harbor-east`、`game`、`damage`、`archive`、`fire-control`、`fire-archive`、`lead-control`、`lead-archive`、`projectile`、`splash`、`splash-archive`、`lock-control`、`ammo-impact`、`groups-archive`、`library`、`guide-return`、`sortie`、`flight-nav`。生成器完成标记和 PNG 文件检查均成功才算通过。

## 3. 运行报告结构

```text
test-<UTC>-<唯一编号>/
  manifest.json          # 项目路径、Git 提交、分支、工作区状态
  summary.json           # 总结与各阶段结果，requested_cases 表示请求范围
  import/
    stdout.txt / stderr.txt / engine.log / result.json
  p2_groups/
    stdout.txt / stderr.txt / engine.log / result.json
    debug/echo-<会话编号>.jsonl
```

运行游戏对应 `game/`，截图对应 `capture/<模式>.png`，工具测试对应 `python-tests/`。`result.json` 包含实际参数数组、退出码、耗时、超时／中断／启动错误、成功标记、原生错误和告警。报告不是性能基准，不能仅据一次耗时判断性能提升。

测试脚本可通过主动设置测试配置改变自身进程的设置；工具不会备份、覆盖或删除玩家存档。现有 smoke 按已有项目方式运行，调试日志完全独立于玩家配置。诊断报告默认临时目录，重要复现请主动打包保存。

## 4. Godot 内的日志

`DebugLog` 自动加载，日志路径会在 Godot 输出中显示。编辑器直接 F5 也会写入：

- `user://debug/echo-<UTC>-<PID>-<启动计数>.jsonl`：独立会话结构日志。
- `user://debug/engine.log`：Godot 原生解析错误、运行时错误、告警及调用位置。引擎按配置保留最多 5 个文件。

Windows 的 `user://` 通常在 `%APPDATA%\Godot\app_userdata\<项目名称>`；以 Godot 实际输出路径为准。Python 运行时将 JSONL 和原生日志重定向到本次诊断目录。

日志覆盖：

- 会话开始／正常结束、引擎版本、日志等级、模拟时间、单调时间、严格递增记录编号与场景重开编号。
- 所有 EventBus 事件，保持原模拟时间，包括跨大时间步的真实弹着时间；指派／炮弹／炮组编号可串联。
- MissionController 成功／拒绝，包含原因、调用栈和状态；模式拒绝、数据目录错误、导航拒绝、世界生成与倍速变化。
- 按钮／选项实际信号、目标查看、档案与图鉴开关；支持的键盘事件，以及 **F3 手动现场快照**。
- 关键事件及操作的状态快照，每 2 秒真实时间一次周期快照。暂停时诊断仍工作，模拟资源和时间保持冻结。
- 舰体、敌舰、雷达与观测年龄、指派、锁定、炮塔、两组弹药与装填、修正、飞行炮弹及弹着、损管、飞机位置／燃油／导航、任务模式与胜利状态、FPS／静态内存。
- 当前场景、准备页阶段、港内位置／航向／航速／解缆与离港状态，以及教程记录和应用后的设置。

按钮信号监听和事件回调的执行顺序可能导致操作结果先于按钮信号记录；记录序号表示实际回调顺序。状态是该记录写入时的现场，不是整段操作的原子事务；初始化中尚未就绪的节点标为 `ready: false`。原生引擎错误不一定能进入 JSONL，应同时查看 `engine.log`。

日志以一行一个 JSON 对象保存，版本为 `schema_version: 1`，Vector2 是 `{x, y}`，嵌套快照独立序列化，不修改 EventBus 原数据或玩家档案。真实敌舰状态只存在开发日志，不进入玩家情报；共享报告前自行确认是否愿意分享本地路径和玩法信息。不收集环境变量、令牌、密码或自由文本键盘输入。

## 5. 看日志定位问题

复制工具打印的诊断目录，用下列命令：

```powershell
python tools/dev.py analyze "完整诊断目录" --tail 12
python tools/dev.py analyze "完整诊断目录" --kind action_rejected
python tools/dev.py analyze "完整诊断目录" --order fire_control.001
python tools/dev.py analyze "完整诊断目录" --shot deck_gun.001
python tools/dev.py analyze "完整诊断目录" --json
```

也可直接传单个 JSONL 文件，并用 `--session` 限定会话、`--level warning` 限定等级。筛选只影响时间线，不隐藏完整会话的结束记录和最后状态。命令／炮弹编号会在重开后复用，跨会话查看必须结合 session_id；同一会话多次重开时结合 scenario_sequence 和模拟时间识别。

分析器保留崩溃前已写出的有效行，对损坏行报告文件及行号；读取问题／原生错误返回非零。**没有 session_end 并不能单独证明崩溃**：强制终止、日志等级过滤或预算用尽也可能造成缺失。分析器同时扫描原生日志定位脚本错误；完整调用栈在原始 engine/stdout/stderr 文件中。

推荐排查顺序：

1. 查看 `summary.json` 是否失败、退出码／超时；查 engine.log 的首个错误及调用位置。
2. 查最后一条 `action_rejected`：原因和栈能说明哪个入口拒绝了操作。
3. 用指派／炮弹编号串联指派、发射、校射、弹着、失锁、清理；核对模拟时间与炮组。
4. 对照该点状态：舰桥权限、暂停、观测时效、射程射界、锁定、资源、装填或损管。
5. 看后续周期快照判断程序仍在运行，或在最后一次操作后停止。用相同测试／截图模式复测，比较修改前后日志。

比较两次运行的最后状态，每侧选单个会话文件：

```powershell
python tools/dev.py compare "修改前.jsonl" "修改后.jsonl"
```

输出增加／移除／改变的字段；FPS、内存和最后采样时刻自然可能不同，不应误认为玩法回归。此工具是状态比较，未实现自动输入回放／存档还原。

## 6. 保存诊断包

```powershell
python tools/dev.py bundle "工具打印的诊断目录" "D:\reports\echo-debug.zip"
```

源目录必须带有效 `manifest.json`。只收集诊断 JSON、JSONL、原生输出与截图；不打包源码、`.env`、玩家配置或存档。目标文件已存在时拒绝覆盖。然后将 ZIP 或需要的日志提供给开发者即可复盘。编辑器直接 F5 的日志可以先复制并直接 `analyze`；`bundle` 专用于 Python 工具建立的报告目录。

## 7. 日志控制与扩展

编辑器启动前可设置环境变量：

| 变量 | 默认／用途 |
|---|---|
| `ECHO_DEBUG_DIR` | `user://debug`；自定义必须绝对路径 |
| `ECHO_DEBUG_LEVEL` | debug 构建为 debug，其他构建为 info；debug/info/warning/error/off |
| `ECHO_DEBUG_MAX_MB` | 每个结构日志默认 32 MB，范围 1–1024 MB |

Python 工具默认启用 debug，可用 `--debug-level info` 或 `--debug-level off` 改变，`--log-budget-mb 64` 调整预算。原生 Godot 文件日志不受 JSONL 的 off 控制。`debug_log` smoke 专门验证已启用的日志，执行该项需 debug 等级。

写目录／文件失败时警告并停止记录，玩法继续；达到预算时追加 `log_budget_exhausted` 并停止该会话结构记录，不删除已有内容。周期快照仅在 debug 等级记录，关键操作为 info，拒绝为 warning，数据加载错误为 error。日志同步 flush 以保留崩溃前最后操作，长时间性能测量可关闭结构日志；它不是无成本的遥测服务。

新增玩法使用以下接口，禁止把真实诊断状态复制到玩家情报：

```gdscript
EventBus.record("new_gameplay_event", {"order_id": order_id, "reason": reason})
DebugLog.write("warning", "subsystem_rejected", {"reason": reason}, true)
DebugLog.checkpoint("before_new_operation")
```

`DebugLog.write(level, kind, details, include_state, simulation_seconds)` 的最后时间参数默认当前时钟，真实弹着等子步事件可显式传入。要增加状态字段，在 `debug_log.gd::snapshot` 的只读字段表中添加。新增 `tests/<名称>_smoke.gd` 使用非零退出／`FAIL:` 标记和成功 `smoke ... passed`，Python 工具自动发现，不需复制 PowerShell 测试循环。

Python 可复用模块：`runner.execute` 负责进程、超时、日志和结果；`select_tests` 负责安全发现；`analysis.read_logs/filtered/summarize/state_diff` 负责分析；`bundle` 负责有限收集。均以 Path／参数数组交互，不用 shell 拼接。

敌舰撤离切片新增 `capture enemy-withdrawal`；用 `analyze <目录> --kind enemy_withdrawal` 查询触发记录，快照中的 `MissionController.enemy_navigation` 显示威胁记忆、撤离与阻挡状态。玩家采样情报通过 `event.contact_maneuver_observed` 查询。

## 8. 验收入口

| 行为 | 回归证据 |
|---|---|
| 假成功退出、缺标记、stderr／原生错误、超时、启动失败、空目录与参数安全 | `tools/tests/test_runner.py::RunnerTests` |
| 损坏日志、版本／结构、命令关联、多会话、最后状态、状态差异、打包排除与防覆盖 | `tools/tests/test_analysis.py::AnalysisTests` |
| 非法命令／场景、前置失败中止、截图缺失、筛选结束状态、比较会话边界 | `tools/tests/test_cli.py::CliTests` |
| 会话／时间／嵌套序列化、拒绝栈、UI／暂停／F3、不修改玩法和历史、关闭／off／目录失败／预算 | `tests/debug_log_smoke.gd` |
| 原有玩法兼容、工具真实端到端链路 | `tools/dev.py check`、图形 smoke、capture/analyze/bundle |

工具不会自动提交、推送或部署，不修改 Git remote。检查通过之后仍需要审查 diff、更新 CHANGELOG，再按项目流程提交。

2026-10-11 在 Windows、Python 3.11.15、Godot 4.7.2 验证：22 项 Python 测试、资源导入及全部 23 项 Godot smoke 通过；另通过 debug_log/menu_ui/p2_groups/mission_guidance 四项图形回归、五帧启动、火控与港口截图、日志分析、同状态比较和 ZIP 打包。debug_log 的目录失败与预算耗尽、p0 的非法模式警告属于主动覆盖的失败路径，保留在报告中。
