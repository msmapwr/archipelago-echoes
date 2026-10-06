shader_type canvas_item;

// Character CRT glass: restrained line structure and edge falloff.
// The radar PPI draws its own phosphor response and does not use an RGB mask.
uniform float line_strength : hint_range(0.0, 0.03) = 0.004;
uniform float edge_strength : hint_range(0.0, 0.2) = 0.08;
uniform vec2 screen_size = vec2(1200.0, 636.0);
uniform float corner_radius = 22.0;

void fragment() {
	float line_structure = 0.5 + 0.5 * cos(UV.y * 636.0 * 6.2831853);
	vec2 centered = (UV - vec2(0.5)) * vec2(1.55, 1.15);
	float edge = smoothstep(0.44, 0.83, length(centered));
	float reflection = exp(-pow((UV.x + UV.y * 0.45 - 0.42) * 8.0, 2.0)) * 0.018;
	float alpha = line_structure * line_strength + edge * edge_strength + reflection;
	vec2 corner = abs((UV - vec2(0.5)) * screen_size) - (screen_size * 0.5 - vec2(corner_radius));
	float distance_to_edge = length(max(corner, vec2(0.0))) + min(max(corner.x, corner.y), 0.0) - corner_radius;
	float outside = smoothstep(-0.75, 0.75, distance_to_edge);
	COLOR = vec4(mix(vec3(0.04, 0.10, 0.07), vec3(0.008, 0.025, 0.021), outside), mix(alpha, 1.0, outside));
}
