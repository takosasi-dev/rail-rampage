// Web 書き出しを窓なし・消音の Chrome で開く確認の共通部品（check_web.mjs と shoot_web.mjs が使う）。
// 窓を出さない・音を出さない（開発者が同じ PC で別の作業をしていても邪魔しない）。
// Chrome は CDP（Node 22 以降に入っている WebSocket）で動かすので、追加のインストールは要らない。
import { spawn } from 'node:child_process';
import { existsSync, writeFileSync } from 'node:fs';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

export { sleep };
export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const WEB = path.join(ROOT, 'build', 'web');
export const BOOT_TIMEOUT_MS = 60000;
export const SCREEN_SETTLE_MS = 2000; // 画面が切り替わって落ち着くまで
const BROWSERS = [
	'C:/Program Files/Google/Chrome/Application/chrome.exe',
	'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
];
// Godot の user:// は IndexedDB '/userfs' の 'FILE_DATA' に、このフォルダの下のキーで写される
const USER_DIR = '/userfs/godot/app_userdata/RailRampage';
const KEYS = {
	Enter: { key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, text: '\r' },
	Space: { key: ' ', code: 'Space', windowsVirtualKeyCode: 32, text: ' ' },
	ArrowRight: { key: 'ArrowRight', code: 'ArrowRight', windowsVirtualKeyCode: 39 },
	ArrowDown: { key: 'ArrowDown', code: 'ArrowDown', windowsVirtualKeyCode: 40 },
	ArrowUp: { key: 'ArrowUp', code: 'ArrowUp', windowsVirtualKeyCode: 38 },
	Escape: { key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 },
};
// user:// の中のファイルをすべて文字列で読む
const READ_USERFS = `new Promise((resolve) => {
	const req = indexedDB.open('/userfs');
	req.onerror = () => resolve({});
	req.onsuccess = () => {
		const db = req.result;
		if (!db.objectStoreNames.contains('FILE_DATA')) { db.close(); resolve({}); return; }
		const out = {};
		db.transaction('FILE_DATA').objectStore('FILE_DATA').openCursor().onsuccess = (e) => {
			const c = e.target.result;
			if (!c) { db.close(); resolve(out); return; }
			if (c.value && c.value.contents) out[c.key] = new TextDecoder().decode(c.value.contents);
			c.continue();
		};
	};
})`;
// user:// にファイルを書く（{ ファイル名: 中身 }）。エンジンが動いていないページで呼ぶ（動いていると上書きされうる）。
// 1回目の起動で保存領域が作られた後に使う。親フォルダの記録も書く（無いと、起動時にファイルを読み込めない）
const writeUserfsExpr = (files) => `new Promise((resolve, reject) => {
	const req = indexedDB.open('/userfs');
	req.onerror = () => reject(String(req.error));
	req.onsuccess = () => {
		const db = req.result;
		const tx = db.transaction('FILE_DATA', 'readwrite');
		const store = tx.objectStore('FILE_DATA');
		const parts = '${USER_DIR}'.split('/').filter(Boolean);
		for (let i = 2; i <= parts.length; i++) { // '/userfs' の下のフォルダを上から順に
			store.put({ timestamp: new Date(), mode: 16877 }, '/' + parts.slice(0, i).join('/'));
		}
		for (const [name, text] of Object.entries(${JSON.stringify(files)})) {
			store.put({ timestamp: new Date(), mode: 33188, contents: new TextEncoder().encode(text) }, '${USER_DIR}/' + name);
		}
		tx.oncomplete = () => { db.close(); resolve(true); };
		tx.onerror = () => reject(String(tx.error));
	};
})`;

export function findBrowser() {
	return BROWSERS.find(existsSync);
}

export async function waitFor(fn, timeoutMs, intervalMs = 500) {
	const end = Date.now() + timeoutMs;
	while (Date.now() < end) {
		const v = await fn();
		if (v) return v;
		await sleep(intervalMs);
	}
	return null;
}

async function connect(url) {
	const ws = new WebSocket(url);
	await new Promise((ok, ng) => { ws.onopen = ok; ws.onerror = ng; });
	let id = 0;
	const pending = new Map();
	const listeners = [];
	ws.onmessage = (m) => {
		const msg = JSON.parse(m.data);
		if (msg.id && pending.has(msg.id)) {
			const { ok, ng } = pending.get(msg.id);
			pending.delete(msg.id);
			msg.error ? ng(new Error(msg.error.message)) : ok(msg.result);
		} else {
			listeners.forEach((f) => f(msg));
		}
	};
	return {
		send: (method, params = {}) => new Promise((ok, ng) => {
			const i = ++id;
			pending.set(i, { ok, ng });
			ws.send(JSON.stringify({ id: i, method, params }));
		}),
		onEvent: (f) => listeners.push(f),
		close: () => ws.close(),
	};
}

// python の http.server で dir を配信し、窓なし消音の Chrome を立ち上げて、ページにつなぐ。つなげなければ null
export async function launch({ httpPort, cdpPort, profile, dir = WEB }) {
	const server = spawn('python', ['-m', 'http.server', String(httpPort), '--bind', '127.0.0.1', '--directory', dir], { stdio: 'ignore' });
	const chrome = spawn(findBrowser(), [
		'--headless=new', '--mute-audio', `--remote-debugging-port=${cdpPort}`,
		`--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check',
		'--window-size=1280,720', '--enable-unsafe-swiftshader', 'about:blank',
	], { stdio: 'ignore' });
	const stop = async () => {
		try { // kill だけだと Chrome の子プロセスが残ることがある
			const version = await (await fetch(`http://127.0.0.1:${cdpPort}/json/version`)).json();
			await (await connect(version.webSocketDebuggerUrl)).send('Browser.close');
		} catch { /* もう終わっている */ }
		if (chrome.exitCode === null) await Promise.race([new Promise((ok) => chrome.once('exit', ok)), sleep(SCREEN_SETTLE_MS)]);
		chrome.kill();
		server.kill();
	};
	const target = await waitFor(async () => {
		try {
			const list = await (await fetch(`http://127.0.0.1:${cdpPort}/json/list`)).json();
			return list.find((t) => t.type === 'page');
		} catch { return null; }
	}, BOOT_TIMEOUT_MS);
	if (!target) { await stop(); return null; }
	const page = await connect(target.webSocketDebuggerUrl);
	const logs = [];
	page.onEvent((msg) => {
		if (msg.method === 'Runtime.consoleAPICalled') {
			logs.push({ level: msg.params.type, text: msg.params.args.map((a) => a.value ?? a.description).join(' ') });
		} else if (msg.method === 'Runtime.exceptionThrown') {
			logs.push({ level: 'exception', text: msg.params.exceptionDetails.exception?.description ?? msg.params.exceptionDetails.text });
		} else if (msg.method === 'Log.entryAdded') {
			logs.push({ level: msg.params.entry.level, text: `${msg.params.entry.text} ${msg.params.entry.url ?? ''}` });
		}
	});
	await page.send('Runtime.enable');
	await page.send('Log.enable');
	await page.send('Page.enable');
	// 窓が無くてもフォーカスがある扱いにする（無いと自動ポーズ FR-47 がかかる）
	await page.send('Emulation.setFocusEmulationEnabled', { enabled: true });
	// 撮る絵をゲームの画面と同じ 1280×720 にする（窓の大きさのままだと少し小さくなる）
	await page.send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
	const evaluate = async (expression) =>
		(await page.send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })).result.value;
	return {
		page,
		logs,
		origin: `http://127.0.0.1:${httpPort}`,
		boots: () => logs.filter((l) => l.text.startsWith('Godot Engine v')).length,
		open: (url) => page.send('Page.navigate', { url }),
		shot: async (file) => {
			const { data } = await page.send('Page.captureScreenshot', { format: 'png' });
			writeFileSync(file, Buffer.from(data, 'base64'));
		},
		press: async (name) => {
			if (!(name in KEYS)) throw new Error(`web_lib: キー ${name} は KEYS に無い`); // 無いキーは何も送らずに素通りしていた
			await page.send('Input.dispatchKeyEvent', { type: 'keyDown', ...KEYS[name] });
			await page.send('Input.dispatchKeyEvent', { type: 'keyUp', ...KEYS[name] });
		},
		readUserfs: async () => (await evaluate(READ_USERFS)) ?? {},
		writeUserfs: (files) => evaluate(writeUserfsExpr(files)),
		errors: () => logs.filter((l) => ['error', 'exception'].includes(l.level)),
		close: async () => { page.close(); await stop(); },
	};
}
