// AC-16（NFR-3）: Web 書き出しを `python -m http.server` で配信し、窓を出さない消音の Chrome で開いて、
// キーボードだけでステージ1をクリアできるか確かめる。クリアしたかは IndexedDB に残る user://save.cfg で見る。
// 開き直して記録が残っているか（FR-48）も見る。画面の写しは build/web_check/ に残す。
// 実行: node tests/check_web.mjs（先に Web 書き出しをしておく。Node 22 以降・Python・Chrome か Edge が要る）
import { existsSync, mkdirSync, rmSync } from 'node:fs';
import path from 'node:path';
import { BOOT_TIMEOUT_MS, ROOT, SCREEN_SETTLE_MS, WEB, findBrowser, launch, sleep, waitFor } from './web_lib.mjs';

const OUT = path.join(ROOT, 'build', 'web_check');
const HTTP_PORT = 8765;
const CDP_PORT = 9765;
const CLEAR_TIMEOUT_MS = 180000;

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
		const saveCfg = async () => Object.entries(await b.readUserfs()).find(([k]) => k.endsWith('/save.cfg'))?.[1] ?? '';
		const stage1Cleared = (cfg) => /\[stage_01\][^[]*cleared=true/.test(cfg);

		await b.open(`${b.origin}/index.html`);
		if (!expect(await waitFor(() => b.boots() >= 1, BOOT_TIMEOUT_MS), 'スレッド無しの配信（COOP/COEP ヘッダー無し）でエンジンが起動する')) return;
		await sleep(SCREEN_SETTLE_MS);
		await shot('1_title');
		await b.press('Enter'); // タイトルの「試験開始」
		await sleep(SCREEN_SETTLE_MS);
		await shot('2_select');
		await b.press('Enter'); // 第1試験の「試験開始」
		await sleep(SCREEN_SETTLE_MS);
		await shot('3_game');
		await b.press('Space'); // 最初の分岐を切り替える（ステージ1はどの道でもゴールに着く）
		await sleep(SCREEN_SETTLE_MS / 4);
		await shot('4_toggled');
		const cleared = await waitFor(async () => stage1Cleared(await saveCfg()), CLEAR_TIMEOUT_MS, 1000);
		expect(cleared, 'キーボードだけでステージ1をクリアでき、記録が user:// に保存される（AC-16）');
		const cfg = await saveCfg();
		expect(/\[stats\][^[]*runs=1\b[^[]*clears=1\b/.test(cfg), '試験記録の累計（走った回数・合格）も user:// に保存される');
		await sleep(SCREEN_SETTLE_MS);
		await shot('5_result');

		await b.page.send('Page.reload');
		if (!expect(await waitFor(() => b.boots() >= 2, BOOT_TIMEOUT_MS), '開き直してもエンジンが起動する')) return;
		expect(stage1Cleared(await saveCfg()), '開き直しても記録が残っている');
		await sleep(SCREEN_SETTLE_MS);
		await b.press('Enter');
		await sleep(SCREEN_SETTLE_MS);
		await shot('6_select_after_reload');

		const bad = b.errors();
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
