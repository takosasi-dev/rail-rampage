// AC-16（NFR-3）: Web 書き出しを `python -m http.server` で配信し、窓を出さない消音の Chrome で開いて、
// キーボードだけでステージ1をクリアできるか確かめる。開き直して記録が残っているか（FR-48）も見る。画面の写しは build/web_check/ に残す。
// 保存の置き場（autoload/game_state.gd の頭）も確かめる。Web の保存は localStorage の rail-rampage/<ファイル名>。
// user:// の実体（IndexedDB の /userfs）は同じサイトの Godot のゲーム全部で 1 つで、どれかのタブが書くと、そのタブが起動した時の写しで
// 全体を書き戻す（別のタブ・別のゲームの保存が古い物に戻る・消える）ので、v0.1.1 からは user:// に書かない:
//   (1) v0.1.0 の /userfs の保存（設定・記録・ゴースト）を引き継ぎ、書くと localStorage に移る
//   (2) 起動した後に別のゲームが /userfs に書いた物が、ステージ1を走って保存した後も残る
//   別のタブとの間は、書く前の読み直しが無いので「最後に書いた方が勝つ」（ここでは確かめない）
// 実行: node tests/check_web.mjs（先に Web 書き出しをしておく。Node 22 以降・Python・Chrome か Edge が要る）
//       node tests/check_web.mjs --url https://takosasi-dev.github.io/rail-rampage/ で公開中の版に当てる（v0.1.0 は (1)(2) が落ちる）
import { existsSync, mkdirSync, rmSync } from 'node:fs';
import path from 'node:path';
import { BOOT_TIMEOUT_MS, ROOT, SCREEN_SETTLE_MS, USER_DIR, WEB, findBrowser, launch, sleep, waitFor } from './web_lib.mjs';

const URL_AT = process.argv.indexOf('--url');
const BASE = URL_AT >= 0 ? process.argv[URL_AT + 1] : null; // 末尾は '/'
const OUT = path.join(ROOT, 'build', BASE ? 'web_check_url' : 'web_check');
const HTTP_PORT = 8765;
const CDP_PORT = 9765;
const CLEAR_TIMEOUT_MS = 180000;
const AFTER_SAVE_MS = 8000; // v0.1.0 はゴールの保存の直後（1 秒足らず）に /userfs を書き戻す。その何倍か見る
const OTHER = '/userfs/godot/app_userdata/OtherGame/save.cfg'; // 同じサイトの別のゲームの保存の代わり
// v0.1.0 の保存（/userfs）。設定の車両は未解放なので、起動時に標準型へ戻して設定を書く（設定画面を触らずに移りを見られる）
const LEGACY = {
	'settings.cfg': '[settings]\n\nse_volume=40\ntrolley="heavy"\n',
	'save.cfg': '[stats]\n\nruns=7\n\n[endless]\n\nbest_score=4321\nbest_distance=123.0\n',
	'save_ghosts.cfg': '[stage_02]\n\ndata={\n"dt": 0.05,\n"paint": 0,\n"points": PackedVector3Array(0, 600, 0, 25, 600, 0),\n'
		+ '"score": 4321,\n"trolley": "standard"\n}\n',
};

let failures = 0;
function expect(ok, label) {
	console.log(`${ok ? 'OK' : 'NG'}  ${label}`);
	if (!ok) failures++;
	return ok;
}

async function main() {
	if (!BASE && !expect(existsSync(path.join(WEB, 'index.html')), 'build/web/index.html がある（Web 書き出し済み）')) return;
	if (!expect(findBrowser() !== undefined, 'Chrome か Edge がある')) return;
	rmSync(OUT, { recursive: true, force: true });
	mkdirSync(OUT, { recursive: true });
	const b = await launch({ httpPort: HTTP_PORT, cdpPort: CDP_PORT, profile: path.join(OUT, 'profile') });
	if (!expect(b !== null, 'Chrome に接続できる')) return;
	try {
		const base = BASE ?? `${b.origin}/`;
		const shot = (name) => b.shot(path.join(OUT, `${name}.png`));
		const booted = async (n, label) => expect(await waitFor(() => b.boots() >= n, BOOT_TIMEOUT_MS), label);
		// 記録の読み手: localStorage、無ければ /userfs（v0.1.0 にも当てられるように）
		const saveCfg = async () => (await b.saved('save.cfg')) ?? (await b.readUserfs())[`${USER_DIR}/save.cfg`] ?? '';
		const stage1Cleared = (cfg) => /\[stage_01\][^[]*cleared=true/.test(cfg);
		const hasOther = async () => OTHER in (await b.readUserfs());

		await b.open(`${base}index.html`); // 1回目の起動で /userfs の保存領域ができる
		if (!(await booted(1, 'スレッド無しの配信（COOP/COEP ヘッダー無し）でエンジンが起動する'))) return;
		await sleep(SCREEN_SETTLE_MS);
		await b.open(`${base}__blank`); // エンジンを止めて（同じ origin の無いページへ移って）から /userfs に書く
		await sleep(SCREEN_SETTLE_MS / 4);
		await b.writeUserfs(LEGACY);
		await b.open(`${base}index.html`);
		if (!(await booted(2, 'v0.1.0 の保存を入れて開き直してもエンジンが起動する'))) return;
		await sleep(SCREEN_SETTLE_MS);
		const settings = (await b.saved('settings.cfg')) ?? '';
		expect(/se_volume=40\b/.test(settings) && /trolley="standard"/.test(settings),
			`(1) v0.1.0 の設定（/userfs）を読み、書くと localStorage に移る（localStorage: ${JSON.stringify(settings)}）`);
		await b.userfsPut({ [OTHER]: 'other game' }); // このタブが起動した後に、別のゲームが書いた

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
		expect(cleared, 'キーボードだけでステージ1をクリアでき、記録が保存される（AC-16）');
		const save = (await b.saved('save.cfg')) ?? '';
		expect(stage1Cleared(save) && /\[stats\][^[]*runs=8\b[^[]*clears=1\b/.test(save) && /\[endless\][^[]*best_score=4321\b/.test(save),
			'(1) 記録は localStorage に入り、v0.1.0 の記録（/userfs の試験記録の累計 7 回・無限軌道）も引き継ぐ（走った回数 8・合格 1）');
		const ghosts = (await b.saved('save_ghosts.cfg')) ?? '';
		expect(/\[stage_01\]/.test(ghosts) && /\[stage_02\][^[]*"score": 4321\b/.test(ghosts),
			'(1) ゴーストは localStorage に入り、v0.1.0 のゴースト（/userfs の第2試験）も引き継ぐ');
		const t0 = Date.now();
		const gone = await waitFor(async () => !(await hasOther()), AFTER_SAVE_MS, 250);
		expect(!gone, gone ? `(2) 別のゲームが /userfs に書いた保存が、合格の記録を書いた後に消えた（見つけてから ${Date.now() - t0} ms で消えていた）`
			: `(2) 起動した後に別のゲームが /userfs に書いた保存が、ステージ1を走って保存した後も残る（${AFTER_SAVE_MS / 1000} 秒見た）`);
		const mine = Object.entries(await b.readUserfs()).filter(([k]) => k.startsWith(`${USER_DIR}/`));
		expect(mine.length === Object.keys(LEGACY).length && mine.every(([k, v]) => LEGACY[k.slice(USER_DIR.length + 1)] === v),
			`(2) /userfs の RailRampage のファイルは v0.1.0 の物のまま（user:// に書かない。${mine.map(([k]) => k.slice(USER_DIR.length + 1)).join(' ')}）`);
		await sleep(SCREEN_SETTLE_MS);
		await shot('5_result');

		await b.page.send('Page.reload');
		if (!(await booted(3, '開き直してもエンジンが起動する'))) return;
		expect(stage1Cleared(await saveCfg()), '開き直しても記録が残っている');
		await sleep(SCREEN_SETTLE_MS);
		await b.press('Enter');
		await sleep(SCREEN_SETTLE_MS);
		await shot('6_select_after_reload');
		expect(await hasOther(), '(2) 開き直した後も、別のゲームが /userfs に書いた保存が残る');

		// 起動時に localStorage を読む（/userfs の v0.1.0 の物より優先する）: ★3 の記録があれば検定印「満点答案」を付けて記録を書き直し、
		// 未解放の車両の設定は標準型に戻して設定を書き直す（音量は localStorage の 55。/userfs は 40）
		await b.open(`${base}__blank`);
		await sleep(SCREEN_SETTLE_MS / 4);
		await b.writeSaves({ 'save.cfg': '[stage_01]\n\ncleared=true\nbest_score=1\nstars=3\n', 'settings.cfg': '[settings]\n\nse_volume=55\ntrolley="heavy"\n' });
		await b.open(`${base}index.html`);
		if (!(await booted(4, 'localStorage の保存を入れて開き直してもエンジンが起動する'))) return;
		const reread = await waitFor(async () => /\[stamps\][^[]*full_marks=/.test((await b.saved('save.cfg')) ?? ''), SCREEN_SETTLE_MS * 5, 250);
		const settings2 = (await b.saved('settings.cfg')) ?? '';
		expect(reread && /se_volume=55\b/.test(settings2) && /trolley="standard"/.test(settings2),
			`起動時に localStorage の記録と設定を読む（記録: ${JSON.stringify(await b.saved('save.cfg'))}）`);

		// エンジンを止めるために開いた無いページ（とその favicon）の 404 は数えない
		const bad = b.errors().filter((l) => !/Failed to load resource.*\/(__blank|favicon\.ico)\b/.test(l.text));
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
