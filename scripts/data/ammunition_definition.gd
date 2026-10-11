extends GameDefinition
class_name AmmunitionDefinition

@export var damage: float = 50.0
@export var penetration_mm: float = 80.0
@export var overpenetration_ratio: float = 1.0

func snapshot() -> Dictionary:
	return {"id": id, "label": display_name, "damage": damage, "penetration_mm": penetration_mm, "overpenetration_ratio": overpenetration_ratio}

static func resolve(profile: Dictionary, armor_mm: float) -> Dictionary:
	var penetration: float = profile.get("penetration_mm", 0)
	var base_damage: float = profile.get("damage", 0)
	if armor_mm > penetration:
		return {"damage": base_damage * 0.15, "outcome": "未穿透 / 表面损伤"}
	if armor_mm < penetration * 0.15:
		return {"damage": base_damage * float(profile.get("overpenetration_ratio", 1)), "outcome": "过穿" if profile.get("overpenetration_ratio", 1) < 1 else "爆破"}
	return {"damage": base_damage, "outcome": "穿透"}
