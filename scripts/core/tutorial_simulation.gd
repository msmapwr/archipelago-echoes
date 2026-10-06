extends RefCounted

# A rehearsal, deliberately independent of the live mission and its autoloads.
const LESSONS := [
	["主动扫描", "点击主动扫描，让训练回波出现在雷达上。发射雷达也可能暴露自己的位置。"],
	["选择回波", "点击雷达上的 A1，或使用选择 A1 按钮。亮点只代表接触，不代表敌人。"],
	["确认身份", "再扫描一次，再确认接触。至少两次观测才能识别；过期回波需重新扫描。"],
	["甲板炮演练", "A1 已确认为训练敌舰，距离 8 km、方位 042°，在舰首射界内。点击甲板炮。"],
	["航行命令", "点击右转 15°，再加速到 6 kn。正式航行要避开岛屿；港内限速 10 kn。"],
	["暂停与恢复", "点击暂停，再恢复。正式任务也可用空格暂停；时间倍率会同时影响敌人。"],
	["出击与安全回收", "按顺序演练出击、返航和降落回舰。正式任务的切换、航行和降落都需要时间与燃油。"],
]

var step: int = 0
var scans: int = 0
var echo_age: float = 0.0
var selected: bool = false
var identified: bool = false
var fired: bool = false
var heading_degrees: float = 0.0
var speed_knots: float = 0.0
var paused: bool = false
var practiced_pause: bool = false
var flight: String = "deck"
var skipped: bool = false
var message: String = "训练链路在线。正式关卡时间与资源保持冻结。"

func ready_to_continue() -> bool:
	return skipped or step == LESSONS.size()

func advance_time(delta: float) -> void:
	if not paused and not ready_to_continue():
		echo_age += maxf(0.0, delta)

func act(action: String) -> bool:
	if ready_to_continue():
		return _reject("训练已结束；可重播或继续接受命令。")
	if action == "scan":
		if paused:
			return _reject("训练已暂停，请先恢复。")
		scans += 1
		echo_age = 0.0
		message = "新观测已写入 / A1 · 方位 042° · 距离 8 km。"
		if step == 0:
			step = 1
		return true
	match step:
		1:
			if action == "select":
				selected = true
				return _complete("已选择 A1；身份仍未确认。")
		2:
			if action == "identify":
				if scans < 2 or echo_age > 15.0:
					return _reject("需要至少两次扫描，且最新观测不超过 15 秒。请主动扫描。")
				identified = true
				return _complete("识别完成 / 训练敌舰。正式任务中不要向未知或中立目标开火。")
		3:
			if action == "fire":
				if echo_age > 15.0:
					return _reject("观测已过期，请重新扫描再开火。")
				fired = true
				return _complete("训练弹命中。正式甲板炮有射程、射界、弹药和装填限制。")
		4:
			if action == "turn":
				heading_degrees = 15.0
			elif action == "throttle":
				speed_knots = 6.0
			else:
				return _reject("请先练习航向和航速控制。")
			message = "航向 %03.0f° / 航速 %.0f kn。" % [heading_degrees, speed_knots]
			if heading_degrees == 15.0 and speed_knots == 6.0:
				return _complete("航行命令已下达；正式港口需要实际驶过离港线。")
			return true
		5:
			if action == "pause":
				paused = not paused
				if paused:
					practiced_pause = true
					message = "训练暂停；点击恢复继续。"
					return true
				if practiced_pause:
					return _complete("时间已恢复。暂停可用于阅读情报与下达命令。")
		6:
			if action == "launch" and flight == "deck":
				flight = "airborne"
				message = "训练飞机升空；正式出击时母舰仍可能遭受攻击。下一步返航。"
				return true
			if action == "return" and flight == "airborne":
				flight = "approach"
				message = "训练飞机已进入进近；正式任务需接近回收点并满足降落条件。"
				return true
			if action == "land" and flight == "approach":
				flight = "recovered"
				return _complete("训练完成。只有安全回收才能继续作战；正式任务只有一条命。")
	return _reject("操作条件未满足，请按当前训练提示完成步骤。")

func skip() -> void:
	skipped = true
	paused = false
	message = "已跳过训练。正式任务中请注意识别、燃油与安全回收。"

func _complete(feedback: String) -> bool:
	step += 1
	message = feedback
	return true

func _reject(feedback: String) -> bool:
	message = feedback
	return false
