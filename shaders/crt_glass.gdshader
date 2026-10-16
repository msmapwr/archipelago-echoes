shader_type canvas_item;

// Character CRT glass: restrained line structure and edge falloff.
// The radar PPI draws its own phosphor response and does not use an RGB mask.
uniform float line_strength : hint_range(0.0, 0.03) = 0.004;
uniform float edge_strength : hint_range(0.0, 0.2) = 0.08;
uniform vec2 screen_size = vec2(1200.0, 636.0);
uniform float corner_radius = 22.0;
// 0: monochrome PPI, 1: character terminal, 2: color archive monitor.
uniform int device_type : hint_range(0, 2) = 1;
global uniform float crt_effect_strength;

void fragment() {
	float line_structure = 0.5 + 0.5 * cos(UV.y * screen_size.y * 6.2831853);
	vec2 centered = (UV - vec2(0.5)) * vec2(1.55, 1.15);
	float edge = smoothstep(0.44, 0.83, length(centered));
	float reflection = exp(-pow((UV.x + UV.y * 0.45 - 0.42) * 8.0, 2.0)) * (device_type == 2 ? 0.035 : 0.014);
	float rim = smoothstep(0.72, 1.0, max(abs(UV.x - 0.5), abs(UV.y - 0.5)) * 2.0) * 0.025;
	float lines = line_structure * line_strength * (device_type == 0 ? 0.12 : 1.0);
	float alpha = (lines + edge * edge_strength + reflection + rim) * crt_effect_strength;
	vec2 corner = abs((UV - vec2(0.5)) * screen_size) - (screen_size * 0.5 - vec2(corner_radius));
	float distance_to_edge = length(max(corner, vec2(0.0))) + min(max(corner.x, corner.y), 0.0) - corner_radius;
	float outside = smoothstep(-0.75, 0.75, distance_to_edge);
	vec3 glass_tint = vec3(0.04, 0.10, 0.07);
	if (device_type == 2) {
		float mask = mod(floor(UV.x * screen_size.x), 3.0);
		glass_tint = mask < 1.0 ? vec3(0.18, 0.03, 0.03) : mask < 2.0 ? vec3(0.03, 0.18, 0.05) : vec3(0.03, 0.05, 0.18);
		alpha += 0.025 * crt_effect_strength;
	}
	COLOR = vec4(mix(glass_tint, vec3(0.008, 0.025, 0.021), outside), mix(alpha, 1.0, outside));
}
