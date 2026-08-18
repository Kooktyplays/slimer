// Where the builds live.
//
// The desktop builds are ~240 MB together, far too much for a static deploy, so
// they are release assets on GitHub and the site links out to them. Retag the
// release and only VERSION and the sizes below need to change.

export const VERSION = '2.0.0';
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
