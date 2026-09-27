# 雷达指挥官：群岛空海战

Godot 4.x 游戏项目，当前已完成 P0 工程、状态与数据骨架，以及可交互雷达样例。玩法方向与开发阶段见 [项目总计划](docs/plan.md) 和 [详细开发计划](docs/development-plan.md)。P0 规则及状态见 [决策记录](docs/decisions/2026-09-27-p0-rules.md) 和 [状态流程](docs/p0-state-flow.md)。

## 打开项目

1. 安装 Godot 4.x 标准版。
2. 在 Godot 项目管理器中导入 `radar-commander/project.godot`。
3. 打开工程后运行主场景。点击雷达标记选择接触，按 Esc 取消，按空格暂停或继续；点击“下一次扫描”查看接触更新和失联。当前是模拟接触样例，海空战斗尚未实现。

命令行可用时，在仓库根目录运行：

```powershell
godot --headless --path radar-commander --editor --quit
godot --headless --path radar-commander --quit-after 1
godot --headless --path radar-commander --script res://tests/p0_smoke.gd --log-file p0-test.log
```

## 目录

- `radar-commander/`：Godot 工程、场景、脚本、数据与资源。
- `docs/`：玩法、开发和决策文档。
- `AGENTS.md`：本项目开发规范。

后续按详细计划逐步加入系统和资源。`addons/` 暂未引入测试插件或其他依赖。静态样例数据使用 `.tres`，缺失 ID 和错误引用由 `DataManager` 报告。`p0-test.log` 仅供本地验证，不属于项目内容。
