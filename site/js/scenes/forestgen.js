// Forest generator scene: the real algorithm, animated through its six steps.
//
// A port of world/forest_generator.gd on the actual 4800 x 3700 arena, with the
// actual constants from data. Reseed it and you get a different, still-valid
// forest - which is the point the game makes 200 times over in its test sweep.
//
// Steps, in the order the generator runs them:
//   1  scatter 9-13 clearings, radius 300-470, min separation 720
//   2  relax them apart
//   3  connect with paths of width 170 - a minimum spanning tree, plus 3 extra
//      loop edges, so the map has loops to circle-strafe rather than dead ends
//   4  stamp 2-4 ponds, never on a clearing or a path
//   5  scatter trees / rocks / logs / bushes on a jittered grid
//   6  rasterise every blocker into a 64px walkable grid, inflated by the 46px
//      actor clearance, then flood-fill from spawn to prove it all connects
//
// If validation fails the real generator widens chokepoints and reseeds, up to
// six attempts. The 200-seed sweep in tests/test_forest.gd passes on the first
// attempt every time, so this visualiser shows the first attempt too.

import { rgb, rng, TAU, clamp, withAlpha } from '../gl.js';
import { FOREST, PALETTE } from '../data.js';

const GROUND = rgb(PALETTE.clear);
const GOLD = rgb(PALETTE.gold);
const BORDER = rgb(PALETTE.border);
const BLUE = rgb(PALETTE.blue);

const STEP_NAMES = [
	'1 — scatter clearings',
	'2 — relax them apart',
	'3 — connect: spanning tree + 3 loops',
	'4 — stamp ponds',
	'5 — scatter props',
	'6 — rasterise and flood-fill',
];

const TREES = ['tree_round_a', 'tree_round_b', 'tree_pine', 'tree_dead'];
const ROCKS = ['rock_a', 'rock_b', 'rock_c', 'log_a', 'log_b', 'stump'];
const SOFT = ['bush_a', 'bush_b', 'bush_c', 'fern', 'grass_a', 'grass_b', 'grass_c'];

/** Generates one complete forest from a seed. Pure data, like the original. */
export function generateForest(seed) {
	const rand = rng(seed);
	const F = FOREST;
	const inner = {
		x0: F.border, y0: F.border,
		x1: F.width - F.border, y1: F.height - F.border,
	};

	// 1 - scatter clearings, rejecting any that crowd an existing one.
	const count = F.clearings[0] + Math.floor(rand() * (F.clearings[1] - F.clearings[0] + 1));
	const clearings = [];
	for (let attempt = 0; attempt < 400 && clearings.length < count; attempt++) {
		const r = F.clearingRadius[0] + rand() * (F.clearingRadius[1] - F.clearingRadius[0]);
		const c = {
			x: inner.x0 + r + rand() * (inner.x1 - inner.x0 - r * 2),
			y: inner.y0 + r + rand() * (inner.y1 - inner.y0 - r * 2),
			r,
		};
		if (clearings.every((o) => Math.hypot(o.x - c.x, o.y - c.y) > F.clearingSeparation)) {
			clearings.push(c);
		}
	}

	// 2 - relax: push overlapping neighbours apart, a few passes.
	const scattered = clearings.map((c) => ({ ...c }));
	for (let pass = 0; pass < 12; pass++) {
		for (let i = 0; i < clearings.length; i++) {
			for (let j = i + 1; j < clearings.length; j++) {
				const a = clearings[i], b = clearings[j];
				const dx = b.x - a.x, dy = b.y - a.y;
				const d = Math.hypot(dx, dy) || 1;
				const want = F.clearingSeparation;
				if (d < want) {
					const push = (want - d) * 0.5;
					a.x -= (dx / d) * push; a.y -= (dy / d) * push;
					b.x += (dx / d) * push; b.y += (dy / d) * push;
				}
			}
			const c = clearings[i];
			c.x = clamp(c.x, inner.x0 + c.r, inner.x1 - c.r);
			c.y = clamp(c.y, inner.y0 + c.r, inner.y1 - c.r);
		}
	}

	// 3 - minimum spanning tree over the clearings (Prim), then extra loops.
	const edges = [];
	const inTree = new Set([0]);
	while (inTree.size < clearings.length) {
		let best = null;
		for (const i of inTree) {
			for (let j = 0; j < clearings.length; j++) {
				if (inTree.has(j)) continue;
				const d = Math.hypot(clearings[i].x - clearings[j].x, clearings[i].y - clearings[j].y);
				if (!best || d < best.d) best = { i, j, d };
			}
		}
		if (!best) break;
		edges.push([best.i, best.j]);
		inTree.add(best.j);
	}
	const tree = edges.length;
	// The loop edges: shortest pairs not already joined, so the map has cycles.
	const candidates = [];
	for (let i = 0; i < clearings.length; i++) {
		for (let j = i + 1; j < clearings.length; j++) {
			if (edges.some(([a, b]) => (a === i && b === j) || (a === j && b === i))) continue;
			candidates.push({
				i, j,
				d: Math.hypot(clearings[i].x - clearings[j].x, clearings[i].y - clearings[j].y),
			});
		}
	}
	candidates.sort((a, b) => a.d - b.d);
	for (const c of candidates.slice(0, F.extraLoopEdges)) edges.push([c.i, c.j]);

	// 4 - ponds, never on a clearing or a path.
	const onPath = (x, y, pad) => edges.some(([a, b]) =>
		distToSegment(x, y, clearings[a], clearings[b]) < F.pathWidth / 2 + pad);
	const inClearing = (x, y, pad) =>
		clearings.some((c) => Math.hypot(x - c.x, y - c.y) < c.r + pad);

	const pondCount = F.ponds[0] + Math.floor(rand() * (F.ponds[1] - F.ponds[0] + 1));
	const ponds = [];
	for (let attempt = 0; attempt < 300 && ponds.length < pondCount; attempt++) {
		const r = F.pondRadius[0] + rand() * (F.pondRadius[1] - F.pondRadius[0]);
		const x = inner.x0 + r + rand() * (inner.x1 - inner.x0 - r * 2);
		const y = inner.y0 + r + rand() * (inner.y1 - inner.y0 - r * 2);
		if (inClearing(x, y, r) || onPath(x, y, r)) continue;
		if (ponds.some((p) => Math.hypot(p.x - x, p.y - y) < p.r + r + 200)) continue;
		ponds.push({ x, y, r });
	}

	// 5 - scatter props on a jittered grid, three passes at three spacings.
	const open = (x, y, pad) =>
		!inClearing(x, y, pad) && !onPath(x, y, pad)
		&& !ponds.some((p) => Math.hypot(x - p.x, y - p.y) < p.r + pad);

	const props = [];
	const scatter = (spacing, jitter, keys, chance, pad, blocks) => {
		for (let y = F.border * 0.4; y < F.height - F.border * 0.4; y += spacing) {
			for (let x = F.border * 0.4; x < F.width - F.border * 0.4; x += spacing) {
				if (rand() > chance) continue;
				const px = x + (rand() - 0.5) * jitter;
				const py = y + (rand() - 0.5) * jitter;
				if (!open(px, py, pad)) continue;
				props.push({
					key: keys[(rand() * keys.length) | 0],
					x: px, y: py, blocks,
					scale: 0.85 + rand() * 0.3,
				});
			}
		}
	};
	// The impassable tree wall around the arena border comes first.
	for (let i = 0; i < 900; i++) {
		const edge = i % 4;
		const t = rand();
		const depth = rand() * F.border;
		let x, y;
		if (edge === 0) { x = t * F.width; y = depth; }
		else if (edge === 1) { x = t * F.width; y = F.height - depth; }
		else if (edge === 2) { x = depth; y = t * F.height; }
		else { x = F.width - depth; y = t * F.height; }
		props.push({
			key: TREES[(rand() * TREES.length) | 0],
			x, y, blocks: true, scale: 0.9 + rand() * 0.3, wall: true,
		});
	}
	scatter(F.treeSpacing, 132, TREES, 0.8, 90, true);
	scatter(F.scatterSpacing, 118, ROCKS, 0.26, 40, true);
	scatter(F.detailSpacing, 96, SOFT, 0.55, 0, false);

	// 6 - rasterise blockers into the walkable grid, inflated by actor clearance,
	// then flood-fill from the spawn clearing.
	const cols = Math.ceil(F.width / F.gridCell);
	const rows = Math.ceil(F.height / F.gridCell);
	const walkable = new Uint8Array(cols * rows).fill(1);
	const blockAt = (x, y, radius) => {
		const rr = radius + F.actorClearance;
		const c0 = Math.max(0, Math.floor((x - rr) / F.gridCell));
		const c1 = Math.min(cols - 1, Math.floor((x + rr) / F.gridCell));
		const r0 = Math.max(0, Math.floor((y - rr) / F.gridCell));
		const r1 = Math.min(rows - 1, Math.floor((y + rr) / F.gridCell));
		for (let ry = r0; ry <= r1; ry++) {
			for (let cx = c0; cx <= c1; cx++) walkable[ry * cols + cx] = 0;
		}
	};
	for (const p of props) if (p.blocks) blockAt(p.x, p.y, 38 * p.scale);
	for (const p of ponds) blockAt(p.x, p.y, p.r * 0.9);

	// Flood fill from the largest clearing - the spawn.
	const spawn = clearings.reduce((a, b) => (b.r > a.r ? b : a), clearings[0]);
	const reached = new Uint8Array(cols * rows);
	const startC = clamp(Math.floor(spawn.x / F.gridCell), 0, cols - 1);
	const startR = clamp(Math.floor(spawn.y / F.gridCell), 0, rows - 1);
	const queue = [startR * cols + startC];
	reached[queue[0]] = 1;
	let head = 0;
	while (head < queue.length) {
		const idx = queue[head++];
		const cx = idx % cols, cy = (idx / cols) | 0;
		for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
			const nx = cx + dx, ny = cy + dy;
			if (nx < 0 || ny < 0 || nx >= cols || ny >= rows) continue;
			const n = ny * cols + nx;
			if (reached[n] || !walkable[n]) continue;
			reached[n] = 1;
			queue.push(n);
		}
	}

	// Validation, as the generator states it: every clearing reachable, and none
	// below MIN_CLEARING_OPEN_CELLS of fightable space.
	const openCells = clearings.map((c) => {
		let n = 0;
		const rr = c.r;
		const c0 = Math.max(0, Math.floor((c.x - rr) / F.gridCell));
		const c1 = Math.min(cols - 1, Math.floor((c.x + rr) / F.gridCell));
		const r0 = Math.max(0, Math.floor((c.y - rr) / F.gridCell));
		const r1 = Math.min(rows - 1, Math.floor((c.y + rr) / F.gridCell));
		for (let ry = r0; ry <= r1; ry++) {
			for (let cx = c0; cx <= c1; cx++) if (reached[ry * cols + cx]) n++;
		}
		return n;
	});
	const valid = openCells.every((n) => n >= FOREST.minClearingOpenCells);

	return {
		seed, clearings, scattered, edges, tree, ponds, props,
		walkable, reached, cols, rows, spawn, openCells, valid,
		reachedCount: reached.reduce((a, b) => a + b, 0),
	};
}

function distToSegment(px, py, a, b) {
	const dx = b.x - a.x, dy = b.y - a.y;
	const len2 = dx * dx + dy * dy;
	const t = len2 ? clamp(((px - a.x) * dx + (py - a.y) * dy) / len2, 0, 1) : 0;
	return Math.hypot(px - (a.x + dx * t), py - (a.y + dy * t));
}

/**
 * @param labelEl  element that gets the current step's name
 * @param statEl   element that gets the seed and the validation result
 * @param onSeed   called with the forest when a new one is generated
 */
export function forestGenScene(labelEl, statEl, onSeed) {
	return (r) => {
		const F = FOREST;
		let forest = generateForest((Math.random() * 0xffffff) | 0);
		let step = 0;
		let clock = 0;
		let reveal = 0;

		const announce = () => {
			if (labelEl) labelEl.textContent = STEP_NAMES[step];
			if (statEl) {
				statEl.textContent =
					`seed ${forest.seed} · ${forest.clearings.length} clearings · `
					+ `${forest.tree} tree edges + ${F.extraLoopEdges} loops · `
					+ `${forest.ponds.length} ponds · ${forest.props.length} props · `
					+ (forest.valid ? 'valid on the first attempt' : 'rejected — reseeding');
			}
			onSeed?.(forest);
		};
		announce();

		const reseed = (seed) => {
			forest = generateForest(seed ?? ((Math.random() * 0xffffff) | 0));
			step = 0;
			clock = 0;
			reveal = 0;
			announce();
		};

		return {
			reseed,

			update(dt) {
				clock += dt;
				reveal = clamp(reveal + dt * 1.6, 0, 1);
				const hold = step === 5 ? 3.4 : 1.9;
				if (clock > hold) {
					clock = 0;
					reveal = 0;
					if (step === STEP_NAMES.length - 1) reseed();
					else { step++; announce(); }
				}
			},

			draw() {
				r.clear(GROUND);
				// Fit the whole 4800x3700 arena, whatever the canvas shape.
				const zoom = Math.min(
					r.canvas.width / (F.width * 1.04),
					r.canvas.height / (F.height * 1.04),
				);
				r.begin({ x: F.width / 2, y: F.height / 2, zoom });

				// The arena and its impassable border.
				r.rect(0, 0, F.width, F.height, withAlpha(BORDER, 0.10));
				r.rect(F.border, F.border, F.width - F.border * 2, F.height - F.border * 2,
					withAlpha(GROUND, 0.6));

				// Step 6 draws the walkable grid underneath everything else.
				if (step >= 5) {
					const cell = F.gridCell;
					for (let ry = 0; ry < forest.rows; ry++) {
						for (let cx = 0; cx < forest.cols; cx++) {
							const i = ry * forest.cols + cx;
							if (!forest.walkable[i]) continue;
							const lit = forest.reached[i];
							// The flood fill spreads outward from spawn over the hold.
							const d = Math.hypot(cx * cell - forest.spawn.x, ry * cell - forest.spawn.y);
							if (lit && d > reveal * 6200) continue;
							r.rect(cx * cell + 3, ry * cell + 3, cell - 6, cell - 6,
								lit ? withAlpha(GOLD, 0.30) : withAlpha(BLUE, 0.06));
						}
					}
				}

				// Step 1 shows where the clearings landed before relaxation.
				if (step === 0 || step === 1) {
					for (const c of forest.scattered) {
						r.ring(c.x, c.y, c.r, withAlpha(BLUE, step === 0 ? 0.5 : 0.18));
					}
				}

				const clearingsVisible = step >= 1;
				if (clearingsVisible) {
					for (const c of forest.clearings) {
						r.glow(c.x, c.y, c.r, withAlpha(GOLD, 0.14));
						r.ring(c.x, c.y, c.r, withAlpha(GOLD, 0.55));
					}
				}

				// Step 3: spanning tree in gold, the three loop edges in blue, so
				// the thing that turns a tree into a network is visible.
				if (step >= 2) {
					forest.edges.forEach(([a, b], i) => {
						const A = forest.clearings[a], B = forest.clearings[b];
						const isLoop = i >= forest.tree;
						const grow = step === 2 ? clamp(reveal * forest.edges.length - i, 0, 1) : 1;
						if (grow <= 0) return;
						r.line(A.x, A.y, A.x + (B.x - A.x) * grow, A.y + (B.y - A.y) * grow,
							F.pathWidth, isLoop ? withAlpha(BLUE, 0.55) : withAlpha(GOLD, 0.34));
					});
				}

				if (step >= 3) {
					for (const p of forest.ponds) {
						r.glow(p.x, p.y, p.r * 1.1, withAlpha(BLUE, 0.35));
						r.ring(p.x, p.y, p.r, withAlpha(BLUE, 0.7));
					}
				}

				// Step 5 onward: the actual props, at real positions.
				if (step >= 4) {
					const n = step === 4 ? Math.floor(forest.props.length * reveal) : forest.props.length;
					for (let i = 0; i < n; i++) {
						const p = forest.props[i];
						r.sprite(p.key, p.x, p.y, {
							anchor: 'base', scale: p.scale * 1.9,
							sway: p.blocks ? 0 : 2.0,
							color: p.wall ? [0.72, 0.78, 0.72, 1] : [1, 1, 1, 1],
						});
					}
				}

				// The spawn point.
				if (step >= 1) {
					r.ring(forest.spawn.x, forest.spawn.y, 150 + Math.sin(clock * 4) * 24,
						withAlpha(GOLD, 0.9));
				}

				r.flush();
			},
		};
	};
}
