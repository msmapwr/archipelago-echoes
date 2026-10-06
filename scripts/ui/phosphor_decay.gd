extends RefCounted

static func energy(age_seconds: float, lifetime_seconds: float) -> float:
	if lifetime_seconds <= 0.0:
		return 0.0
	return pow(clampf(1.0 - maxf(0.0, age_seconds) / lifetime_seconds, 0.0, 1.0), 1.7)
