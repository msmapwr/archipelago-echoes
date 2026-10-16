# Large A 海图与图标视觉验收

2026-10-11；Windows，Python 3.11.15，Godot 4.7.2 Compatibility。引擎：`H:\Godot_v4.7.2-stable_win64.exe`。基线为 `f3e182d`，在临时目录从 Git 导出独立副本；未还原或覆盖工作区。首关种子 `270928`。

## 已执行并通过

| 验收 | 证据 |
|---|---|
| 全量工具／脚本／玩法回归 | `python tools/dev.py --godot H:/Godot_v4.7.2-stable_win64.exe check`；23 项 Python、导入及 25 项 Godot smoke 通过，原有主动失败路径保留 6 个预期警告 |
| 地图与深度 | `chart_features_smoke.gd::map_data`：固定种子复现、不同种子差异、海岸深度、陆地／地图外边界、机场位置、四级等深线均处于水域 |
| 码头与建筑 | `port_structure/harbor_data`：全部港口尺寸与十形态具备独立屋顶和栈桥；十种仓库子结构、有界画布、港内六建筑、既有岸壁和可航通道 |
| 圆形裁切与标注 | `clip_boundaries/projections`：线段／面填充在圆内，量程边界、稳定数据、六设施、最小符号尺寸、图标互斥、文字避让、未登记设施隐藏 |
| 结构与导出兼容 | `unit_icon_smoke`：420 个有界且组内独特结构、PNG/SVG/JSON、透明边界和完整图集索引；`unit_library_flow_smoke`：未知身份与暂停所有权 |
| 真图形模式 | `test --graphics --case m1_ui --case radar_visual --case flight_navigation --case unit_icon --case unit_library_flow --case harbor_navigation --case chart_features`；最后几何／导航避让修改又执行 chart_features、flight_navigation、radar_visual |
| 临时截图设置 | Python `CliTests.test_capture_options_reach_only_child_process_and_report`；配置只传给子进程，报告记录模式／分辨率／弱 CRT |
| 视觉矩阵 | 港口与舰桥各三分辨率（1280×720、1600×900、1920×1080）×普通／弱 CRT；最终 PPI 修改后重新截图六种组合，验证 PNG 实际尺寸 |
| 信息状态 | 正常、选择、陈旧、静默、100 km 审查视图、飞行导航、火控；静默保留已知海图，回波按旧观测衰减，机场回收标记不重复；另复查最低分辨率弱 CRT 座舱 |
| 结构视觉检查 | Godot 资源展示场景的港口／船坞灰度预览与十形态条；开发者检查设施用途轮廓，不能代替玩家无标签辨识 |
| 原有闭环 | m1_mission、m0_m1_hardening、tutorial_flow、menu_ui、settings_generation 自动覆盖开始、准备、离港、海空任务、回收、失败／结算及重试；非真人完整试玩 |

### 截图对照

基线港口：[修改前](reference/chart-qa/before-harbor.webp)；本批港口：[修改后](reference/chart-qa/harbor.webp)。泊位编号移至水域侧，不覆盖仓库；控制楼与维修区有独立图标。

基线舰桥：[修改前](reference/chart-qa/before-game.webp)；本批舰桥：[修改后](reference/chart-qa/game.webp)。岸线对应真实地图，边缘岛屿可部分显示，设施和水深标注遵循优先级。

原始 PNG 与诊断保留在 `%TEMP%\echo-chart-qa-20261011`；文档仅保存四张压缩对照图，目录 `.gdignore` 防止 Godot 导入文档截图。截图审查没有发现新增的遮盖或裁切问题；1280×720 下已有终端小字号仍有进一步提升空间，归入 Large B。

## 绘制成本

使用同一 Godot、1600×900 窗口、570×460 PPI、25 km 量程和种子；暂停模拟、关闭结构日志。分别固定位置和每帧移动 0.003 km，预热 30 帧，每状态采集 180 次 `_draw()` CPU 耗时。基线与本批均在独立进程运行，测量脚本及 JSON 留在上述临时目录。

| PPI 绘制 | 基线均值／P95 | 本批均值／P95 |
|---|---|---|
| 固定位置 | 0.551／0.648 ms | 0.634／0.725 ms |
| 连续移动 | 0.559／0.671 ms | 2.063／2.187 ms |

静态内存约 35.2 → 37.5 MB（Godot 静态内存监视器，含新增海图数据与测试采样）。新增海图有实际成本；使用岸线／等深线／标记投影缓存及内外裁切快速路径，避免静止时重复几何计算。此项是 PPI CPU 绘制成本，不是整款游戏 FPS、GPU 或长期内存证明；不据此声称整体性能提升。

## 已执行但失败，随后复验通过

早期草稿纸图使用首尾重复的填充顶点，触发 Godot 原生多边形三角化错误。工具按错误日志判失败，即使进程退出码为零；改为无重复填充顶点和独立闭合轮廓，后续相关、全量与图形回归通过。泊位／仓库与水深标签重叠在截图中发现后修正并复查。

## 未执行

- 玩家无标签舰种／设施辨识实验及全部 420 个结构的人工美术验收。
- 真人从菜单到结算／失败的完整长时试玩、不同显卡／驱动兼容性与长时内存稳定性。
- 水深、声呐、吃水、建筑生产／补给等玩法；本批没有实现这些能力。

## 证据位置

最终全量报告：`%TEMP%\echo-dev\check-20261011T101208Z-0a89b974\summary.json`；七项图形报告：`test-20261011T100422Z-f9a2ee0c`；最后三项图形复验：`test-20261011T101005Z-99cdb4af`。完整截图参数在每个截图目录 `capture-settings.json`，原生日志和 JSONL 均由工具保存。

Godot MCP 已启动项目并保留窗口运行；启动无脚本／Shader 错误。原有 EventBus 未显式使用信号和地图 `seed` 命名警告保留；本批两处局部变量遮蔽警告已清理，图形 `chart_features` 再次复验通过（`test-20261011T101606Z-101cca0d`）。

2026-10-16 续作收尾：确认工作区与中断时一致；将港口回归改为检查建筑位于岸侧、每条栈桥服务独立建筑，避免绑定单个矩形的精确坐标。完整 `check` 再次通过（23 项 Python、导入和 25 项 Godot smoke）；报告：`%TEMP%\echo-dev\check-20261016T103343Z-0e2c2598\summary.json`。此前截图和性能数字保留为 10 月 11 日的实际记录。
