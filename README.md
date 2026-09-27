# 雷达指挥官：群岛空海战

Godot 4.7.2 游戏项目，当前已完成 P0 工程、状态与数据骨架、可交互雷达样例、P1.1 固定种子地图和世界时钟，以及 P1.2 的航行与接触观测部分。玩法方向与开发阶段见 [项目总计划](docs/plan.md) 和 [详细开发计划](docs/development-plan.md)，视觉方向见 [游戏美学计划](docs/radar_commander_aesthetic_plan.md)。P0 规则及状态见 [决策记录](docs/decisions/2026-09-27-p0-rules.md) 和 [状态流程](docs/p0-state-flow.md)；世界与航行规则见 [P1.1 说明](docs/p1-world.md) 和 [P1.2 航行说明](docs/p1-navigation.md)。

## 打开项目

1. 使用 Godot 4.7.2 标准版。
2. 在 Godot 项目管理器中导入仓库根目录的 `project.godot`。
3. 打开工程后运行主场景。点击雷达标记选择接触，按 Esc 取消，按空格暂停或继续；点击“下一次扫描”查看接触更新和失联。右侧按钮以 15° 调整航向、以 5 kn 调整航速；舰艇在模拟时间内移动，航路碰到岛屿或地图边界时自动停车。雷达标记表示最后一次观测点，失联后隐藏。当前接触仍为静止样例，战斗、敌方机动和识别尚未实现。

命令行可用时，在仓库根目录运行：

```powershell
godot --headless --path . --editor --quit
godot --headless --path . --quit-after 1
godot --headless --path . --script res://tests/p0_smoke.gd --log-file p0-test.log
godot --headless --path . --script res://tests/p1_world_smoke.gd
godot --headless --path . --script res://tests/p1_navigation_smoke.gd
```

## 目录

- 仓库根目录：Godot 工程、场景、脚本、数据与资源。
- `docs/`：玩法、开发和决策文档。
- `AGENTS.md`：本项目开发规范。

后续按详细计划逐步加入系统和资源。`addons/` 暂未引入测试插件或其他依赖。静态样例数据使用 `.tres`，缺失 ID 和错误引用由 `DataManager` 报告。`p0-test.log` 仅供本地验证，不属于项目内容。
