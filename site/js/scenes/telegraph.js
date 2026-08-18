// Telegraph scene: the two design decisions that make the bosses fair.
//
// Every heavy attack draws its danger on the ground before it lands, and the
// marker fills from the centre outward, ending exactly at the radius the hit
// will cover. Two of the nine attacks are worth showing:
//
//   radial  - the burst always leaves a gap. A perfect ring is a damage tax; a
//             ring with a seam is a decision.
//   charge  - the line is drawn before the boss moves, so the safe ground is
//             never ambiguous.
//
// Cycles between them, with the real telegraph window from boss.gd:
// max(0.42, 0.85 - 0.11 * (phase - 1)).

import { rgb, TAU, clamp, withAlpha, lerp } from '../gl.js';
import { PALETTE, BALANCE } from '../data.js';

const GROUND = rgb(PALETTE.clear);
const GOLD = rgb(PALETTE.gold);
const RED = rgb(PALETTE.red);
const WORLD = 1500;

const ATTACKS = ['radial', 'charge'];

export function telegraphScene(labelEl) {
	return (r) => {
		const boss = { x: 0, y: -80, bob: 0 };
		const player = { x: 340, y: 210, bob: 0, hurt: 0 };

		let which = 0;
		let phase = 2;
		let stage = 'idle';       // idle -> telegraph -> strike -> recover
		let clock = 0;
		let bullets = [];
		let charge = null;
		let shake = 0;

		const window = () => BALANCE.telegraph(phase);

		const setLabel = () => {
			if (!labelEl) return;
			const name = ATTACKS[which] === 'radial' ? 'radial burst' : 'line charge';
			labelEl.textContent =
				`${name} — phase ${phase}, ${window().toFixed(2)} s of warning`;
		};
		setLabel();

		// The gap in the ring. Regenerated per burst, so it is never learnable
		// as a fixed direction - only as a thing you have to look for.
		let gapAngle = 0;
		const GAP_WIDTH = 0.9;

		const beginTelegraph = () => {
			stage = 'telegraph';
			clock = 0;
			gapAngle = Math.random() * TAU;
			if (ATTACKS[which] === 'charge') {
				const a = Math.atan2(player.y - boss.y, player.x - boss.x);
				charge = {
					a, from: { x: boss.x, y: boss.y },
					to: { x: boss.x + Math.cos(a) * 1250, y: boss.y + Math.sin(a) * 1250 },
					t: 0,
				};
			}
			setLabel();
		};

		const strike = () => {
			stage = 'strike';
			clock = 0;
			shake = 1;
			if (ATTACKS[which] === 'radial') {
				// 18 projectiles, minus the ones that would fill the seam.
				const n = 18;
				for (let i = 0; i < n; i++) {
					const a = (i / n) * TAU;
					let delta = Math.abs(((a - gapAngle + Math.PI * 3) % TAU) - Math.PI);
					if (delta > Math.PI - GAP_WIDTH) continue;
					bullets.push({
						x: boss.x, y: boss.y,
						vx: Math.cos(a) * 460, vy: Math.sin(a) * 460, age: 0,
					});
				}
			}
		};

		return {
			update(dt) {
				clock += dt;
				boss.bob += dt * 1.8;
				player.bob += dt * 3;
				player.hurt = Math.max(0, player.hurt - dt * 2);
				shake = Math.max(0, shake - dt * 4);

				if (stage === 'idle' && clock > 0.75) beginTelegraph();
				else if (stage === 'telegraph' && clock > window()) strike();
				else if (stage === 'strike') {
					if (ATTACKS[which] === 'charge' && charge) {
						charge.t = clamp(charge.t + dt * 2.6, 0, 1);
						// Ease-out: it commits hard, then arrives.
						const k = 1 - (1 - charge.t) ** 2;
						boss.x = lerp(charge.from.x, charge.to.x, k * 0.62);
						boss.y = lerp(charge.from.y, charge.to.y, k * 0.62);
					}
					if (clock > 1.15) {
						stage = 'recover';
						clock = 0;
					}
				} else if (stage === 'recover' && clock > 0.9) {
					// Next attack, and every third pass a later phase - which is
					// how the game tightens the window without ever removing it.
					which = (which + 1) % ATTACKS.length;
					if (which === 0) phase = phase >= 4 ? 2 : phase + 1;
					stage = 'idle';
					clock = 0;
					bullets = [];
					charge = null;
					boss.x = 0; boss.y = -80;
					setLabel();
				}

				for (let i = bullets.length - 1; i >= 0; i--) {
					const b = bullets[i];
					b.x += b.vx * dt; b.y += b.vy * dt; b.age += dt;
					if (Math.hypot(b.x - player.x, b.y - player.y) < 40) {
						player.hurt = 1;
						bullets.splice(i, 1);
						continue;
					}
					if (b.age > 2.4) bullets.splice(i, 1);
				}

				// The player sidesteps into the safe ground, because a telegraph
				// you cannot act on is just a warning label.
				if (stage === 'telegraph') {
					if (ATTACKS[which] === 'radial') {
						const tx = boss.x + Math.cos(gapAngle) * 470;
						const ty = boss.y + Math.sin(gapAngle) * 470;
						player.x = lerp(player.x, tx, dt * 2.4);
						player.y = lerp(player.y, ty, dt * 2.4);
					} else if (charge) {
						// Step perpendicular to the drawn line.
						const off = 300;
						const tx = player.x + -Math.sin(charge.a) * off;
						const ty = player.y + Math.cos(charge.a) * off;
						player.x = lerp(player.x, clamp(tx, -600, 600), dt * 2.2);
						player.y = lerp(player.y, clamp(ty, -400, 400), dt * 2.2);
					}
				}
			},

			draw() {
				const jitter = shake * 14;
				r.clear(GROUND);
				r.begin({
					x: (Math.random() - 0.5) * jitter,
					y: (Math.random() - 0.5) * jitter,
					zoom: Math.min(r.canvas.width, r.canvas.height * 1.7) / WORLD,
				});

				const k = stage === 'telegraph' ? clamp(clock / window(), 0, 1) : 0;

				if (stage === 'telegraph' && ATTACKS[which] === 'radial') {
					// Fills centre-outward, ending exactly at the hit radius.
					const radius = 470;
					r.glow(boss.x, boss.y, radius * k, withAlpha(RED, 0.30));
					r.ring(boss.x, boss.y, radius * k, withAlpha(RED, 0.85));
					// The seam, drawn in safe gold so the gap is the readable part.
					for (let i = 0; i < 7; i++) {
						const a = gapAngle + (i / 6 - 0.5) * GAP_WIDTH * 1.5;
						const rr = radius * k;
						r.sprite('spark_square', boss.x + Math.cos(a) * rr, boss.y + Math.sin(a) * rr, {
							scale: 2.4, color: withAlpha(GOLD, 0.9),
						});
					}
				}

				if (stage === 'telegraph' && charge) {
					// The line, drawn before the boss moves.
					r.line(charge.from.x, charge.from.y, charge.to.x, charge.to.y,
						230 * (0.35 + k * 0.65), withAlpha(RED, 0.22 + k * 0.5));
					r.line(charge.from.x, charge.from.y,
						lerp(charge.from.x, charge.to.x, k),
						lerp(charge.from.y, charge.to.y, k),
						230, withAlpha(RED, 0.5));
				}

				for (const b of bullets) {
					r.sprite('boss_orb', b.x, b.y, {
						scale: 1.5, color: withAlpha(RED, 0.95),
					});
				}

				// The player, then the boss on top - it is the biggest thing here.
				r.sprite('shadow', player.x, player.y + 24, { scale: 1.3, color: [0, 0, 0, 0.3] });
				r.flash = player.hurt;
				r.sprite('player_body', player.x, player.y + Math.sin(player.bob) * 3, { scale: 1.4 });
				r.sprite('player_face', player.x, player.y - 6, { scale: 1.3 });
				r.flash = 0;

				const bossScale = 1.5 + Math.sin(boss.bob) * 0.02;
				r.sprite('shadow', boss.x, boss.y + 100, { scale: 3.4, color: [0, 0, 0, 0.32] });
				r.flash = stage === 'strike' ? 0.4 : 0;
				r.sprite('boss_oak', boss.x, boss.y + 110, { anchor: 'base', scale: bossScale });
				r.flash = 0;
				r.sprite('boss_oak_eyes', boss.x, boss.y - 78, { scale: bossScale * 0.9 });

				r.flush();
			},
		};
	};
}
