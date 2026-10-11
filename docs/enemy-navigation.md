# 敌舰受损撤离切片

2026-10-11，依据 `plan-legacy.md` §14 的巡逻、机动、士气与非全知 AI，以及 `plan.md` 的海战 AI 后续包。此批保留一个 A1 和原侦察／安全回收任务，不引入多目标、难度档或战役逃兵结算。

## 规则与操作

- 完好敌舰保持已有东西向巡逻、探测记忆和 10 km 还击规则。
- 实际舰体降至 **40% 或以下且仍存活**，进入本关持续的撤离状态。速度 **18 kn**，每模拟秒最多转 **5°**。这些是原型默认值，不是 legacy 固定数值；位于 `ContactDefinition` 的 withdrawal 字段，数据加载校验有限正数及阈值范围。
- 方向背离最后已知威胁。敌舰只通过既有雷达截获／目视更新己舰位置记忆，实际受击可记住炮弹发射点或轰炸机位置。失去探测后不偷读玩家实时位置；没有位置记忆时保持当前航向撤离。
- 移动逐段检查岛屿及地图边界，不能穿越陆地或离开地图；受阻时原地按有限转向率转向再尝试。此为局部避障，尚无全局绕岛寻路，狭窄海域可能持续受阻，调试日志显示 blocked。
- 撤离仍可按原规则还击；没有自动脱战、无敌、回血、弹药刷新或目标删除。暂停冻结、击沉停车、结束停止、重开恢复巡逻及 6 kn。

可玩路径：确认／指派 A1 → 接近并使用 AP 连续命中两次 → 存活敌舰降至 30% 后撤离 → 复测航向变化 → 更新提前量／照射及校射，或完成侦察并返航。不能因敌舰受损而直接判定任务胜利。

## 玩家情报

真实撤离状态不进入玩家档案。成功扫描已确认接触后，比较采样航向／位移，显示“转向机动”“正在远离本舰”或“保持观测航向”；这些描述只表示观测，不证明撤退意图。

没有复测时详情保持原情报；静默、失联或观测超过 45 秒标记“旧观测”。采样描述变化进入 F1 行动记录；已指派的目标出现机动观测时，指引建议复测运动解并留意还击、返航。火控仍沿用最后观测、时效、射程射界与资源检查。

## 状态所有权与诊断

`enemy_navigation.gd` 为每实例 RefCounted，拥有撤离状态与威胁记忆；控制器拥有舰体、实际位置／航向／速度和伤害入口；资源只提供配置。UI 只读 `contact_maneuver_status()`，不写 AI 数据。

DebugLog 记录 `enemy_withdrawal_started`，包含触发健康、来源、威胁记忆及真实状态，炮弹伤害保持弹着子步时间。`enemy_navigation_obstacle` 记录阻挡状态变化；周期快照的 `MissionController.enemy_navigation` 包含真实与采样情报，便于区分 AI 行为和玩家看到的内容。

```powershell
python tools/dev.py test --case enemy_navigation
python tools/dev.py test --case enemy_navigation --graphics
python tools/dev.py capture enemy-withdrawal
python tools/dev.py analyze "诊断目录" --kind enemy_withdrawal
```

## 验收

| 要求 | 回归入口 |
|---|---|
| 阈值边界、单次转态、死亡与重置、转速、步长一致性、海岸／边界、未知与非法威胁 | `enemy_navigation_smoke.gd::policy_boundaries` |
| 非有限配置、有效默认值和阈值上下界 | `enemy_navigation_smoke.gd::profile_validation` |
| 真实两发 AP、资源／指派保持、隐藏移动与复测、CRT／指引／档案、暂停、非全知、死亡和重开 | `enemy_navigation_smoke.gd::combat_observation_lifecycle` |

四级 AI、个性、协调、干扰、全局寻路、火灾进水与子系统损伤仍待后续完整切片。

验证结果：全部 24 项 Godot smoke、22 项 Python 测试与资源导入通过；撤离、双炮组、任务指引三项图形回归通过。`enemy-withdrawal` 实际 CRT 截图中采样机动、火控复测建议与按钮均可读；分析日志确认真实撤离单独记录且无原生 ERROR。最终复验新增配置边界、结束冻结、调试日志与 P0；原有预期警告保留。
