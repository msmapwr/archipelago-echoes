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

出航设置页可调整主音量、1280×720／1600×900／1920×1080 窗口、全屏和弱化 CRT；点击“应用并保存”生效，下次启动自动恢复。恢复默认只填入草稿，未应用的修改不会保存。配置位于 Godot 用户目录 `user://preferences.cfg`，保存失败保留旧设置。

生成页可输入 0–2147483647 的种子或使用随机种子，生成五岛的位置偏移和半径；同一种子复现同一布局。修改种子后必须重新生成，通过出生点与离港航道校验才能继续；失败可重新生成或返回菜单。离港和首关重试沿用该种子。港口布局、岛屿锚点和任务配置仍为固定原型。

点击“开始游戏”后依次进入开场、设置、背景、新手教程、指令部命令、海域生成和港口准备；准备时正式世界暂停。背景与简报来自首关任务资源，长文可滚动阅读。七步训练台练习扫描、选择、识别、炮击、航行、暂停和安全回收，支持跳过与重播；训练是独立的简化模拟，不消耗正式资源，完成或跳过后才能接受命令。完整开场影像和正式剧情仍待制作。进入港口后点击“解缆”，以航向按钮和加减速按钮驾驶舰船；港内限速 10 kn，沿中央航道向北驶过 320 m 外的离港线，才自动启动首关。码头、防波堤和港区边界会阻挡航行并停车，可调整航向后重试。港内支持暂停、×1／×10 时间和返回菜单；离港后位置、航向和速度继续沿用。成功结算或失败后可返回主菜单，也可直接重试相同种子的首关。见 [完整游戏流程](docs/game-session-flow.md)。

## 验证

任务中主 CRT 顶部显示当前目标。页脚“命令档案”或 F1 可查简报、五项任务进度和行动记录；ESC 关闭。阅读暂停模拟，关闭恢复此前运行状态和倍率，手动暂停及结束状态保持冻结。返航时提示回收窗口、航速限制与直线燃油估算；提前降落但情报未完成会说明补救路径。

出击配置可选母舰保持航行或升空后停车；空中可请求母舰停车，返航中可取消返航继续侦察。停车不阻止敌方攻击，取消返航不补油。暂停时航行／导航可排队，其余实际行动需恢复模拟后执行。M0/M1 的技术验收与真人试玩要求见 [验收清单](docs/m0-m1-acceptance.md)。

新手教程首次全部完成后自动保存，后续开始默认跳过；背景与命令页可重播。仅点击跳过不会记录为完成，重播不清除既有完成状态。

座舱导航图跟随飞机，显示母舰／机场和回收窗口；右键指定航点，或聚焦雷达后方向键定位、Enter 确认。选择机场后返航会保留机场，燃油面板显示入窗估算与余量；母舰沉没则改航机场。详见 [飞行导航](docs/flight-navigation.md)。

雷达回波按观测年龄由亮到暗，复测恢复亮度；选择框和标签保持可读。舰艇数据目前含护航航舰、航空母舰、驱逐舰、巡洋舰、战列舰、潜艇六类，各有类别占位符号，首关仍使用原有舰机与武器规则。`scripts/data/unit_visual_catalog.gd` 为每类建筑／战舰的每个小、中、大尺寸预留十个形态 ID；这些槽位尚无完整美术，资源可通过 `symbol_texture`、`silhouette_scene` 接入。形态库与拼装要求见 [总计划](docs/plan.md)。

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
godot --headless --path . --script res://tests/radar_visual_smoke.gd
godot --headless --path . --script res://tests/settings_generation_smoke.gd
godot --headless --path . --script res://tests/tutorial_flow_smoke.gd
godot --headless --path . --script res://tests/mission_guidance_smoke.gd
godot --headless --path . --script res://tests/m0_m1_hardening_smoke.gd
godot --headless --path . --script res://tests/flight_navigation_smoke.gd
godot --headless --path . --script res://tests/menu_ui_smoke.gd
godot --path . --script res://tests/m1_ui_smoke.gd
```

最后一项使用图形窗口检查嵌入主界面后的 CRT 鼠标输入。控制台分区与比例说明见 [UI 布局说明](docs/ui-shell.md)；规则、已验证分支和原型限制见 [M1 首关说明](docs/m1-vertical-slice.md)；版本变更见 [CHANGELOG](CHANGELOG.md)。

## 项目状态

首关的自动化闭环已通过。实际玩家游玩记录、长期平衡、更多关卡、完整海空战和战役系统仍在后续阶段。仓库根目录存放 Godot 场景、脚本、样例数据与测试；`docs/` 存放计划和设计决策，`AGENTS.md` 为开发规范。
