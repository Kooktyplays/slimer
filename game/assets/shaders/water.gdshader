shader_type canvas_item;
render_mode unshaded;

// Pond surface: two slow, out-of-phase UV distortions plus a faint bright
// band, which reads as moving water without costing anything or drawing the
// eye away from combat.

global uniform float anim_time;

uniform float wobble : hint_range(0.0, 0.05) = 0.010;
uniform float speed : hint_range(0.0, 2.0) = 0.35;

void fragment() {
	vec2 uv = UV;
	uv.x += sin(anim_time * speed + UV.y * 26.0) * wobble;
	uv.y += cos(anim_time * speed * 0.8 + UV.x * 21.0) * wobble;
	vec4 c = texture(TEXTURE, uv);
	float shimmer = 0.06 * sin(anim_time * 0.6 + (UV.x + UV.y) * 14.0);
	c.rgb += shimmer;
	COLOR = c * COLOR;
}
