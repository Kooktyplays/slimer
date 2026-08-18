// Roster scene: each of the six colours acting out its own behaviour tag.
//
// One canvas, six viewports - the cells are measured off the HTML cards that sit
// on top, so the WebGL grid tracks whatever the CSS layout does at any width.
//
// Distances are the real ones from enemy_types.gd (the spitter really does hold
// 420 px and retreat at 260), but every actor is drawn at DISPLAY_SCALE so a
// slime is legible in a card-sized cell. The cards carry the true numbers.

import { rgb, TAU, clamp, withAlpha } from '../gl.js';
import { ENEMIES, PALETTE, BALANCE } from '../data.js';
import { drawSlime } from './hero.js';

const DISPLAY_SCALE = 2.2;
const CELL_WORLD = 950;       // world px across a cell's short dimension
// The bottom of each card is its name, hint and stat block, and the card is
// painted *over* this canvas - so the sim only gets the top slice, and actors
// are kept well inside it. The card's background gradient in site.css must stay
// transparent across this whole band or the sim disappears behind it.
const SIM_BAND = 0.52;
const Y_SPREAD = 0.5;   // fraction of the cell half-extent actors may use
const GROUND = rgb(PALETTE.clear);
const GOLD = rgb(PALETTE.gold);
const RED = rgb(PALETTE.red);

export function rosterScene(cells) {
	return (r) => {
		const sims = ENEMIES.map((type) => makeSim(type));
		let rects = [];

		const measure = () => {
			const dpr = Math.min(window.devicePixelRatio || 1, 2);
			const base = r.canvas.getBoundingClientRect();
			rects = cells.map((el) => {
				const b = el.getBoundingClientRect();
				return {
					x: Math.round((b.left - base.left) * dpr),
					y: Math.round((b.top - base.top) * dpr),
					w: Math.round(b.width * dpr),
					h: Math.round(b.height * SIM_BAND * dpr),
				};
			});
		};

		return {
			resize: measure,

			update(dt) {
				// Cards reflow on font load and orientation change; cheap to redo.
				if (rects.length !== cells.length) measure();
				for (const s of sims) s.update(dt);
			},

			draw() {
				r.fullViewport();
				r.clear(null);
				measure();
				for (let i = 0; i < sims.length; i++) {
					const rect = rects[i];
					if (!rect || rect.w <= 0 || rect.h <= 0) continue;
					r.viewport(rect.x, rect.y, rect.w, rect.h);
					r.clear(GROUND);
					const zoom = Math.min(rect.w, rect.h) / CELL_WORLD;
					r.begin({ x: 0, y: 0, zoom });
					sims[i].draw(r);
					r.flush();
				}
				r.fullViewport();
			},
		};
	};
}

/**
 * One cell: a dummy player at the origin and a single enemy running the real
 * steering rule for its behaviour tag. Each sim resets itself on a loop so the
 * card always has something happening in it.
 */
function makeSim(type) {
	const player = { x: 0, y: 0, aim: 0, bob: 0, kick: 0 };
	const half = CELL_WORLD / 2 - 60;

	let e, bullets, blasts, sparks, t, playerHit;

	const reset = () => {
		const a = Math.random() * TAU;
		const d = type.behaviour === 'skittish' ? 240 : half * 0.92;
		e = {
			type, x: Math.cos(a) * d, y: Math.sin(a) * d * Y_SPREAD,
			bob: Math.random() * TAU, elite: false,
			hp: 1, fuse: 0, cooldown: 0.8, flash: 0, dead: 0,
			flankSide: Math.random() < 0.5 ? 1 : -1,
		};
		bullets = [];
		blasts = [];
		sparks = [];
		t = 0;
		playerHit = 0;
	};
	reset();

	const spark = (x, y, colour, n = 8) => {
		for (let i = 0; i < n; i++) {
			const a = Math.random() * TAU;
			const sp = 90 + Math.random() * 220;
			sparks.push({
				x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp,
				life: 0.3 + Math.random() * 0.3, age: 0, colour,
			});
		}
	};

	const update = (dt) => {
		t += dt;
		player.bob += dt * 3;
		player.kick = Math.max(0, player.kick - dt * 6);
		playerHit = Math.max(0, playerHit - dt);
		e.flash = Math.max(0, e.flash - dt * 5);

		const dx = player.x - e.x, dy = player.y - e.y;
		const dist = Math.hypot(dx, dy) || 1;
		const ux = dx / dist, uy = dy / dist;
		player.aim = Math.atan2(e.y - player.y, e.x - player.x);

		if (e.dead > 0) {
			e.dead += dt;
			if (e.dead > 0.9) reset();
			return;
		}

		const speed = e.type.speed;
		switch (type.behaviour) {
			case 'chase':
			case 'tank':
				// Straight at you. The brute is simply slower and much heavier.
				e.x += ux * speed * dt;
				e.y += uy * speed * dt;
				break;

			case 'flank': {
				// Steers for a point off to one side of the player, so it arrives
				// from an angle rather than head-on.
				const side = e.flankSide;
				const tx = player.x - ux * 90 + -uy * 300 * side;
				const ty = player.y - uy * 90 + ux * 300 * side;
				const fd = Math.hypot(tx - e.x, ty - e.y) || 1;
				e.x += ((tx - e.x) / fd) * speed * dt;
				e.y += ((ty - e.y) / fd) * speed * dt;
				if (dist < 120) e.flankSide = -side;
				break;
			}

			case 'ranged': {
				// Holds `range`, backs off below `retreat`, fires on cooldown.
				const want = type.range;
				if (dist > want + 40) { e.x += ux * speed * dt; e.y += uy * speed * dt; }
				else if (dist < type.retreat) { e.x -= ux * speed * dt; e.y -= uy * speed * dt; }
				else {
					// Strafes, so holding position still reads as movement.
					e.x += -uy * speed * 0.45 * dt;
					e.y += ux * speed * 0.45 * dt;
				}
				e.cooldown -= dt;
				if (e.cooldown <= 0 && dist < want + 160) {
					e.cooldown = type.cooldown;
					bullets.push({
						x: e.x, y: e.y,
						vx: ux * type.projectileSpeed, vy: uy * type.projectileSpeed,
						enemy: true, age: 0,
					});
				}
				break;
			}

			case 'skittish':
				// Runs from you, and pays out about five times a green slime.
				if (dist < type.flee) { e.x -= ux * speed * dt; e.y -= uy * speed * dt; }
				else { e.x += -uy * speed * 0.5 * dt; e.y += ux * speed * 0.5 * dt; }
				break;

			case 'bomber':
				// Closes, then lights a 0.75 s fuse you are meant to hear.
				if (e.fuse <= 0) {
					e.x += ux * speed * dt;
					e.y += uy * speed * dt;
					if (dist < type.fuseRange) e.fuse = type.fuse;
				} else {
					e.fuse -= dt;
					if (e.fuse <= 0) {
						blasts.push({ x: e.x, y: e.y, r: type.blastRadius, age: 0 });
						spark(e.x, e.y, rgb(type.hex), 20);
						playerHit = 0.35;
						e.dead = 0.001;
					}
				}
				break;
		}

		// Keep the actor inside its cell, and well inside the band vertically.
		e.x = clamp(e.x, -half, half);
		e.y = clamp(e.y, -half * Y_SPREAD, half * Y_SPREAD);
		e.bob += dt * 7;

		// The dummy player shoots back at the gun's real 5 rounds/sec.
		if (t > 0.5 && Math.floor(t * BALANCE.gun.rate) !== Math.floor((t - dt) * BALANCE.gun.rate)) {
			bullets.push({
				x: player.x + Math.cos(player.aim) * 34,
				y: player.y + Math.sin(player.aim) * 34,
				vx: Math.cos(player.aim) * 900, vy: Math.sin(player.aim) * 900,
				enemy: false, age: 0,
			});
			player.kick = 1;
		}

		for (let i = bullets.length - 1; i >= 0; i--) {
			const b = bullets[i];
			b.x += b.vx * dt; b.y += b.vy * dt; b.age += dt;
			const target = b.enemy ? player : e;
			const hitR = b.enemy ? 26 : e.type.radius;
			if (Math.hypot(b.x - target.x, b.y - target.y) < hitR) {
				bullets.splice(i, 1);
				if (b.enemy) { playerHit = 0.3; spark(b.x, b.y, RED, 5); }
				else {
					e.flash = 1;
					spark(b.x, b.y, rgb(e.type.hex), 6);
					e.hp -= 0.22;
					if (e.hp <= 0) { e.dead = 0.001; spark(e.x, e.y, rgb(e.type.hex), 16); }
				}
				continue;
			}
			if (b.age > 2 || Math.abs(b.x) > half + 200 || Math.abs(b.y) > half + 200) {
				bullets.splice(i, 1);
			}
		}

		for (let i = blasts.length - 1; i >= 0; i--) {
			blasts[i].age += dt;
			if (blasts[i].age > 0.5) blasts.splice(i, 1);
		}
		for (let i = sparks.length - 1; i >= 0; i--) {
			const s = sparks[i];
			s.age += dt;
			s.x += s.vx * dt; s.y += s.vy * dt;
			s.vx *= 0.92; s.vy *= 0.92;
			if (s.age > s.life) sparks.splice(i, 1);
		}
	};

	const draw = (r) => {
		// The distance each of these two colours is built around, drawn so that
		// "keeps its distance" and "runs from you" are visible, not just stated.
		if (type.behaviour === 'ranged') {
			r.ring(player.x, player.y, type.range, withAlpha(rgb(type.hex), 0.16));
		}
		if (type.behaviour === 'skittish') {
			r.ring(player.x, player.y, type.flee, withAlpha(GOLD, 0.13));
		}

		for (const b of blasts) {
			const k = b.age / 0.5;
			r.ring(b.x, b.y, b.r * (0.4 + k * 0.9),
				withAlpha(rgb(type.hex), (1 - k) * 0.85));
			r.glow(b.x, b.y, b.r * (0.3 + k * 0.5), withAlpha(GOLD, (1 - k) * 0.5));
		}

		drawPlayer(r, player, playerHit);

		if (e.dead > 0) {
			const k = clamp(e.dead / 0.9, 0, 1);
			r.sprite(`enemy_${e.type.id}`, e.x, e.y + 6, {
				anchor: 'base', scale: e.type.scale * DISPLAY_SCALE * (1 - k * 0.4),
				color: [1, 1, 1, 1 - k],
			});
		} else {
			// The bloater's fuse: it swells and whitens before it goes off.
			const fuseK = e.fuse > 0 ? 1 - e.fuse / type.fuse : 0;
			r.flash = e.flash * 0.9 + fuseK * 0.6;
			drawSlime(r, e, DISPLAY_SCALE * (1 + fuseK * 0.25));
			r.flash = 0;
			if (e.fuse > 0) {
				r.ring(e.x, e.y, type.fuseRange * (0.6 + fuseK),
					withAlpha(GOLD, 0.5 * (1 - fuseK)));
			}
		}

		for (const b of bullets) {
			const colour = b.enemy ? rgb(type.hex) : GOLD;
			r.sprite('bullet', b.x, b.y, {
				rot: Math.atan2(b.vy, b.vx), scale: b.enemy ? 1.5 : 1.2, color: colour,
			});
		}
		for (const s of sparks) {
			const k = 1 - s.age / s.life;
			r.sprite('spark', s.x, s.y, { scale: 1.6 * k, color: withAlpha(s.colour, k) });
		}
	};

	return { update, draw };
}

function drawPlayer(r, p, hurt) {
	const bob = Math.sin(p.bob) * 3;
	r.sprite('shadow', p.x, p.y + 26, { scale: 1.5, color: [0, 0, 0, 0.3] });
	r.flash = hurt > 0 ? clamp(hurt * 2.4, 0, 1) : 0;
	r.sprite('player_body', p.x, p.y + bob, { scale: 1.6 });
	r.sprite('player_face', p.x, p.y + bob - 6, { scale: 1.5 });
	r.flash = 0;
	const recoil = 1 - p.kick * 0.25;
	r.sprite('pistol', p.x + Math.cos(p.aim) * 40 * recoil, p.y + Math.sin(p.aim) * 40 * recoil, {
		rot: p.aim, scale: 1.3, flip: Math.abs(p.aim) > Math.PI / 2,
	});
	if (p.kick > 0.55) {
		r.sprite('muzzle', p.x + Math.cos(p.aim) * 74, p.y + Math.sin(p.aim) * 74, {
			rot: p.aim, scale: 1.4 * p.kick, color: withAlpha(GOLD, p.kick),
		});
	}
}
