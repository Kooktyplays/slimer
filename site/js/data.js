// Game constants, transcribed from the real data tables so the scenes simulate
// what the game actually does. Sources are named per block; if the game is
// retuned, these are the numbers to re-check.
//
// game/data/enemy_types.gd - "colour is a promise": colour, behaviour and stats
// live in one entry so they cannot drift apart.

export const ENEMIES = [
	{
		id: 'green', name: 'Slime', behaviour: 'chase', hex: '#5CCC26',
		hp: 30, speed: 110, contact: 8, threat: 1.0, money: '4-7',
		radius: 30, scale: 0.62, unlock: 1,
		hint: 'Green slimes chase you down. Keep moving.',
	},
	{
		id: 'blue', name: 'Darter', behaviour: 'flank', hex: '#2999EB',
		hp: 20, speed: 215, contact: 6, threat: 1.2, money: '6-10',
		radius: 25, scale: 0.54, unlock: 4,
		hint: 'Blue darters are fast and try to get behind you.',
	},
	{
		id: 'red', name: 'Brute', behaviour: 'tank', hex: '#DB293D',
		hp: 110, speed: 62, contact: 20, threat: 3.0, money: '12-18',
		radius: 44, scale: 0.92, unlock: 6,
		hint: "Red brutes soak damage and hit hard. Don't get cornered.",
	},
	{
		id: 'purple', name: 'Spitter', behaviour: 'ranged', hex: '#993DD9',
		hp: 38, speed: 95, contact: 5, threat: 2.2, money: '10-16',
		radius: 30, scale: 0.64, unlock: 9,
		range: 420, retreat: 260, projectile: 9, projectileSpeed: 430, cooldown: 2.1,
		hint: 'Purple spitters keep their distance. Close in or break line of sight.',
	},
	{
		id: 'yellow', name: 'Hoarder', behaviour: 'skittish', hex: '#F2BF1F',
		hp: 45, speed: 145, contact: 7, threat: 1.8, money: '34-52',
		radius: 32, scale: 0.66, unlock: 11, flee: 340,
		hint: 'Yellow hoarders run from you and pay out big. Worth the chase.',
	},
	{
		id: 'orange', name: 'Bloater', behaviour: 'bomber', hex: '#F2731A',
		hp: 34, speed: 130, contact: 0, threat: 2.4, money: '11-17',
		radius: 34, scale: 0.70, unlock: 15,
		blast: 26, blastRadius: 165, fuseRange: 95, fuse: 0.75,
		hint: 'Orange bloaters detonate. Kill them early, at range.',
	},
];

export const ENEMY_BY_ID = Object.fromEntries(ENEMIES.map((e) => [e.id, e]));

// game/data/boss_db.gd
export const BOSSES = [
	{
		id: 'bramble', name: 'Bramble Warden', title: 'Warden of the Thicket',
		kind: 'mini', radius: 110, scale: 1.75, speed: 92, contact: 22,
		summons: '3 x green, green, blue',
		phases: [
			['charge', 'radial'],
			['+ summon', 'rain'],
			['+ spiral'],
		],
		blurb: 'A thorny root creature. Opens with a straight charge, so the first thing it teaches you is to read a line on the ground.',
	},
	{
		id: 'toad', name: 'The Toadfather', title: 'Glutton of the Mire',
		kind: 'mini', radius: 130, scale: 1.7, speed: 64, contact: 26,
		summons: '4 x green, orange',
		phases: [
			['slam', 'aimed volley'],
			['+ summon', 'shockwave'],
			['+ rain'],
		],
		blurb: 'Slow and bloated, and it summons bloaters. The pressure is never the toad itself - it is what the toad leaves standing next to you.',
	},
	{
		id: 'wisp', name: 'The Wisp Choir', title: 'Voices in the Dark',
		kind: 'mini', radius: 95, scale: 1.8, speed: 128, contact: 16,
		summons: '3 x purple, blue',
		phases: [
			['spiral', 'blink radial'],
			['+ aimed volley', 'summon'],
			['+ rain'],
		],
		blurb: 'Floats, and the fastest thing in the forest. It blinks before it bursts, so position is worth more than damage here.',
	},
	{
		id: 'oak', name: 'The Ancient Oak', title: 'First Root of the Deep Wood',
		kind: 'major', radius: 150, scale: 2.15, speed: 52, contact: 34,
		summons: '5 x green, red, purple',
		phases: [
			['rain', 'radial', 'summon'],
			['+ shockwave', 'slam'],
			['+ spiral'],
			['+ charge'],
		],
		blurb: 'The wave-20 wall. A treant that barely moves and fills the clearing instead, four phases deep on a repeat visit.',
	},
	{
		id: 'sovereign', name: 'The Slime Sovereign', title: 'Crowned Devourer',
		kind: 'major', radius: 190, scale: 2.2, speed: 76, contact: 36,
		summons: '6 x green, blue, red, yellow - and they can be elites',
		phases: [
			['slam', 'spiral', 'summon'],
			['+ rain', 'radial'],
			['+ shockwave', 'charge'],
			['+ blink radial'],
		],
		blurb: 'The biggest hit radius in the game and the only boss whose summons arrive crowned. Everything the forest has taught you, at once.',
	},
];

// game/data/abilities_db.gd - eleven exist, you carry exactly two.
export const ABILITIES = [
	{ id: 'dash', name: 'Dash', icon: 'icon_dash', role: 'escape', charges: 2, cd: 3.2, essence: 0,
		desc: 'Blink through enemies and bullets. Brief invulnerability.', detail: '320 px, 0.16 s fully invulnerable' },
	{ id: 'grenade', name: 'Grenade', icon: 'icon_grenade', role: 'burst', charges: 1, cd: 7, essence: 0,
		desc: 'Lob an explosive at the cursor. Heavy area damage.', detail: '90 damage, 190 radius, 0.75 s fuse' },
	{ id: 'shield', name: 'Bulwark', icon: 'icon_shield', role: 'sustain', charges: 1, cd: 14, essence: 120,
		desc: 'A barrier absorbs the next 120 damage for 6 seconds.', detail: '120 absorbed, 6 s' },
	{ id: 'nova', name: 'Nova', icon: 'icon_nova', role: 'burst', charges: 1, cd: 11, essence: 150,
		desc: 'Detonate around yourself, damaging and flinging back everything near.', detail: '70 damage, 300 radius, 640 knockback' },
	{ id: 'heal', name: 'Bloom', icon: 'icon_heal', role: 'sustain', charges: 1, cd: 26, essence: 180,
		desc: 'Restore 35% of maximum health instantly.', detail: '35% of max HP' },
	{ id: 'decoy', name: 'Effigy', icon: 'icon_decoy', role: 'control', charges: 1, cd: 16, essence: 200,
		desc: 'Drop a lure that pulls enemies for 7 seconds, then bursts.', detail: '7 s taunt at 620 px, 60 damage burst' },
	{ id: 'timeslow', name: 'Torpor', icon: 'icon_timeslow', role: 'control', charges: 1, cd: 18, essence: 200,
		desc: 'Slow every enemy and enemy bullet to 35% for 4 seconds.', detail: '35% speed, 4 s - bullets too' },
	{ id: 'lightning', name: 'Stormcall', icon: 'icon_lightning', role: 'burst', charges: 1, cd: 9, essence: 220,
		desc: 'Chain lightning arcs between up to 7 nearby enemies.', detail: '55 damage, 7 jumps, 320 px reach' },
	{ id: 'rapidfire', name: 'Frenzy', icon: 'icon_rapidfire', role: 'burst', charges: 1, cd: 20, essence: 240,
		desc: 'Triple fire rate and free reloads for 5 seconds.', detail: 'x3 fire rate, 5 s, no reloads' },
	{ id: 'orbital', name: 'Satellites', icon: 'icon_orbital', role: 'control', charges: 1, cd: 22, essence: 260,
		desc: 'Three orbs circle you for 12 seconds, damaging what they touch.', detail: '3 orbs, 26 damage, 150 px orbit' },
	{ id: 'lifesteal', name: 'Leech', icon: 'icon_lifesteal', role: 'sustain', charges: 1, cd: 24, essence: 280,
		desc: 'For 8 seconds, 18% of the damage you deal comes back as health.', detail: '18% of damage dealt, 8 s' },
];

// game/data/balance.gd
export const BALANCE = {
	budget: (w) => 4 + 2.1 * w + 0.075 * w * w,
	spawnRate: (w) => Math.min(1.1 + 0.18 * w, 7.5),
	hpScale: (w) => Math.min(1 + 0.055 * (w - 1), 3.2),
	damageScale: (w) => Math.min(1 + 0.035 * (w - 1), 2.4),
	speedScale: (w) => Math.min(1 + 0.012 * (w - 1), 1.45),
	eliteChance: (w) => (w < 13 ? 0 : Math.min(0.06 + 0.012 * (w - 13), 0.30)),
	miniHp: (w) => 520 + 95 * w,
	majorHp: (w) => 1600 + 240 * w,
	maxConcurrent: 55,
	miniEvery: 5,
	majorEvery: 20,
	player: { hp: 100, speed: 265, radius: 22, iframes: 0.55 },
	gun: { damage: 12, rate: 5, mag: 12, reload: 1.1, speed: 1000, crit: 0.05, range: 900 },
	// Telegraph window, actors/bosses/boss.gd - tighter each phase, never below 0.42 s.
	telegraph: (phase) => Math.max(0.42, 0.85 - 0.11 * (phase - 1)),
};

// game/ui/ui_theme.gd, plus project.godot's default_clear_color.
export const PALETTE = {
	bg: '#171F1A',
	clear: '#293629',
	panel: '#212B24',
	panelHi: '#304033',
	border: '#5C8557',
	text: '#EBF5E6',
	textDim: '#9EB29E',
	gold: '#FFD152',
	red: '#EB5257',
	green: '#7ADB6B',
	blue: '#6BB8FF',
	purple: '#B27AF5',
};

// world/forest_generator.gd - the arena and the rules the visualiser reproduces.
export const FOREST = {
	width: 4800,
	height: 3700,
	border: 300,
	clearings: [9, 13],
	clearingRadius: [300, 470],
	clearingSeparation: 720,
	pathWidth: 170,
	extraLoopEdges: 3,
	ponds: [2, 4],
	pondRadius: [190, 330],
	treeSpacing: 168,
	scatterSpacing: 132,
	detailSpacing: 108,
	gridCell: 64,
	actorClearance: 46,
	minClearingOpenCells: 26,
	maxAttempts: 6,
};

// autoload/audio.gd - four tracks, nine cues.
export const MUSIC_CUES = [
	{ cue: 'MENU', track: 'lobby_music', rate: 1.00, drive: 0, when: 'Main menu, loadout, permanent upgrades, credits' },
	{ cue: 'SHOP', track: 'lobby_music', rate: 1.00, drive: 0, when: 'Forest Rest, between waves' },
	{ cue: 'COMBAT', track: 'normal_music', rate: 1.00, drive: 0, when: 'Ordinary waves, 1 to 7' },
	{ cue: 'ESCALATION', track: 'normal_music', rate: 1.06, drive: 0, when: 'Ordinary waves, 8 and up', layer: 'escalation percussion' },
	{ cue: 'MINI BOSS', track: 'normal_music', rate: 0.92, drive: 0.22, when: 'Mini-boss phase', layer: 'mini percussion' },
	{ cue: 'MAJOR BOSS', track: 'normal_music', rate: 0.84, drive: 0.40, when: 'Major-boss phase', layer: 'major percussion' },
	{ cue: 'LOW HEALTH', track: 'low_health_music', rate: 1.00, drive: 0, when: 'At or below 30% health, in any phase but the shop' },
	{ cue: 'DEATH', track: 'low_health_music', rate: 0.88, drive: 0, when: 'The run ends' },
	{ cue: 'RESULTS', track: 'happy_ending', rate: 1.00, drive: 0, when: 'Run results, essence tallied' },
];

export const TRACKS = {
	lobby_music: 'Lobby Music',
	normal_music: 'Normal Music',
	low_health_music: 'Low Health Music',
	happy_ending: 'Happy Ending',
};
