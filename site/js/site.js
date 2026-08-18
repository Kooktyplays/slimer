// Page wiring: mounts the scenes, builds the two data-driven tables, and runs
// the gallery lightbox and the music player.
//
// Everything here is progressive. The page's text is in the HTML, so if this
// module fails to load the content is still readable - the scenes just fall back
// to screenshots.

import { mount, REDUCED_MOTION } from './gl.js';
import { MUSIC_CUES, TRACKS } from './data.js';
import { applyDownloadLinks } from './config.js';
import { heroScene } from './scenes/hero.js';
import { rosterScene } from './scenes/roster.js';
import { telegraphScene } from './scenes/telegraph.js';
import { forestGenScene } from './scenes/forestgen.js';
import { mountBudgetChart } from './scenes/budget.js';

applyDownloadLinks();

// -- WebGL scenes ------------------------------------------------------------

const heroCanvas = document.querySelector('.hero-gl');
if (heroCanvas) mount(heroCanvas, heroScene);

const rosterCanvas = document.getElementById('roster-gl');
if (rosterCanvas) {
	const cells = [...document.querySelectorAll('.roster-grid .enemy')];
	mount(rosterCanvas, rosterScene(cells));
}

const telegraphCanvas = document.getElementById('telegraph-gl');
if (telegraphCanvas) {
	mount(telegraphCanvas, telegraphScene(document.getElementById('telegraph-label')));
}

const forestCanvas = document.getElementById('forest-gl');
if (forestCanvas) {
	mount(forestCanvas, forestGenScene(
		document.getElementById('forest-step'),
		document.getElementById('forest-stat'),
	)).then((handle) => {
		const btn = document.getElementById('forest-reseed');
		if (!handle || !btn) return;
		btn.addEventListener('click', () => {
			handle.scene.reseed();
			// With motion reduced the loop is not running, so redraw by hand.
			if (REDUCED_MOTION) {
				for (let i = 0; i < 400; i++) handle.scene.update(1 / 60);
				handle.scene.draw();
			}
		});
	});
}

const chart = document.getElementById('budget-chart');
if (chart) mountBudgetChart(chart);

// -- music cue table ---------------------------------------------------------
//
// One deck, click to play, nothing autoplays. Each cue applies its own playback
// rate, which is most of what separates the combat theme from the boss themes.

const cueRows = document.getElementById('cue-rows');
if (cueRows) {
	let audio = null;
	let playing = null;

	// Button state follows the element's actual play/pause events, not the
	// play() promise. A blocked or failed play must not leave a row claiming to
	// be playing when the page is silent.
	const paint = () => {
		for (const b of cueRows.querySelectorAll('.cue-btn')) {
			const live = playing === b.dataset.cue && audio && !audio.paused;
			b.setAttribute('aria-pressed', live ? 'true' : 'false');
			if (!b.disabled) b.textContent = live ? '■ stop' : '▶ play';
		}
	};

	const stop = () => {
		if (audio) { audio.pause(); audio.currentTime = 0; }
		playing = null;
		paint();
	};

	for (const cue of MUSIC_CUES) {
		const tr = document.createElement('tr');

		const add = (html, mono = true) => {
			const td = document.createElement('td');
			td.innerHTML = html;
			if (!mono) td.style.fontFamily = 'var(--sans)';
			tr.append(td);
			return td;
		};

		add(`<b style="color:var(--gold);font-weight:400">${cue.cue}</b>`);
		add(TRACKS[cue.track]);
		add(cue.rate === 1 ? '—' : `×${cue.rate.toFixed(2)}`);
		add(cue.drive ? `${cue.drive.toFixed(2)}` : '—');
		add(cue.when + (cue.layer ? ` <span style="color:var(--dim)">+ ${cue.layer}</span>` : ''), false);

		const cell = add('');
		const btn = document.createElement('button');
		btn.type = 'button';
		btn.className = 'cue-btn';
		btn.dataset.cue = cue.cue;
		btn.textContent = '▶ play';
		btn.setAttribute('aria-pressed', 'false');
		btn.setAttribute('aria-label', `Play the ${cue.cue} cue`);
		btn.addEventListener('click', () => {
			const wasPlaying = playing === cue.cue && audio && !audio.paused;
			stop();
			if (wasPlaying) return;
			if (!audio) {
				audio = new Audio();
				audio.loop = true;
				audio.volume = 0.6;
				for (const ev of ['play', 'pause', 'ended']) {
					audio.addEventListener(ev, paint);
				}
				audio.addEventListener('error', () => {
					playing = null;
					for (const b of cueRows.querySelectorAll('.cue-btn')) {
						b.textContent = 'unavailable';
						b.disabled = true;
					}
				});
			}
			if (!audio.src.endsWith(`${cue.track}.mp3`)) {
				audio.src = `assets/music/${cue.track}.mp3`;
			}
			audio.playbackRate = cue.rate;
			// Let the pitch shift through - dropping the combat theme to 0.84x is
			// most of what makes the major-boss cue feel different.
			audio.preservesPitch = false;
			playing = cue.cue;
			audio.play().then(paint).catch(() => {
				playing = null;
				btn.textContent = 'blocked';
				paint();
			});
		});
		cell.append(btn);

		cueRows.append(tr);
	}

	// Never leave music running behind a page the visitor has left.
	document.addEventListener('visibilitychange', () => {
		if (document.hidden) stop();
	});
}

// -- gallery + lightbox ------------------------------------------------------

const SHOTS = [
	['01_main_menu', 'Main menu'],
	['02_loadout', 'Choosing your two abilities'],
	['03_meta_upgrades', 'Permanent unlocks, bought with essence'],
	['04_credits', 'Credits and attribution'],
	['05_forest_spawn', 'Spawn: a clearing in a fresh forest'],
	['06_wave_all_colours', 'A wave with all six colours on screen'],
	['07_combat', 'Combat, with elites crowned'],
	['08_ability_nova', 'Nova going off'],
	['09_pause_menu', 'Pause — and the world really does stop'],
	['10_settings', 'Settings, including full rebinding'],
	['11_mini_boss', 'A mini-boss and its telegraph'],
	['12_major_boss', 'The Ancient Oak, wave 20'],
	['13_shop', 'Forest Rest: six offers, two affordable'],
	['14_low_health', 'Low health, and the music knows'],
	['15_death', 'Death'],
	['16_results', 'Run results and essence earned'],
];

const gallery = document.getElementById('gallery');
const dialog = document.getElementById('lightbox');
const lbImg = document.getElementById('lightbox-img');
const lbCaption = document.getElementById('lb-caption');
const lbCount = document.getElementById('lb-count');

if (gallery) {
	SHOTS.forEach(([slug, caption], i) => {
		const fig = document.createElement('figure');
		fig.style.margin = '0';
		const btn = document.createElement('button');
		btn.type = 'button';
		btn.innerHTML = `
			<img src="assets/shots/${slug}_thumb.webp" alt="${caption}"
				width="800" height="450" loading="lazy" decoding="async">
			<figcaption>${caption}</figcaption>`;
		btn.addEventListener('click', () => open(i));
		fig.append(btn);
		gallery.append(fig);
	});
}

let current = 0;

function open(index) {
	if (!dialog || !lbImg) return;
	current = (index + SHOTS.length) % SHOTS.length;
	const [slug, caption] = SHOTS[current];
	lbImg.src = `assets/shots/${slug}.webp`;
	lbImg.alt = caption;
	lbCaption.textContent = caption;
	lbCount.textContent = `${current + 1} / ${SHOTS.length}`;
	if (!dialog.open) dialog.showModal();
}

if (dialog) {
	document.getElementById('lb-prev').addEventListener('click', () => open(current - 1));
	document.getElementById('lb-next').addEventListener('click', () => open(current + 1));
	document.getElementById('lb-close').addEventListener('click', () => dialog.close());
	dialog.addEventListener('keydown', (ev) => {
		if (ev.key === 'ArrowLeft') { ev.preventDefault(); open(current - 1); }
		if (ev.key === 'ArrowRight') { ev.preventDefault(); open(current + 1); }
	});
	// Clicking the backdrop - anywhere that is not the image or the bar - closes.
	dialog.addEventListener('click', (ev) => {
		if (ev.target === dialog) dialog.close();
	});
}

// -- nav: highlight the section you are actually looking at ------------------

const navLinks = [...document.querySelectorAll('.nav-links a')];
const sections = navLinks
	.map((a) => document.querySelector(a.getAttribute('href')))
	.filter(Boolean);

if (sections.length) {
	const spy = new IntersectionObserver((entries) => {
		for (const entry of entries) {
			if (!entry.isIntersecting) continue;
			const id = `#${entry.target.id}`;
			for (const a of navLinks) {
				a.setAttribute('aria-current', a.getAttribute('href') === id ? 'true' : 'false');
			}
		}
	}, { rootMargin: '-45% 0px -50% 0px' });
	for (const s of sections) spy.observe(s);
}
