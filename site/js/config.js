// Where the builds live.
//
// The desktop builds are ~240 MB together, far too much for a static deploy, so
// they are release assets on GitHub and the site links out to them. Retag the
// release and only VERSION and the sizes below need to change.

export const VERSION = '2.1.0';

// Alpha builds are web-only.
//
// The desktop buttons point at GitHub release assets, and there is no release
// tagged for this version - so with them live an alpha tester who clicked
// Download would get 2.0.0 and quietly play a different game from the one in
// the browser tab. The browser build is served from this origin and is always
// whatever was last deployed, so it cannot go stale the same way.
//
// Set this to false once a release is tagged and the three zips are uploaded.
export const ALPHA = true;
export const REPO = 'https://github.com/Kooktyplays/slimer';

const RELEASE = `${REPO}/releases/download/v${VERSION}`;

// Sizes are the compressed download, not the unpacked build - that is the number
// a visitor is actually about to spend. Unpacked, Windows is 101 MB and Linux
// 74 MB.
export const DOWNLOADS = {
	macos: {
		url: `${RELEASE}/Slimer-${VERSION}-macos.zip`,
		size: '65 MB',
		file: `Slimer-${VERSION}-macos.zip`,
	},
	windows: {
		url: `${RELEASE}/Slimer-${VERSION}-windows.zip`,
		size: '41 MB',
		file: `Slimer-${VERSION}-windows.zip`,
	},
	linux: {
		url: `${RELEASE}/Slimer-${VERSION}-linux.zip`,
		size: '33 MB',
		file: `Slimer-${VERSION}-linux.zip`,
	},
};

/** Fills in every [data-dl="platform"] link and its size label. */
export function applyDownloadLinks(root = document) {
	for (const el of root.querySelectorAll('[data-alpha-only]')) {
		el.hidden = !ALPHA;
	}
	if (ALPHA) {
		// The links ship disabled in the markup and are only ever enabled here,
		// so doing nothing is the safe state: they stay unclickable.
		for (const el of root.querySelectorAll('[data-dl-desktop]')) el.hidden = true;
		for (const el of root.querySelectorAll('[data-version]')) el.textContent = VERSION;
		for (const el of root.querySelectorAll('[data-repo]')) el.href = REPO;
		return;
	}
	for (const [platform, info] of Object.entries(DOWNLOADS)) {
		for (const el of root.querySelectorAll(`[data-dl="${platform}"]`)) {
			el.href = info.url;
			el.removeAttribute('aria-disabled');
		}
		for (const el of root.querySelectorAll(`[data-dl-size="${platform}"]`)) {
			el.textContent = info.size;
		}
	}
	for (const el of root.querySelectorAll('[data-repo]')) el.href = REPO;
	for (const el of root.querySelectorAll('[data-version]')) el.textContent = VERSION;
}
