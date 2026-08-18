shader_type canvas_item;
render_mode unshaded;

// Foliage sway. The phase comes from the sprite's own world position, so every
// bush and tree in the forest moves out of step with its neighbours while all
// of them share one material - no per-node uniforms, no per-frame script cost.
//
// Only the top of the sprite moves: displacement is weighted by (1 - UV.y)
// squared, so the base stays planted and the canopy leans.

// Driven by Game, which stops advancing it while the game is paused.
global uniform float anim_time;

uniform float strength : hint_range(0.0, 3.0) = 1.0;
uniform float speed : hint_range(0.1, 4.0) = 1.25;
uniform float amount : hint_range(0.0, 24.0) = 5.0;

void vertex() {
	float phase = MODEL_MATRIX[3].x * 0.0131 + MODEL_MATRIX[3].y * 0.0077;
	float top = 1.0 - UV.y;
	float lean = sin(anim_time * speed + phase)
		+ 0.35 * sin(anim_time * speed * 1.7 + phase * 2.3);
	VERTEX.x += lean * amount * strength * top * top;
}
