# 母舰航点 Large 验证报告

2026-10-18，北京时间。基线 `3225a38`，Windows / Godot 4.7.2 Compatibility；引擎 `H:\Godot_v4.7.2-stable_win64.exe`。使用项目现有 SceneTree smoke 和 Python 工具，没有新增测试框架或依赖。

## 已执行并通过

诊断根目录 `%TEMP%\echo-ship-route-qa-20261018`；每次的 `summary.json`、引擎日志与结构日志可追溯。

| 范围 | 证据 |
|---|---|
| 资源导入、27 项 Godot、23 项 Python | `check-20261018T040656Z-89b4ae1f/summary.json` 全部通过 |
| 配置／起飞、航点、飞机导航、M1 UI、任务指引图形模式 | `test-20261018T040539Z-1e77cc87/summary.json` 五项通过 |
| 雷达图形模式 | `test-20261018T040355Z-65e502d4/summary.json` 通过 |
| 最终航点图形复验 | `test-20261018T040820Z-0b4a8ef4/summary.json`，包括补充的 2 m 余深断言；原有真实鼠标／键盘路径仍通过 |
| 三分辨率与 CRT | 1280×720、1600×900、1920×1080 的航点界面各包含默认与弱 CRT；另有抵达、生成、飞机导航。最终标签位置调整后补拍 1280 弱化／1600 默认及抵达。共 12 张成功 PNG，均逐一核对实际尺寸 |

命令（实际执行另加 `--output`）：

```powershell
$env:GODOT_BIN = 'H:\Godot_v4.7.2-stable_win64.exe'
python tools/dev.py check
python tools/dev.py test --graphics --case m0_m1_hardening --case ship_route --case flight_navigation --case m1_ui --case mission_guidance
python tools/dev.py capture ship-route --resolution 1280x720 --weak-crt
python tools/dev.py capture ship-route-arrived --resolution 1600x900
```

新回归 `tests/ship_route_smoke.gd` 验证：非法坐标／过近／陆地／穿岛／余深不足的拒绝与原命令保留、暂停排队、ETA、大步抵达截断、抵达单次记录、手动接管与旧标记清理、1×/10×、升空托管、配置停车及空中请求停车、舰上／空中沉舰、运行危险中断、重开，以及真实 CRT 鼠标、圆外拒绝、键盘、档案模态和任务指引。

## 开发者画面检查

已查看三分辨率默认／弱 CRT 合成图、1280 最终弱化原图、抵达和飞机导航画面。航点与敌情回波独立，用方框及 `WP` 标记；导航操作和取消按钮可见，说明／距离／ETA 可读，保留告警优先级。未知目标仍是通用回波，不借航点显示敌方隐藏数据。

修改前参考：[舰桥](reference/bridge-qa/game.webp)。最终留档：[执行航点](reference/ship-route-qa/route.webp)、[1280 弱 CRT](reference/ship-route-qa/route-weak.webp)、[抵达停车](reference/ship-route-qa/arrived.webp)。仓库为压缩 WebP 展示副本；原始 PNG 与截图设置留于诊断目录。

## 已执行但曾失败，已修复复验

- 首次全量的 `m0_m1_hardening` 检出新增控件挤出起飞按钮（`check-20261018T040443Z-7a2e68b5`）。仅在舰桥显示航点编辑控件，配置页保持起飞优先；原断言未改动。五项图形及最终全量复验通过。
- 第一次新增截图入口使用了错误局部变量作用域，脚本解析失败（`capture-20261018T040600Z-b725451a`）。修正截图脚本控制器引用后所有请求的截图通过，未屏蔽解析检查。
- 航点 smoke 有一个故意无效操舵命令产生的预期警告；全量原有 debug_log 两个、p0 四个预期警告继续保留。未宣称零告警。

## 未执行／限制

- 真人完整航行、长时间交战与离舰决策压力；自动化通过不能替代玩家体验结论。
- 跨硬件性能基准和长时间内存稳定性；本批未更改 CRT Shader，未宣称性能提升。
- 多航点、自动绕岛、动态避碰、真实舵速和减速距离。本批明确采用现有瞬时航向与停车模型，直线路径最多 20 m 采样。

工作区原有 `AGENTS.md` 删除、`.agents/` 及 SVG 导入文件保留，不纳入提交。使用方式见 [母舰航点说明](ship-navigation.md)。
