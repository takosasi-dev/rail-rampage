// README に載せる絵を撮る: Web 書き出しを窓なし・消音の Chrome で開き、タイトル・ステージ選択・車庫と、
// 走っている所の連続写真（GIF の元）を build/readme_shots/ に撮る。どれを docs/images/ に入れるかは人が選ぶ。
// 実行: node tests/shoot_readme.mjs [第何試験か（既定 4）]（先に Web 書き出し）。GIF の作り方は README の tests の表
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { ROOT, SCREEN_SETTLE_MS, launch, sleep, waitFor, BOOT_TIMEOUT_MS } from './web_lib.mjs';

const OUT = path.join(ROOT, 'build', 'readme_shots');
const STAGE = Number(process.argv[2] ?? 4);
const BURST_MS = 9000; // 連続写真を撮る長さ
const SAVE = Array.from({ length: 10 }, (_, i) =>
	`[stage_${String(i + 1).padStart(2, '0')}]\n\ncleared=true\nbest_score=0\nstars=0\n`).join('\n')
	+ '\n[stamps]\n\nbasic="2026-09-21"\nall_clear="2026-09-26"\nchain="2026-09-22"\n';
const SETTINGS = '[settings]\n\nse_volume=0\nscreen_shake=true\ntime_of_day_mode="stage"\nshow_ghost=false\n';

rmSync(OUT, { recursive: true, force: true });
mkdirSync(path.join(OUT, 'burst'), { recursive: true });
const b = await launch({ httpPort: 8767, cdpPort: 9767, profile: path.join(OUT, 'profile') });
if (!b) throw new Error('Chrome に接続できない');
try {
	const shot = (name) => b.shot(path.join(OUT, `${name}.png`));
	const openGame = async () => {
		const before = b.boots();
		await b.open(`${b.origin}/index.html`);
		await waitFor(() => b.boots() > before, BOOT_TIMEOUT_MS);
		await sleep(SCREEN_SETTLE_MS);
	};
	await openGame();
	await sleep(SCREEN_SETTLE_MS);
	await b.open(`${b.origin}/__blank`);
	await sleep(SCREEN_SETTLE_MS / 4);
	await b.writeUserfs({ 'save.cfg': SAVE, 'settings.cfg': SETTINGS });
	await openGame();
	await shot('title');
	await b.press('Enter'); // 「試験開始」
	await sleep(SCREEN_SETTLE_MS);
	await shot('select');
	await b.press('ArrowUp'); // 「車両を選ぶ」
	await b.press('Enter');
	await sleep(SCREEN_SETTLE_MS);
	await shot('garage');
	await openGame();
	await b.press('Enter');
	await sleep(SCREEN_SETTLE_MS);
	for (let k = 1; k < STAGE; k++) { await b.press('ArrowRight'); await sleep(150); }
	await b.press('Enter');
	await sleep(500);
	// 1枚ずつ撮ると遅い（約 2 fps）ので、画面の配信（screencast）で描けた絵をすべて受け取る。時刻は GIF の間隔に使う
	const times = [];
	b.page.onEvent((msg) => {
		if (msg.method !== 'Page.screencastFrame') return;
		const { data, sessionId, metadata } = msg.params;
		writeFileSync(path.join(OUT, 'burst', `${String(times.length).padStart(4, '0')}.jpg`), Buffer.from(data, 'base64'));
		times.push(metadata.timestamp);
		b.page.send('Page.screencastFrameAck', { sessionId });
	});
	await b.page.send('Page.startScreencast', { format: 'jpeg', quality: 90, maxWidth: 960, maxHeight: 540 });
	await sleep(BURST_MS);
	await b.page.send('Page.stopScreencast');
	writeFileSync(path.join(OUT, 'burst', 'times.json'), JSON.stringify(times));
	console.log(`連続写真 ${times.length} 枚 / ${BURST_MS} ms（約 ${(times.length * 1000 / BURST_MS).toFixed(1)} fps）: ${OUT}`);
} finally {
	await b.close();
}
