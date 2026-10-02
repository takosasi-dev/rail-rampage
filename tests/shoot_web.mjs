// ① プレイ画面の絵の見た目の確かめ（設計書7章）: Web 書き出しを窓なし・消音の Chrome で開き、
// タイトル・ステージ選択（2ページ）・設定・試験記録・修了証書・車庫・ポーズと、全試験を時間帯 A「順に進む」と
// C「見どころに合わせる」で撮る。
// ゲームのコードは変えず、ブラウザの保存領域（IndexedDB）に「全ステージ解放」の記録と時間帯の設定を書いてから開く。
// 実行: node tests/shoot_web.mjs（先に Web 書き出し。約10分）。画面の写しは build/web_shots/
import { existsSync, mkdirSync, rmSync } from 'node:fs';
import path from 'node:path';
import { BOOT_TIMEOUT_MS, ROOT, SCREEN_SETTLE_MS, WEB, findBrowser, launch, sleep, waitFor } from './web_lib.mjs';

const OUT = path.join(ROOT, 'build', 'web_shots');
const HTTP_PORT = 8766;
const CDP_PORT = 9766;
const STAGES = 10;
const RUN_MS = 5000; // 走り出してから2枚目を撮るまで
const KEY_GAP_MS = 150;
const BLANK = '__shoot_web_blank'; // エンジンを止めるために移る、同じ origin の無いページ（404）
const SAVE_ALL_CLEARED = Array.from({ length: STAGES }, (_, i) =>
	`[stage_${String(i + 1).padStart(2, '0')}]\n\ncleared=true\nbest_score=0\nstars=0\n`).join('\n');
// 試験記録・修了証書を撮るときの記録: 全ステージ合格に、累計と検定印をいくつか足す（records-design.md 2.1）
const SAVE_RECORDS = SAVE_ALL_CLEARED + `
[stats]

runs=47
clears=21
crashes=19
derails=7
smashed={"crate": 412, "barrel": 64, "dummy": 88, "drum": 23, "wall": 12}
girigiri=6
best_speed=1012.0
best_combo=18
distance=853200.0
attempts={1: 12, 2: 9, 3: 8}
completed_on="2026-09-26"

[stamps]

basic="2026-09-21"
all_clear="2026-09-26"
chain="2026-09-22"
first_crash="2026-09-21"
first_derail="2026-09-23"
`;
const settings = (mode) => `[settings]\n\nse_volume=0\nscreen_shake=true\ntime_of_day_mode="${mode}"\n`;

let failures = 0;
function expect(ok, label) {
	console.log(`${ok ? 'OK' : 'NG'}  ${label}`);
	if (!ok) failures++;
	return ok;
}

async function main() {
	if (!expect(existsSync(path.join(WEB, 'index.html')), 'build/web/index.html がある（Web 書き出し済み）')) return;
	if (!expect(findBrowser() !== undefined, 'Chrome か Edge がある')) return;
	rmSync(OUT, { recursive: true, force: true });
	mkdirSync(OUT, { recursive: true });
	const b = await launch({ httpPort: HTTP_PORT, cdpPort: CDP_PORT, profile: path.join(OUT, 'profile') });
	if (!expect(b !== null, 'Chrome に接続できる')) return;
	try {
		const shot = (name) => b.shot(path.join(OUT, `${name}.png`));
		// ゲームを開き、起動の知らせ（console の "Godot Engine v"）を待って、画面が落ち着くまで待つ
		const openGame = async () => {
			const before = b.boots();
			await b.open(`${b.origin}/index.html`);
			const ok = await waitFor(() => b.boots() > before, BOOT_TIMEOUT_MS);
			await sleep(SCREEN_SETTLE_MS);
			return ok !== null;
		};
		// エンジンを止めて（同じ origin の無いページへ移って）から user:// に書く
		const writeFiles = async (files) => {
			await b.open(`${b.origin}/${BLANK}`);
			await sleep(SCREEN_SETTLE_MS / 4);
			await b.writeUserfs(files);
		};
		if (!expect(await openGame(), '1回目の起動（保存領域とフォルダを作る）')) return;
		await sleep(SCREEN_SETTLE_MS); // シェーダーの記録を書き終えるまで
		await writeFiles({ 'save.cfg': SAVE_ALL_CLEARED, 'settings.cfg': settings('sequence') });
		if (!expect(await openGame(), '全ステージ解放の記録と時間帯 A の設定を書いて開き直せる')) return;
		await shot('title');
		await b.press('Enter');
		await sleep(SCREEN_SETTLE_MS);
		await shot('select_A');
		await openGame();
		await b.press('ArrowDown'); // 「試験記録」
		await b.press('ArrowDown'); // 「設定」
		await b.press('Enter');
		await sleep(SCREEN_SETTLE_MS);
		await shot('settings');
		await writeFiles({ 'save.cfg': SAVE_RECORDS });
		if (expect(await openGame(), '累計と検定印を足した記録を書いて開き直せる')) {
			await b.press('ArrowDown'); // 「試験記録」
			await b.press('Enter');
			await sleep(SCREEN_SETTLE_MS);
			await shot('records');
			await b.press('Enter'); // 全試験に合格しているので「修了証書」にフォーカスがある
			await sleep(SCREEN_SETTLE_MS);
			await shot('certificate');
			// 車庫: 記録で全車両が解放されている（第3・5試験の合格と、検定印「連鎖反応」「全課程修了」）
			await openGame();
			await b.press('Enter'); // タイトルの「試験開始」
			await sleep(SCREEN_SETTLE_MS);
			await b.press('ArrowUp'); // 「車両を選ぶ」
			await b.press('Enter');
			await sleep(SCREEN_SETTLE_MS);
			await shot('garage');
		}
		// 上部中央のステージ札（17.4 の 490,24 300×34）の絵。違うステージに入れたかを見分ける
		const stageTag = async () => (await b.page.send('Page.captureScreenshot',
			{ format: 'png', clip: { x: 490, y: 24, width: 300, height: 34, scale: 1 } })).data;
		for (const [label, mode] of [['A', 'sequence'], ['C', 'stage']]) {
			await writeFiles({ 'settings.cfg': settings(mode) });
			const tags = new Set();
			for (let n = 1; n <= STAGES; n++) {
				if (!expect(await openGame(), `${label} 第${n}試験を開ける`)) continue;
				await b.press('Enter'); // タイトルの「試験開始」
				await sleep(SCREEN_SETTLE_MS);
				if (n === 1 && label === 'C') await shot('select_C');
				for (let k = 1; k < n; k++) {
					await b.press('ArrowRight');
					await sleep(KEY_GAP_MS);
				}
				if (n === STAGES && label === 'A') await shot('select_A_page2'); // 応用課程のページ
				await b.press('Enter'); // 「試験開始」
				await sleep(SCREEN_SETTLE_MS);
				await shot(`stage${n}_${label}_1`);
				tags.add(await stageTag());
				await sleep(RUN_MS);
				await shot(`stage${n}_${label}_2`);
				await sleep(RUN_MS); // 奥の壁・ジャンプ・分岐も写るように、もう1枚
				await shot(`stage${n}_${label}_3`);
				if (n === 1 && label === 'A') {
					await b.press('Escape');
					await sleep(SCREEN_SETTLE_MS / 2);
					await shot('pause');
				}
			}
			expect(tags.size === STAGES, `${label}: 第1〜${STAGES}試験にそれぞれ入れた（ステージ札が ${tags.size} 種類）`);
		}
		// 無いページ（404）と、その favicon の読み込み失敗は数えない
		const bad = b.errors().filter((l) => !l.text.includes(BLANK) && !l.text.includes('favicon.ico'));
		bad.forEach((l) => console.log(`    [${l.level}] ${l.text}`));
		expect(bad.length === 0, 'ブラウザのコンソールにエラーが出ない');
		console.log(`画面の写し: ${OUT}`);
	} finally {
		await b.close();
	}
}

await main();
console.log(failures === 0 ? 'ALL OK' : `${failures} 件 NG`);
process.exitCode = failures === 0 ? 0 : 1; // process.exit() は Windows の Node で libuv の assert に当たることがある
