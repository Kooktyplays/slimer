// Hero scene: a slice of forest that behaves like the real one.
//
// Ground is tiled from the game's four 256px tiles, props are scattered on the
// same jittered grid the generator uses, everything with a canopy sways out of
// phase, and a dozen slimes wander at their real per-colour speeds. The camera
// drifts slowly so the parallax reads without anyone touching it.

import { rgb, rng, TAU, clamp } from '../gl.js';
import { ENEMIES, PALETTE } from '../data.js';

const GROUND = rgb(PALETTE.clear);

// Trees and rocks block; grass, bushes and ferns are cover you run through.
// The scene keeps that promise visually, so it reads the way the game plays.
const CANOPY = [
	{ key: 'tree_round_a', sway: 5.0, scale: 1.0 },
	{ key: 'tree_round_b', sway: 5.0, scale: 1.0 },
	{ key: 'tree_pine', sway: 3.2, scale: 1.0 },
	{ key: 'tree_dead', sway: 2.0, scale: 0.95 },
];
const UNDERGROWTH = [
	{ key: 'bush_a', sway: 3.4 }, { key: 'bush_b', sway: 3.4 },
	{ key: 'bush_c', sway: 2.8 }, { key: 'fern', sway: 3.0 },
	{ key: 'grass_a', sway: 2.2 }, { key: 'grass_b', sway: 2.2 },
	{ key: 'grass_c', sway: 2.2 }, { key: 'flower_a', sway: 1.8 },
	{ key: 'flower_b', sway: 1.8 }, { key: 'mushroom', sway: 0 },
];
const BLOCKERS = [
	{ key: 'rock_a' }, { key: 'rock_b' }, { key: 'rock_c' },
	{ key: 'log_a' }, { key: 'log_b' }, { key: 'stump' }, { key: 'pebbles' },
];

// Sized so the world edge never drifts into view, even on a very wide monitor:
// the visible width is cssWidth / ZOOM_PER_DPR, plus the camera's drift.
const WORLD = { w: 6400, h: 4200 };
const TILE = 256;

// Trees should look the same size on a phone and a desktop. The projection works
// in device pixels, so the zoom has to scale with devicePixelRatio to hold a
// constant apparent size - at 0.34 a tree is about 51 CSS px across.
const ZOOM_PER_DPR = 0.34;

// Three clearings joined by paths and one pond - a hand-placed miniature of
// what ForestGenerator builds from a seed.
const CLEARING = { x: 3200, y: 2100, r: 700 };
const CLEARINGS = [
	CLEARING,
	{ x: 1250, y: 900, r: 440 },
	{ x: 5100, y: 3150, r: 480 },
];
const PATHS = [
	[CLEARINGS[1], { x: 2100, y: 1600 }, CLEARING],
	[CLEARING, { x: 4300, y: 2600 }, CLEARINGS[2]],
];
const POND = { x: 4950, y: 1100, r: 360 };
const PATH_HALF = 170 / 2;

function distToSegment(px, py, a, b) {
	const dx = b.x - a.x, dy = b.y - a.y;
	const len2 = dx * dx + dy * dy;
	const t = len2 ? clamp(((px - a.x) * dx + (py - a.y) * dy) / len2, 0, 1) : 0;
	return Math.hypot(px - (a.x + dx * t), py - (a.y + dy * t));
}

function pathDistance(x, y) {
	let best = Infinity;
	for (const poly of PATHS) {
		for (let i = 0; i < poly.length - 1; i++) {
			best = Math.min(best, distToSegment(x, y, poly[i], poly[i + 1]));
		}
	}
	return best;
}

function clearingDepth(x, y) {
	// Positive inside a clearing, scaled 0..1 by how deep in it you are.
	let best = -Infinity;
	for (const c of CLEARINGS) {
		best = Math.max(best, 1 - Math.hypot(x - c.x, y - c.y) / c.r);
	}
	return best;
}

export function heroScene(r) {
	const rand = rng(0x51e3);
	const props = [];
	const tiles = [];

	// Ground, painted in three passes so each surface keeps its real shape.
	//
	// Grass is a plain 256px grid. Clearings and the pond are stamped on a finer
	// grid with a jittered radius, so the edge reads as ragged rather than as a
	// staircase. Paths are stamped *along* their polyline at their true 170px
	// width - classifying them on the coarse grid broke them into a dotted line
	// of disconnected squares.
	for (let y = -TILE; y < WORLD.h + TILE; y += TILE) {
		for (let x = -TILE; x < WORLD.w + TILE; x += TILE) {
			tiles.push({ key: 'ground_grass', x, y, size: TILE });
		}
	}

	const PATH_STEP = 110;
	for (const poly of PATHS) {
		for (let i = 0; i < poly.length - 1; i++) {
			const a = poly[i], b = poly[i + 1];
			const len = Math.hypot(b.x - a.x, b.y - a.y);
			const steps = Math.ceil(len / PATH_STEP);
			for (let s = 0; s <= steps; s++) {
				const t = s / steps;
				tiles.push({
					key: 'ground_path', size: PATH_HALF * 2,
					x: a.x + (b.x - a.x) * t - PATH_HALF,
					y: a.y + (b.y - a.y) * t - PATH_HALF,
				});
			}
		}
	}

	// Cell size trades quad count against how round the edge looks. The pond is
	// the smallest shape here, so it needs the finest grid to stop reading as a
	// rectangle.
	const stampDisc = (c, key, cell, squashY = 1) => {
		for (let y = c.y - c.r - cell; y < c.y + c.r + cell; y += cell) {
			for (let x = c.x - c.r - cell; x < c.x + c.r + cell; x += cell) {
				const cx = x + cell / 2, cy = y + cell / 2;
				const d = Math.hypot(cx - c.x, (cy - c.y) / squashY) / c.r;
				if (d > 1 + (rand() - 0.5) * 0.16) continue;
				tiles.push({ key, x, y, size: cell });
			}
		}
	};
	for (const c of CLEARINGS) stampDisc(c, 'ground_clearing', 96);
	stampDisc(POND, 'ground_water', 56, 0.82);

	// Brown and grey stop you, green does not: nothing that blocks may stand in
	// a clearing, on a path, or in the water.
	const open = (x, y, pad = 0) =>
		clearingDepth(x, y) < -pad / 600
		&& pathDistance(x, y) > PATH_HALF + pad
		&& Math.hypot(x - POND.x, y - POND.y) > POND.r + pad;

	// Jittered grid, like ForestGenerator's scatter pass: regular enough to
	// leave gaps you can walk through, irregular enough not to look planted.
	const scatter = (spacing, jitter, pick, chance, pad) => {
		for (let y = 40; y < WORLD.h; y += spacing) {
			for (let x = 40; x < WORLD.w; x += spacing) {
				if (rand() > chance) continue;
				const px = x + (rand() - 0.5) * jitter;
				const py = y + (rand() - 0.5) * jitter;
				if (!open(px, py, pad)) continue;
				const def = pick[(rand() * pick.length) | 0];
				props.push({
					...def, x: px, y: py,
					scale: (def.scale ?? 1) * (0.86 + rand() * 0.3),
					tint: 0.86 + rand() * 0.14,
				});
			}
		}
	};
	// The generator's own three passes: trees 168, scatter 132, detail 108.
	scatter(168, 132, CANOPY, 0.82, 90);
	scatter(132, 118, BLOCKERS, 0.30, 40);
	scatter(108, 96, UNDERGROWTH, 0.70, 0);

	// Lilypads and reeds only make sense on the water's edge.
	for (let i = 0; i < 22; i++) {
		const a = rand() * TAU;
		const d = POND.r * (0.25 + rand() * 0.7);
		props.push({
			key: rand() < 0.55 ? 'lilypad' : 'reeds',
			x: POND.x + Math.cos(a) * d,
			y: POND.y + Math.sin(a) * d * 0.8,
			scale: 0.85 + rand() * 0.35, sway: 2.4, tint: 1,
		});
	}
	// A campfire and a lantern mark the far clearing, the way the shop point does.
	props.push({ key: 'campfire', x: CLEARINGS[2].x, y: CLEARINGS[2].y, scale: 1, sway: 0, tint: 1 });
	props.push({ key: 'shop_lantern', x: CLEARINGS[2].x + 150, y: CLEARINGS[2].y - 40, scale: 1, sway: 1.2, tint: 1 });

	props.sort((a, b) => a.y - b.y); // painter's order: further back draws first

	// Wandering slimes, at the speeds enemy_types.gd actually gives them.
	const slimes = [];
	for (let i = 0; i < 14; i++) {
		const type = ENEMIES[(rand() * ENEMIES.length) | 0];
		const a = rand() * TAU;
		const dist = rand() * CLEARING.r * 0.8;
		slimes.push({
			type,
			x: CLEARING.x + Math.cos(a) * dist,
			y: CLEARING.y + Math.sin(a) * dist,
			dir: rand() * TAU,
			turn: 0,
			bob: rand() * TAU,
			elite: rand() < 0.22,
		});
	}

	const leaves = [];
	for (let i = 0; i < 34; i++) {
		leaves.push({
			key: `leaf_${(rand() * 3) | 0}`,
			x: rand() * WORLD.w, y: rand() * WORLD.h,
			vx: 18 + rand() * 30, vy: 8 + rand() * 16,
			rot: rand() * TAU, spin: (rand() - 0.5) * 1.4,
			scale: 0.7 + rand() * 0.6,
		});
	}

	let t = 0;
	const cam = { x: CLEARING.x, y: CLEARING.y, zoom: 1 };

	return {
		resize(w, h, dpr) {
			// Constant apparent tree size at any density or window shape - a
			// canvas-relative zoom turned the forest into wallpaper on mobile.
			cam.zoom = clamp(dpr * ZOOM_PER_DPR, 0.3, 1.1);
		},

		update(dt) {
			t += dt;

			// A slow lissajous drift: motion without a destination.
			cam.x = CLEARING.x + Math.sin(t * 0.043) * 420;
			cam.y = CLEARING.y + Math.cos(t * 0.031) * 240;

			for (const s of slimes) {
				s.turn -= dt;
				if (s.turn <= 0) {
					s.turn = 1.4 + Math.random() * 2.6;
					s.dir += (Math.random() - 0.5) * 2.4;
				}
				const speed = s.type.speed * (s.elite ? 1.0 : 0.55);
				s.x += Math.cos(s.dir) * speed * dt;
				s.y += Math.sin(s.dir) * speed * dt;
				// Keep them loosely in the clearing - they are set dressing.
				const d = Math.hypot(s.x - CLEARING.x, s.y - CLEARING.y);
				if (d > CLEARING.r * 0.86) {
					s.dir = Math.atan2(CLEARING.y - s.y, CLEARING.x - s.x)
						+ (Math.random() - 0.5) * 0.8;
				}
				s.bob += dt * 7;
			}

			for (const l of leaves) {
				l.x += l.vx * dt;
				l.y += l.vy * dt;
				l.rot += l.spin * dt;
				if (l.x > WORLD.w + 60) { l.x = -60; l.y = Math.random() * WORLD.h; }
				if (l.y > WORLD.h + 60) { l.y = -60; }
			}
		},

		draw() {
			r.clear(GROUND);
			r.begin(cam);

			for (const tile of tiles) {
				r.sprite(tile.key, tile.x, tile.y, {
					anchor: 'topleft', w: tile.size, h: tile.size,
				});
			}

			// Props and slimes interleave by depth so slimes pass behind trunks.
			let pi = 0;
			const drawProp = (p) => {
				const shade = [p.tint, p.tint, p.tint, 1];
				r.sprite(p.key, p.x, p.y, {
					anchor: 'base', scale: p.scale, sway: p.sway ?? 0, color: shade,
				});
			};

			const ordered = [...slimes].sort((a, b) => a.y - b.y);
			for (const s of ordered) {
				while (pi < props.length && props[pi].y < s.y) drawProp(props[pi++]);
				drawSlime(r, s);
			}
			while (pi < props.length) drawProp(props[pi++]);

			for (const l of leaves) {
				r.sprite(l.key, l.x, l.y, {
					rot: l.rot, scale: l.scale, color: [1, 1, 1, 0.75],
				});
			}

			r.flush();
		},
	};
}

/**
 * One slime: shadow, squash-stretched body, eyes, crown if it is an elite.
 *
 * The enemy bodies and crowns are already the right colour on disc - gen_art.py
 * hue-rotates them per colour - so they draw untinted. Tinting them again would
 * double the hue shift.
 */
export function drawSlime(r, s, extraScale = 1) {
	const { type } = s;
	const scale = type.scale * (s.elite ? 1.32 : 1) * extraScale;
	const squash = 1 + Math.sin(s.bob) * 0.07;

	r.sprite('shadow', s.x, s.y, { scale: scale * 0.95, color: [0, 0, 0, 0.26] });
	r.sprite(`enemy_${type.id}`, s.x, s.y + 6, {
		anchor: 'base', scale,
		w: 108 / squash, h: 90 * squash,
	});
	r.sprite(s.elite ? 'eyes_angry' : 'slime_face', s.x, s.y - 44 * scale * squash, {
		scale: scale * 0.92,
	});
	if (s.elite) {
		r.sprite(`crown_${type.id}`, s.x, s.y + 6, {
			anchor: 'base', scale, w: 108 / squash, h: 90 * squash,
		});
	}
}
