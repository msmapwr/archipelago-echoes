# 群岛回波 / Echoes of the Archipelago

使用 Godot 4.7.2 开发的海空战术游戏原型。主场景是 16:9 的舰桥作战情报中心：中央是单色雷达与字符 CRT，旁边有机械仪表、彩色档案监视器和纸质航海图。菜单经过短暂的设备自检后，仅提供“开始游戏”按钮；点击后依次进入准备流程和港口驾驶，驶离港口后由首关战术终端接管中央 CRT，可搜索接触、识别或交火、驾驶侦察机、返航并结算。布局参考 [UI SVG 草图](docs/reference/ui_wireframe_redraw.svg)，视觉规则见 [游戏美学计划](docs/archipelago_echoes_aesthetic_plan.md)，阶段与后续工作见 [详细开发计划](docs/development-plan.md)。

## 运行与首关操作

1. 使用 Godot 4.7.2 标准版导入根目录的 `project.godot`，运行项目，在主界面点击“开始游戏”，依次完成准备页并驾驶离港。窗口缩放时画面保持 16:9。
2. 在中央 CRT 的舰桥界面点击雷达回波选择 A1；执行两次有效扫描后可确认目标。也可以出击，在距离目标 3 km 内目视侦察完成确认。
3. 舰桥可调整航向、航速；甲板炮要求目标已确认、位于 10 km 内及舰艏两侧各 70° 射界内，且接触情报未过期。雷达上的扇形线标示武器范围，火控栏显示限制与装填倒计时。敌舰会巡逻并在接近后还击。
4. 点击“配置出击”与“开始出击”，等待指挥权移交；飞机可调整航向或导航至 A1、母舰、机场，在 2 km 内执行一次对海攻击。
5. 点击“开始返航”，靠近回收点后降落。母舰回收要求距离不超过 2 km、航速不超过 12 kn；若母舰沉没，可改往友方机场，在 3 km 内降落。确认目标且指挥官安全回收后执行结算。

空格暂停或继续，Esc 清除雷达选择；页脚可切换 1 倍与 10 倍模拟时间。舰桥可切换舰载雷达：静默停止扫描和火控，主动开机可能被敌舰测向；近距离静默也不能保证不被目视发现。命令失败会在右侧显示原因。战役失败或任务结算后可重新开始首关。

页脚“量程”切换 12.5 / 25 km 雷达显示。近距档放大附近目标，远处接触暂不显示；切换回搜索档即可重新选择。此操作不改变雷达探测范围。规则与限制见 [雷达距离档与舰炮射界](docs/p2-fire-control.md)。

母舰受损后，舰桥会显示“投入损管队”。先减速至不超过 12 kn；每关可投入两次，每次修理 30 模拟秒，恢复最多 20% 舰体。修理期间甲板炮停用，敌方仍能攻击；亲自出击后损管继续。暂停会冻结修理进度，沉没则终止修理。

## 游戏流程

点击“开始游戏”后依次进入开场、设置、背景、新手教程、指令部命令、生成和港口出航准备；动画与设置等内容仍预留，准备时世界暂停。进入港口后点击“解缆”，以航向按钮和加减速按钮驾驶舰船；港内限速 10 kn，沿中央航道向北驶过 320 m 外的离港线，才自动启动首关。码头、防波堤和港区边界会阻挡航行并停车，可调整航向后重试。港内支持暂停、×1／×10 时间与返回菜单，海上敌人和任务时钟保持冻结；离港后位置、航向和速度继续沿用。成功结算或失败后可返回主菜单，也可直接重试首关。设置保存与随机生成尚未实现，见 [完整游戏流程](docs/game-session-flow.md)。

## 验证

在仓库根目录运行：

```powershell
godot --headless --path . --editor --quit
godot --headless --path . --quit-after 1
godot --headless --path . --script res://tests/p0_smoke.gd
godot --headless --path . --script res://tests/p1_world_smoke.gd
godot --headless --path . --script res://tests/p1_navigation_smoke.gd
godot --headless --path . --script res://tests/m1_mission_smoke.gd
godot --headless --path . --script res://tests/damage_control_smoke.gd
godot --headless --path . --script res://tests/harbor_navigation_smoke.gd
godot --headless --path . --script res://tests/menu_ui_smoke.gd
godot --path . --script res://tests/m1_ui_smoke.gd
```

最后一项使用图形窗口检查嵌入主界面后的 CRT 鼠标输入。控制台分区与比例说明见 [UI 布局说明](docs/ui-shell.md)；规则、已验证分支和原型限制见 [M1 首关说明](docs/m1-vertical-slice.md)；版本变更见 [CHANGELOG](CHANGELOG.md)。

## 项目状态

首关的自动化闭环已通过。实际玩家游玩记录、长期平衡、更多关卡、完整海空战和战役系统仍在后续阶段。仓库根目录存放 Godot 场景、脚本、样例数据与测试；`docs/` 存放计划和设计决策，`AGENTS.md` 为开发规范。
