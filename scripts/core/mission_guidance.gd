extends RefCounted

# Read-only projection of the current prototype. No task rules or resources change here.
static func project(state: Dictionary) -> Dictionary:
	var mode: String = state.get("mode", "bridge")
	var identified: bool = state.get("identified", false)
	var recovered: bool = state.get("recovered", false)
	var observed: bool = state.get("scans", 0) > 0
	var result := {"stage": "search", "title": "搜索接触", "next": "主动扫描海峡，寻找 A1。", "warning": "", "milestones": [observed, identified, state.get("launched", false), recovered, state.get("settled", false)], "can_land": false, "landing_reason": "", "return_seconds": 0.0}
	if mode == "campaign_failed":
		result.stage = "failed"
		result.title = "指挥官失联"
		var causes := {"fuel_exhausted": "燃油耗尽，飞机失事。", "ship_sunk_with_player_aboard": "母舰沉没，指挥官未能撤离。"}
		result.next = causes.get(state.get("death_reason", ""), "指挥官死亡，本次行动结束。") + " 可重新开始或返回主菜单。"
		return result
	if mode == "settlement":
		result.stage = "complete"
		result.title = "行动完成"
		result.next = "接触已确认，指挥官安全回收。查看命令档案复盘，或返回主菜单。"
		return result
	if recovered:
		if identified:
			result.stage = "report"
			result.title = "提交任务报告"
			result.next = "识别与安全回收均已完成；点击任务结算提交报告。"
		elif mode == "bridge":
			result.stage = "identify"
			result.title = "补齐目标情报"
			result.next = "已安全回舰，但 A1 未确认；开启雷达，完成两次有效扫描后确认接触。"
		else:
			result.stage = "incomplete"
			result.title = "情报尚未完成"
			result.next = "已降落机场，但未确认 A1；当前无法在机场补做侦察。重新开始或返回菜单。"
		return result
	if mode == "configuration":
		result.stage = "configure"
		result.title = "准备出击"
		result.next = "确认舰体、航速和燃油，再点击起飞。可取消配置返回舰桥。"
	elif mode == "switching":
		result.stage = "transfer"
		result.title = "指挥权移交"
		result.next = "移交还需 %.1f 秒；母舰继续执行最后航行命令。可取消或等待升空。" % state.get("switch_seconds", 0.0)
	elif mode == "cockpit":
		result.stage = "return" if identified else "recon"
		result.title = "情报已确认，准备返航" if identified else "空中确认 A1"
		result.next = "点击返航，导航到母舰或友方机场；目标击沉不是本关结算条件。" if identified else "导航 A1，进入 3 km 内点击空中侦察。当前距离 %.1f km。" % state.get("contact_distance", 0.0)
	elif mode == "returning":
		result.stage = "recover"
		result.title = "返航与回收"
		var ship_distance: float = state.get("ship_distance", INF)
		var field_distance: float = state.get("airfield_distance", INF)
		if state.get("ship_afloat", true) and ship_distance <= 2.0:
			result.can_land = state.get("ship_speed", 0.0) <= 12.0
			result.landing_reason = "已进入母舰 2 km 回收窗口；点击降落回舰。" if result.can_land else "母舰航速超过 12 kn，无法回收；导航友方机场，离开母舰回收窗口后再降落。"
		elif field_distance <= 3.0:
			result.can_land = true
			result.landing_reason = "已进入友方机场 3 km 回收窗口；点击降落。"
		else:
			result.landing_reason = "继续导航：母舰 %.1f km / 机场 %.1f km；回收窗口分别为 2 / 3 km。" % [ship_distance, field_distance]
		result.next = result.landing_reason
	elif identified:
		result.stage = "sortie"
		result.title = "出击并安全回收"
		result.next = "A1 已确认；本关还需一次出击与安全回收。点击配置出击，回收后提交报告。"
	elif observed:
		result.stage = "identify"
		result.title = "确认目标身份"
		result.next = "已有两次有效观测；点击确认接触，或配置飞机从空中侦察。" if state.get("scans", 0) >= 2 else "已有一次观测；再扫描并确认接触，或配置飞机从空中侦察。"
		if not state.get("contact_visible", false):
			result.next = "当前回波中断；开启雷达并调整航路复测，或出击侦察。未知目标禁止开火。"
	if state.get("airborne", false):
		var use_ship: bool = state.get("ship_afloat", true) and state.get("ship_speed", 0.0) <= 12.0
		var distance: float = state.get("ship_distance", 0.0) if use_ship else state.get("airfield_distance", 0.0)
		var radius := 2.0 if use_ship else 3.0
		var flight_speed: float = state.get("flight_speed", 0.0) * 1.852 / 3600.0
		result.return_seconds = maxf(0.0, distance - radius) / flight_speed if flight_speed > 0.0 else INF
		var fuel: float = state.get("fuel_seconds", 0.0)
		if fuel < result.return_seconds + 120.0:
			var advice := "立即执行降落。" if result.can_land else "尽快导航%s。" % ("母舰" if use_ship else "友方机场")
			result.warning = "燃油警报：余 %.1f 分，直线回收估算 %.1f 分；%s" % [fuel / 60.0, result.return_seconds / 60.0, advice]
		elif not state.get("ship_afloat", true):
			result.warning = "母舰已沉没；立即导航友方机场并安全降落。"
		elif state.get("ship_speed", 0.0) > 12.0:
			result.warning = "母舰航速超过回收限制；可转往友方机场。"
	elif state.get("ship_health", 100.0) <= 40.0:
		result.warning = "母舰严重受损；低速投入损管或调整航路脱离接触。"
	elif state.get("tracking", false):
		result.warning = "敌方正在追踪母舰；雷达静默不能立即消除已有追踪。"
	return result
