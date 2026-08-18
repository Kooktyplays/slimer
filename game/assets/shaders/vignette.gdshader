shader_type canvas_item;
render_mode unshaded;

// Screen-edge vignette. Used red for low health and for damage flashes.
// Kept to the outer edge on purpose: the centre of the screen is where the
// player is fighting, and tinting it would trade information for atmosphere.

// `inner` is pushed well past the middle on purpose: the playable area has to
// stay uncoloured, or a low-health warning becomes a reason to lose.
uniform vec4 tint : source_color = vec4(0.8, 0.1, 0.12, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float inner : hint_range(0.0, 1.5) = 0.86;
uniform float outer : hint_range(0.0, 2.0) = 1.45;

void fragment() {
	vec2 d = SCREEN_UV - vec2(0.5);
	d.x *= 1.25;                       // account for a widescreen viewport
	float r = length(d) * 2.0;
	float v = smoothstep(inner, outer, r);
	COLOR = vec4(tint.rgb, v * intensity);
}
