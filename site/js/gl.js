// Shared WebGL2 sprite renderer for the Slimer site.
//
// No libraries and no network requests beyond the atlas itself. Everything a
// scene draws - trees, slimes, bosses, telegraph markers, health bars - comes
// out of one packed atlas in a single instanced draw call.
//
// The foliage sway is a direct port of game/assets/shaders/sway.gdshader: the
// phase comes from the sprite's own world position so neighbours move out of
// step, and displacement is weighted by (1 - uv.y) squared so trunks stay
// planted while canopies lean. Like the game (see HANDOVER.md section 5) it
// runs off an explicit time uniform rather than a raw clock, so a scene that
// scrolls out of view freezes instead of drifting.

const VERT = `#version 300 es
precision highp float;

in vec2 a_corner;          // unit quad, (0,0) top-left .. (1,1) bottom-right
in vec4 i_rect;            // x, y, w, h  - top-left in world space
in vec4 i_uv;              // u0, v0, u1, v1 in atlas pixels
in vec4 i_tint;
in vec2 i_spin;            // rotation (radians), sway amount (px)

uniform vec4 u_view;       // camera x, camera y, viewport w, viewport h
uniform float u_zoom;
uniform float u_time;
uniform float u_sway_speed;

out vec2 v_uv;
out vec4 v_tint;

void main() {
	vec2 local = a_corner * i_rect.zw;

	// sway.gdshader, verbatim: phase from world position, canopy-weighted lean.
	float sway = i_spin.y;
	if (sway != 0.0) {
		float phase = i_rect.x * 0.0131 + i_rect.y * 0.0077;
		float top = 1.0 - a_corner.y;
		float lean = sin(u_time * u_sway_speed + phase)
			+ 0.35 * sin(u_time * u_sway_speed * 1.7 + phase * 2.3);
		local.x += lean * sway * top * top;
	}

	float s = sin(i_spin.x), c = cos(i_spin.x);
	vec2 mid = i_rect.zw * 0.5;
	vec2 d = local - mid;
	vec2 world = i_rect.xy + mid + vec2(d.x * c - d.y * s, d.x * s + d.y * c);

	// World is y-down, like Godot's 2D space; flip into clip space.
	vec2 clip = (world - u_view.xy) * u_zoom / (u_view.zw * 0.5);
	gl_Position = vec4(clip.x, -clip.y, 0.0, 1.0);

	v_uv = mix(i_uv.xy, i_uv.zw, a_corner);
	v_tint = i_tint;
}`;

const FRAG = `#version 300 es
precision highp float;

in vec2 v_uv;
in vec4 v_tint;

uniform sampler2D u_atlas;
uniform vec2 u_atlas_size;
uniform float u_flash;     // 0..1 whiteout, the flash.gdshader idea

out vec4 frag;

void main() {
	vec4 tex = texture(u_atlas, v_uv / u_atlas_size);
	if (tex.a < 0.004) discard;
	vec4 col = tex * v_tint;
	col.rgb = mix(col.rgb, vec3(1.0), u_flash * v_tint.a);
	frag = col;
}`;

const FLOATS_PER_INSTANCE = 14; // rect 4, uv 4, tint 4, spin 2
const MAX_INSTANCES = 8192;

let atlasPromise = null;

/** Loads the packed atlas once and shares it between every scene. */
export function loadAtlas() {
	if (!atlasPromise) {
		atlasPromise = (async () => {
			const [manifest, image] = await Promise.all([
				fetch(new URL('../assets/atlas.json', import.meta.url)).then((r) => {
					if (!r.ok) throw new Error(`atlas.json: ${r.status}`);
					return r.json();
				}),
				new Promise((resolve, reject) => {
					const img = new Image();
					img.onload = () => resolve(img);
					img.onerror = () => reject(new Error('atlas.png failed to load'));
					img.src = new URL('../assets/atlas.png', import.meta.url).href;
				}),
			]);
			return { manifest, image };
		})();
	}
	return atlasPromise;
}

export class Renderer {
	constructor(canvas, atlas) {
		const gl = canvas.getContext('webgl2', {
			alpha: true,
			antialias: false,
			premultipliedAlpha: false,
			powerPreference: 'low-power',
		});
		if (!gl) throw new Error('webgl2 unavailable');

		this.gl = gl;
		this.canvas = canvas;
		this.frames = atlas.manifest.frames;
		this.atlasSize = [atlas.manifest.width, atlas.manifest.height];

		const program = buildProgram(gl, VERT, FRAG);
		this.program = program;
		gl.useProgram(program);

		this.u = {
			view: gl.getUniformLocation(program, 'u_view'),
			zoom: gl.getUniformLocation(program, 'u_zoom'),
			time: gl.getUniformLocation(program, 'u_time'),
			swaySpeed: gl.getUniformLocation(program, 'u_sway_speed'),
			atlas: gl.getUniformLocation(program, 'u_atlas'),
			atlasSize: gl.getUniformLocation(program, 'u_atlas_size'),
			flash: gl.getUniformLocation(program, 'u_flash'),
		};

		this.vao = gl.createVertexArray();
		gl.bindVertexArray(this.vao);

		const quad = gl.createBuffer();
		gl.bindBuffer(gl.ARRAY_BUFFER, quad);
		gl.bufferData(
			gl.ARRAY_BUFFER,
			new Float32Array([0, 0, 1, 0, 0, 1, 1, 1]),
			gl.STATIC_DRAW,
		);
		const corner = gl.getAttribLocation(program, 'a_corner');
		gl.enableVertexAttribArray(corner);
		gl.vertexAttribPointer(corner, 2, gl.FLOAT, false, 0, 0);

		this.data = new Float32Array(MAX_INSTANCES * FLOATS_PER_INSTANCE);
		this.count = 0;
		this.instances = gl.createBuffer();
		gl.bindBuffer(gl.ARRAY_BUFFER, this.instances);
		gl.bufferData(gl.ARRAY_BUFFER, this.data.byteLength, gl.DYNAMIC_DRAW);

		const stride = FLOATS_PER_INSTANCE * 4;
		let offset = 0;
		for (const [name, size] of [
			['i_rect', 4], ['i_uv', 4], ['i_tint', 4], ['i_spin', 2],
		]) {
			const loc = gl.getAttribLocation(program, name);
			gl.enableVertexAttribArray(loc);
			gl.vertexAttribPointer(loc, size, gl.FLOAT, false, stride, offset);
			gl.vertexAttribDivisor(loc, 1);
			offset += size * 4;
		}
		gl.bindVertexArray(null);

		this.texture = gl.createTexture();
		gl.bindTexture(gl.TEXTURE_2D, this.texture);
		// NEAREST: the art is flat-vector pixel work and must not be smoothed.
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
		gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, atlas.image);

		gl.enable(gl.BLEND);
		gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);

		this.camera = { x: 0, y: 0, zoom: 1 };
		this.time = 0;
		this.swaySpeed = 1.25;
		this.flash = 0;
		this.view = null; // null = whole canvas
	}

	/**
	 * Restricts drawing to a sub-rectangle of the canvas, in device pixels with
	 * the origin at the top-left. Lets one canvas and one GL context host a grid
	 * of independent little scenes - six enemy behaviours side by side - instead
	 * of spending a context and an atlas upload on each.
	 */
	viewport(x, y, w, h) {
		this.view = w > 0 && h > 0 ? { x, y, w, h } : null;
	}

	fullViewport() {
		this.view = null;
	}

	frame(key) {
		const f = this.frames[key];
		if (!f) throw new Error(`no atlas frame "${key}"`);
		return f;
	}

	/** Clears the batch. `camera` is world-space centre plus a zoom factor. */
	begin(camera = this.camera) {
		this.camera = camera;
		this.count = 0;
	}

	/**
	 * Queues one sprite.
	 *  x, y     world position of the anchor
	 *  anchor   'center' (actors) | 'base' (props standing on the ground) | 'topleft'
	 *  scale    multiplies the sprite's native pixel size
	 *  sway     px of canopy lean; 0 for anything that should stand still
	 */
	sprite(key, x, y, opts = {}) {
		if (this.count >= MAX_INSTANCES) return;
		const f = this.frame(key);
		const scale = opts.scale ?? 1;
		const w = (opts.w ?? f.w) * scale;
		const h = (opts.h ?? f.h) * scale;
		const anchor = opts.anchor ?? 'center';

		let left = x, top = y;
		if (anchor === 'center') { left = x - w / 2; top = y - h / 2; }
		else if (anchor === 'base') { left = x - w / 2; top = y - h; }

		const c = opts.color ?? WHITE;
		const flip = opts.flip ? -1 : 1;
		const d = this.data;
		let i = this.count * FLOATS_PER_INSTANCE;
		d[i++] = left; d[i++] = top; d[i++] = w; d[i++] = h;
		if (flip < 0) {
			d[i++] = f.x + f.w; d[i++] = f.y; d[i++] = f.x; d[i++] = f.y + f.h;
		} else {
			d[i++] = f.x; d[i++] = f.y; d[i++] = f.x + f.w; d[i++] = f.y + f.h;
		}
		d[i++] = c[0]; d[i++] = c[1]; d[i++] = c[2]; d[i++] = c[3] ?? 1;
		d[i++] = opts.rot ?? 0; d[i++] = opts.sway ?? 0;
		this.count++;
	}

	/** A tinted rectangle, sampled from the atlas's flat white swatch. */
	rect(x, y, w, h, color, opts = {}) {
		this.sprite('white', x, y, {
			...opts, w, h, color, anchor: opts.anchor ?? 'topleft',
		});
	}

	/** A line segment of the given thickness between two world points. */
	line(x0, y0, x1, y1, thickness, color) {
		const dx = x1 - x0, dy = y1 - y0;
		const len = Math.hypot(dx, dy);
		if (len < 0.001) return;
		this.sprite('white', (x0 + x1) / 2, (y0 + y1) / 2, {
			w: len, h: thickness, color,
			rot: Math.atan2(dy, dx), anchor: 'center',
		});
	}

	/** A soft ring, used for telegraphs, blasts and pulses. */
	ring(x, y, radius, color, opts = {}) {
		this.sprite('ring', x, y, { ...opts, w: radius * 2, h: radius * 2, color });
	}

	glow(x, y, radius, color) {
		this.sprite('glow', x, y, { w: radius * 2, h: radius * 2, color });
	}

	flush() {
		const { gl } = this;
		gl.useProgram(this.program);
		gl.bindVertexArray(this.vao);
		gl.bindBuffer(gl.ARRAY_BUFFER, this.instances);
		gl.bufferSubData(
			gl.ARRAY_BUFFER, 0,
			this.data.subarray(0, this.count * FLOATS_PER_INSTANCE),
		);

		gl.activeTexture(gl.TEXTURE0);
		gl.bindTexture(gl.TEXTURE_2D, this.texture);
		gl.uniform1i(this.u.atlas, 0);
		gl.uniform2f(this.u.atlasSize, this.atlasSize[0], this.atlasSize[1]);

		const v = this.view;
		if (v) {
			// gl.viewport counts y from the bottom; the rest of the site thinks
			// in top-left screen space, so flip here and nowhere else.
			gl.viewport(v.x, this.canvas.height - v.y - v.h, v.w, v.h);
			gl.enable(gl.SCISSOR_TEST);
			gl.scissor(v.x, this.canvas.height - v.y - v.h, v.w, v.h);
		} else {
			gl.viewport(0, 0, this.canvas.width, this.canvas.height);
			gl.disable(gl.SCISSOR_TEST);
		}
		gl.uniform4f(
			this.u.view,
			this.camera.x, this.camera.y,
			v ? v.w : this.canvas.width,
			v ? v.h : this.canvas.height,
		);
		gl.uniform1f(this.u.zoom, this.camera.zoom ?? 1);
		gl.uniform1f(this.u.time, this.time);
		gl.uniform1f(this.u.swaySpeed, this.swaySpeed);
		gl.uniform1f(this.u.flash, this.flash);

		gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, this.count);
		gl.bindVertexArray(null);
	}

	/** Clears the current viewport, or the whole canvas if none is set. */
	clear(color) {
		const { gl } = this;
		const v = this.view;
		if (v) {
			gl.enable(gl.SCISSOR_TEST);
			gl.scissor(v.x, this.canvas.height - v.y - v.h, v.w, v.h);
		} else {
			gl.disable(gl.SCISSOR_TEST);
			gl.viewport(0, 0, this.canvas.width, this.canvas.height);
		}
		if (color) {
			gl.clearColor(color[0], color[1], color[2], color[3] ?? 1);
		} else {
			gl.clearColor(0, 0, 0, 0);
		}
		gl.clear(gl.COLOR_BUFFER_BIT);
	}

	dispose() {
		const { gl } = this;
		gl.deleteTexture(this.texture);
		gl.deleteBuffer(this.instances);
		gl.deleteVertexArray(this.vao);
		gl.deleteProgram(this.program);
		gl.getExtension('WEBGL_lose_context')?.loseContext();
	}
}

function buildProgram(gl, vertSrc, fragSrc) {
	const compile = (type, src) => {
		const sh = gl.createShader(type);
		gl.shaderSource(sh, src);
		gl.compileShader(sh);
		if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
			throw new Error(`shader: ${gl.getShaderInfoLog(sh)}`);
		}
		return sh;
	};
	const p = gl.createProgram();
	gl.attachShader(p, compile(gl.VERTEX_SHADER, vertSrc));
	gl.attachShader(p, compile(gl.FRAGMENT_SHADER, fragSrc));
	gl.linkProgram(p);
	if (!gl.getProgramParameter(p, gl.LINK_STATUS)) {
		throw new Error(`link: ${gl.getProgramInfoLog(p)}`);
	}
	return p;
}

// -- scene lifecycle ---------------------------------------------------------

export const REDUCED_MOTION =
	window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/**
 * Mounts a scene on a canvas and drives it.
 *
 * The RAF loop only runs while the canvas is on screen, so a page with five
 * scenes never animates more than the one or two you can actually see. With
 * reduced motion requested it draws a single frame and stops. If WebGL2 is
 * unavailable the canvas is replaced by its data-fallback screenshot, so the
 * page degrades into an ordinary illustrated one rather than showing holes.
 */
export async function mount(canvas, factory) {
	let atlas;
	try {
		atlas = await loadAtlas();
	} catch (err) {
		return degrade(canvas, err);
	}

	let renderer;
	let scene;
	try {
		renderer = new Renderer(canvas, atlas);
		scene = factory(renderer);
	} catch (err) {
		return degrade(canvas, err);
	}

	const resize = () => {
		const dpr = Math.min(window.devicePixelRatio || 1, 2);
		const rect = canvas.getBoundingClientRect();
		const w = Math.max(1, Math.round(rect.width * dpr));
		const h = Math.max(1, Math.round(rect.height * dpr));
		if (canvas.width !== w || canvas.height !== h) {
			canvas.width = w;
			canvas.height = h;
			scene.resize?.(w, h, dpr);
		}
	};
	new ResizeObserver(resize).observe(canvas);
	resize();

	let raf = 0;
	let last = 0;
	let visible = false;

	const draw = (now) => {
		raf = 0;
		// Clamp: a tab restored after a minute must not advance an hour of sim.
		const dt = last ? Math.min((now - last) / 1000, 1 / 20) : 1 / 60;
		last = now;
		renderer.time += dt;
		try {
			scene.update?.(dt);
			scene.draw();
		} catch (err) {
			// A throwing scene would otherwise stop its own loop and leave a
			// blank rectangle with no explanation. Say so, once, and fall back to
			// the screenshot like any other failure.
			console.error('[slimer] scene crashed, falling back:', err);
			visible = false;
			degrade(canvas, err);
			return;
		}
		if (visible) raf = requestAnimationFrame(draw);
	};

	const start = () => {
		if (raf || !visible) return;
		last = 0;
		raf = requestAnimationFrame(draw);
	};
	const stop = () => {
		if (raf) cancelAnimationFrame(raf);
		raf = 0;
	};

	if (REDUCED_MOTION) {
		// One representative frame: settle the sim, then draw once.
		for (let i = 0; i < 90; i++) scene.update?.(1 / 60);
		renderer.time = 1.7;
		scene.draw();
		canvas.dataset.static = 'true';
	} else {
		new IntersectionObserver((entries) => {
			visible = entries[0].isIntersecting;
			if (visible) start(); else stop();
		}, { rootMargin: '120px' }).observe(canvas);
		document.addEventListener('visibilitychange', () => {
			if (document.hidden) stop(); else start();
		});
	}

	return { renderer, scene, canvas };
}

function degrade(canvas, err) {
	console.warn('[slimer] scene fell back to a screenshot:', err.message);
	const src = canvas.dataset.fallback;
	if (src) {
		const img = document.createElement('img');
		img.src = src;
		img.alt = canvas.dataset.fallbackAlt || '';
		img.className = canvas.className;
		img.loading = 'lazy';
		canvas.replaceWith(img);
	} else {
		canvas.remove();
	}
	return null;
}

// -- shared helpers ----------------------------------------------------------

export const WHITE = [1, 1, 1, 1];

/** '#rrggbb' or '#rrggbbaa' to the [0..1] float tuple the renderer wants. */
export function rgb(hex, alpha = 1) {
	const h = hex.replace('#', '');
	return [
		parseInt(h.slice(0, 2), 16) / 255,
		parseInt(h.slice(2, 4), 16) / 255,
		parseInt(h.slice(4, 6), 16) / 255,
		h.length >= 8 ? parseInt(h.slice(6, 8), 16) / 255 : alpha,
	];
}

export function withAlpha(color, alpha) {
	return [color[0], color[1], color[2], alpha];
}

/**
 * Deterministic PRNG (mulberry32). The forest generator's whole point is that
 * a seed reproduces a map, so the visualiser must be seeded too.
 */
export function rng(seed) {
	let a = seed >>> 0;
	return () => {
		a = (a + 0x6d2b79f5) >>> 0;
		let t = Math.imul(a ^ (a >>> 15), 1 | a);
		t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

export const lerp = (a, b, t) => a + (b - a) * t;
export const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
export const TAU = Math.PI * 2;
