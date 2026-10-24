# 多航点航线 Large 验证报告

日期：2026-10-24，北京时间。基线 `b2ebf8a`。Windows / Godot 4.7.2 Compatibility，引擎 `H:\Godot_v4.7.2-stable_win64.exe`。

## 交付边界

最多 8 个待执行点，玩家手动规划绕岛；逐段吃水加 2 m 校验、追加／撤回末点、编号航段、合计航程／ETA、逐段模拟与终点停车。保持旧单航点 API，飞机导航独立；不包含自动路径规划、真实转向／刹车或动态避碰。规则与操作见 [母舰航线](ship-navigation.md)。

## 已执行并通过

根目录 `%TEMP%\echo-route-queue-qa-20261024`，保留每次 `summary.json`、参数、原生日志及 JSONL。

| 检查 | 结果 |
|---|---|
| 资源导入、28 Godot、23 Python | `check-20261024T084239Z-2efc9770` 全部通过 |
| 七项图形回归 | `test-20261024T084132Z-030fb8f9`：多航点、单航点、飞机导航、M0/M1 加固、M1 UI、雷达、任务指引通过 |
| 最终视觉调整复验 | `test-20261024T084530Z-833ffbe4`：多航点、雷达、M1 UI 图形通过，零错误／告警 |
| 截图尺寸 | 19 张成功 PNG 均逐一读取并验证尺寸；最终 `final/` 重新完成 1280×720、1600×900、1920×1080 的默认／弱 CRT 六组及中途通过画面 |

执行命令（实际执行另加 `--output`）：

```powershell
$env:GODOT_BIN = 'H:\Godot_v4.7.2-stable_win64.exe'
python tools/dev.py check
python tools/dev.py test --graphics --case ship_route_queue --case ship_route --case flight_navigation --case m0_m1_hardening --case m1_ui --case radar_visual --case mission_guidance
python tools/dev.py capture ship-route-queue --resolution 1280x720 --weak-crt
python tools/dev.py capture ship-route-queue-mid
```

### 新回归覆盖

`tests/ship_route_queue_smoke.gd`：

- `detour_and_budget`：直接穿岛拒绝，从队尾追加的合法绕岛路线通过；合计航程、解算数组副本、暂停、一个大步通过全部转角、真实通过时刻、终点停车与单次事件、1×/10×、跨转角剩余时间。
- `forecast_turns`：手动直行会触及边界时预警；航点终点停车及排队转弯不被错误外推成越界。
- `editing`：8 个待执行点上限、第 9 点原子拒绝、撤回末点保持当前段及航速、空余容量下非法追加保持原队列、修订号、替换整条路线、撤回最后一点停车。
- `lifecycle`：空中托管通过中间点、空中禁止编辑、停车请求清空全部未来点、危险中断、重开清理、母舰损失清空队列。
- `ui`：图形模式走真实 CRT 输入，Shift+右键、可见追加控件、Shift+Enter、档案模态隔离、完整点位提示、撤回与取消按钮、行动归档。

旧测试未删除或降低预期；本批所有新增 smoke 使用现有 SceneTree 入口，无新增框架依赖。

## 视觉检查

开发者查看最终六组航线画面、中途通过、飞机导航、配置、静默及陈旧画面。编号文字采用真实宽度、多候选位置，避让设施／水深文字、其他航点标签和圆形边缘；没有空间时保留点位，完整待执行编号及坐标可从航线状态提示查看。航线使用已知命令数据，不改变敌方识别、回波衰减或传感器范围。

留档：修改前 [单航点](reference/ship-route-qa/route.webp)；最终 [绕岛航线](reference/route-queue-qa/route.webp)、[1280 弱 CRT](reference/route-queue-qa/route-weak.webp)、[中途通过](reference/route-queue-qa/mid-route.webp)。WebP 是压缩展示副本，原始 PNG 和设置保存在诊断目录。

## 已执行但曾失败，已修复

首轮 `test-20261024T084019Z-5f063a64` 的普通手动航行分支出现 `Array`／`Array[Vector2]` 类型赋值错误，并连带影响预警字典和界面刷新。改为明确构造类型化数组；六项关联复验、七项图形及全量检查通过。即使进程退出码为 0，工具仍检出脚本错误并判失败，记录未隐藏。

初版截图中的航点文字存在相互叠压；按实际文字尺寸与占位区域修正后补拍最终矩阵。全量保留既有预期警告：debug_log 两项、p0 四项、ship_route 一个无效操舵命令；新增多航点 smoke 无警告。

## 未执行与限制

- 真人完整长时驾驶／交战及视觉舒适度评估，不以自动化代替玩家体验。
- 跨硬件和长时间性能／内存基准；本批没有修改 CRT Shader，未宣称性能改善。标签避让复用本帧水深文字数据，未重复计算水深标签。
- 仍为中心点、最多 20 m 采样和瞬时转向模型；人工规划航线不会自动抵御敌方攻击或改变首关胜利条件。

保留工作区已有 `AGENTS.md` 删除、`.agents/` 和 SVG 导入文件，不纳入本批提交。
