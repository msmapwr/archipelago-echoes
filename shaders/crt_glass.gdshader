shader_type canvas_item;

uniform float scanline_strength : hint_range(0.0, 0.1) = 0.025;
uniform float edge_strength : hint_range(0.0, 0.2) = 0.07;

void fragment() {
	float scanline = 0.5 + 0.5 * cos(UV.y * 612.0 * 3.14159265);
	vec2 centered = UV * 2.0 - 1.0;
	float edge = smoothstep(0.55, 1.45, length(centered));
	float alpha = scanline * scanline_strength + edge * edge_strength;
	COLOR = vec4(0.005, 0.025, 0.012, alpha);
}
