// Difficulty chart: the threat budget against the stat caps.
//
// Deliberately 2D canvas rather than WebGL. This panel is axes, gridlines and
// text labels; drawing crisp hinted text through a sprite atlas would be worse
// in every way. The WebGL scenes are the ones that need a sprite pipeline.
//
// The two curves are the whole design argument. The budget the spawner has to
// spend grows quadratically forever, while what any single enemy gets is hard
// capped - HP at x3.2, damage at x2.4, speed at x1.45. So a late wave is a
// bigger, nastier crowd, not a wall of the same slime with a longer health bar.

import { BALANCE, ENEMIES, PALETTE } from '../data.js';
import { REDUCED_MOTION } from '../gl.js';

// Out to 50 so all three stat caps visibly flatten inside the frame - HP and
// damage top out at wave 41, speed at 38. The plateau is the whole point.
const MAX_WAVE = 50;
const PAD = { top: 26, right: 20, bottom: 42, left: 46 };

export function mountBudgetChart(canvas) {
	const ctx = canvas.getContext('2d');
	if (!ctx) return null;

	let dpr = 1;
	let w = 0;
	let h = 0;
	let progress = REDUCED_MOTION ? 1 : 0;
	let hover = null;

	const resize = () => {
		dpr = Math.min(window.devicePixelRatio || 1, 2);
		const rect = canvas.getBoundingClientRect();
		w = Math.max(1, Math.round(rect.width * dpr));
		h = Math.max(1, Math.round(rect.height * dpr));
		if (canvas.width !== w || canvas.height !== h) {
			canvas.width = w;
			canvas.height = h;
		}
		draw();
	};

	const plot = () => ({
		x0: PAD.left * dpr,
		y0: PAD.top * dpr,
		x1: w - PAD.right * dpr,
		y1: h - PAD.bottom * dpr,
	});

	const maxBudget = BALANCE.budget(MAX_WAVE);
	const waveToX = (wave, p) => p.x0 + (wave / MAX_WAVE) * (p.x1 - p.x0);
	const budgetToY = (v, p) => p.y1 - (v / maxBudget) * (p.y1 - p.y0);
	const scaleToY = (v, p) => p.y1 - ((v - 1) / 2.4) * (p.y1 - p.y0);

	function draw() {
		if (!w || !h) return;
		const p = plot();
		const f = (n) => `${n * dpr}px "IBM Plex Mono", ui-monospace, monospace`;
		ctx.clearRect(0, 0, w, h);

		// -- gridlines and the wave axis ------------------------------------
		ctx.strokeStyle = 'rgba(92,133,87,0.22)';
		ctx.lineWidth = 1 * dpr;
		ctx.font = f(10);
		ctx.fillStyle = PALETTE.textDim;
		ctx.textAlign = 'center';
		ctx.textBaseline = 'top';
		for (let wave = 0; wave <= MAX_WAVE; wave += 5) {
			const x = waveToX(wave, p);
			ctx.beginPath();
			ctx.moveTo(x, p.y0);
			ctx.lineTo(x, p.y1);
			ctx.stroke();
			if (wave > 0) ctx.fillText(String(wave), x, p.y1 + 8 * dpr);
		}
		ctx.fillText('wave', (p.x0 + p.x1) / 2, p.y1 + 24 * dpr);

		// -- boss cadence: mini every 5, major every 20 ----------------------
		for (let wave = 5; wave <= MAX_WAVE; wave += 5) {
			const major = wave % BALANCE.majorEvery === 0;
			const x = waveToX(wave, p);
			ctx.fillStyle = major ? 'rgba(235,82,87,0.16)' : 'rgba(255,209,82,0.09)';
			ctx.fillRect(x - 3 * dpr, p.y0, 6 * dpr, p.y1 - p.y0);
		}

		// -- the threat budget ----------------------------------------------
		const shown = MAX_WAVE * progress;
		ctx.beginPath();
		for (let wave = 1; wave <= shown; wave += 0.4) {
			const x = waveToX(wave, p);
			const y = budgetToY(BALANCE.budget(wave), p);
			if (wave <= 1) ctx.moveTo(x, y); else ctx.lineTo(x, y);
		}
		ctx.strokeStyle = PALETTE.gold;
		ctx.lineWidth = 2.4 * dpr;
		ctx.stroke();
		// Fill under it, so "more of them" reads as volume.
		if (shown > 1) {
			ctx.lineTo(waveToX(shown, p), p.y1);
			ctx.lineTo(waveToX(1, p), p.y1);
			ctx.closePath();
			ctx.fillStyle = 'rgba(255,209,82,0.10)';
			ctx.fill();
		}

		// -- the capped stat curves -----------------------------------------
		const caps = [
			{ fn: BALANCE.hpScale, cap: 3.2, colour: PALETTE.red, label: 'enemy HP  x3.2 cap' },
			{ fn: BALANCE.damageScale, cap: 2.4, colour: PALETTE.purple, label: 'damage  x2.4 cap' },
			{ fn: BALANCE.speedScale, cap: 1.45, colour: PALETTE.blue, label: 'speed  x1.45 cap' },
		];
		for (const c of caps) {
			ctx.beginPath();
			for (let wave = 1; wave <= shown; wave += 0.4) {
				const x = waveToX(wave, p);
				const y = scaleToY(Math.min(c.fn(wave), 3.4), p);
				if (wave <= 1) ctx.moveTo(x, y); else ctx.lineTo(x, y);
			}
			ctx.strokeStyle = c.colour;
			ctx.lineWidth = 1.6 * dpr;
			ctx.setLineDash([5 * dpr, 4 * dpr]);
			ctx.stroke();
			ctx.setLineDash([]);
		}

		// -- unlock markers, from the real schedule --------------------------
		ctx.textAlign = 'center';
		for (const e of ENEMIES) {
			if (e.unlock > shown) continue;
			const x = waveToX(e.unlock, p);
			const y = budgetToY(BALANCE.budget(e.unlock), p);
			ctx.beginPath();
			ctx.arc(x, y, 4.5 * dpr, 0, Math.PI * 2);
			ctx.fillStyle = e.hex;
			ctx.fill();
			ctx.strokeStyle = PALETTE.bg;
			ctx.lineWidth = 1.5 * dpr;
			ctx.stroke();
		}
		// Elites unlock at 13 and are the only marker that is not a colour.
		if (shown >= 13) {
			const x = waveToX(13, p);
			ctx.font = f(11);
			ctx.fillStyle = PALETTE.gold;
			ctx.textBaseline = 'bottom';
			ctx.fillText('elites', x, p.y0 + 13 * dpr);
			ctx.beginPath();
			ctx.moveTo(x, p.y0 + 16 * dpr);
			ctx.lineTo(x, p.y1);
			ctx.strokeStyle = 'rgba(255,209,82,0.32)';
			ctx.lineWidth = 1 * dpr;
			ctx.setLineDash([3 * dpr, 3 * dpr]);
			ctx.stroke();
			ctx.setLineDash([]);
		}

		// -- axis labels -----------------------------------------------------
		ctx.save();
		ctx.translate(14 * dpr, (p.y0 + p.y1) / 2);
		ctx.rotate(-Math.PI / 2);
		ctx.textAlign = 'center';
		ctx.textBaseline = 'middle';
		ctx.font = f(10);
		ctx.fillStyle = PALETTE.gold;
		ctx.fillText('threat budget', 0, 0);
		ctx.restore();

		// -- readout ---------------------------------------------------------
		const wave = hover ?? Math.max(1, Math.round(shown));
		if (wave >= 1) {
			const budget = BALANCE.budget(wave);
			const lines = [
				`wave ${wave}`,
				`budget ${budget.toFixed(1)} threat`,
				`~${Math.floor(budget / 1.0)} green slimes, or ${Math.floor(budget / 3.0)} brutes`,
				`enemy HP x${BALANCE.hpScale(wave).toFixed(2)}`,
				`elite chance ${(BALANCE.eliteChance(wave) * 100).toFixed(0)}%`,
			];
			ctx.font = f(10.5);
			ctx.textAlign = 'left';
			ctx.textBaseline = 'top';
			const boxW = Math.max(...lines.map((l) => ctx.measureText(l).width)) + 18 * dpr;
			const boxH = lines.length * 14 * dpr + 12 * dpr;
			const bx = p.x0 + 12 * dpr;
			const by = p.y0 + 8 * dpr;
			ctx.fillStyle = 'rgba(23,31,26,0.86)';
			ctx.strokeStyle = 'rgba(92,133,87,0.5)';
			ctx.lineWidth = 1 * dpr;
			ctx.fillRect(bx, by, boxW, boxH);
			ctx.strokeRect(bx, by, boxW, boxH);
			lines.forEach((line, i) => {
				ctx.fillStyle = i === 0 ? PALETTE.gold : PALETTE.textDim;
				ctx.fillText(line, bx + 9 * dpr, by + 7 * dpr + i * 14 * dpr);
			});
		}

		// -- legend ----------------------------------------------------------
		// Boxed, because the stat curves climb through this corner and plain text
		// on top of a dashed line is unreadable.
		ctx.font = f(9.5);
		ctx.textAlign = 'right';
		ctx.textBaseline = 'top';
		const legendW = Math.max(...caps.map((c) => ctx.measureText(c.label).width)) + 16 * dpr;
		const legendH = caps.length * 13 * dpr + 10 * dpr;
		const lx = p.x1 - legendW - 4 * dpr;
		const lyTop = p.y0 + 2 * dpr;
		ctx.fillStyle = 'rgba(23,31,26,0.88)';
		ctx.strokeStyle = 'rgba(92,133,87,0.4)';
		ctx.lineWidth = 1 * dpr;
		ctx.fillRect(lx, lyTop, legendW, legendH);
		ctx.strokeRect(lx, lyTop, legendW, legendH);
		caps.forEach((c, i) => {
			ctx.fillStyle = c.colour;
			ctx.fillText(c.label, p.x1 - 12 * dpr, lyTop + 5 * dpr + i * 13 * dpr);
		});
	}

	// Scrub the readout with the pointer.
	canvas.addEventListener('pointermove', (ev) => {
		const rect = canvas.getBoundingClientRect();
		const p = plot();
		const x = (ev.clientX - rect.left) * dpr;
		const t = (x - p.x0) / (p.x1 - p.x0);
		hover = t >= 0 && t <= 1 ? Math.max(1, Math.round(t * MAX_WAVE)) : null;
		draw();
	});
	canvas.addEventListener('pointerleave', () => { hover = null; draw(); });

	new ResizeObserver(resize).observe(canvas);
	resize();

	// Draw the curves in once, when the panel first scrolls into view.
	if (!REDUCED_MOTION) {
		const io = new IntersectionObserver((entries) => {
			if (!entries[0].isIntersecting) return;
			io.disconnect();
			const t0 = performance.now();
			const step = (now) => {
				const k = Math.min((now - t0) / 1400, 1);
				progress = 1 - (1 - k) ** 3;
				draw();
				if (k < 1) requestAnimationFrame(step);
			};
			requestAnimationFrame(step);
		}, { rootMargin: '-10% 0px' });
		io.observe(canvas);
	}

	return { draw };
}
