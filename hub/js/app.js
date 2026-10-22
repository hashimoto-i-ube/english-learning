'use strict';
// 英語マスター ULSハブ版。素の JS。学習記録は ToolStorage（hub-bridge.js）経由で保存する。
const $app = document.getElementById('app'), $title = document.getElementById('title'), $back = document.getElementById('back');
const DAY = 86400000, INTERVALS = [1, 3, 7, 14, 30, 60], NEW_PER_SESSION = 10;
const LEVELS = [1, 2, 3, 4, 5, 6, 7];
const KINDS = { vocab: '英単語', idioms: '英熟語' };
const SOON = ['英文解釈', '英作文', '基礎知識', '模擬試験'];
const cache = {};
let manifest = null, P = { cards: {}, ex: {}, log: {}, newToday: { date: '', n: 0 } }, backTo = '#/';

const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const today = () => { const d = new Date(); return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`; };
const shuffle = a => { a = a.slice(); for (let i = a.length - 1; i > 0; i--) { const j = Math.random() * (i + 1) | 0; [a[i], a[j]] = [a[j], a[i]]; } return a; };
const save = () => window.ToolStorage.setItem('progress', JSON.stringify(P)).catch(() => {});
const bump = () => { P.log[today()] = (P.log[today()] || 0) + 1; };

async function load(file) {
  if (!cache[file]) cache[file] = fetch('content/' + file).then(r => { if (!r.ok) throw new Error(file); return r.json(); });
  return cache[file];
}
const packFiles = re => manifest.packs.filter(p => re.test(p.file)).map(p => p.file);
async function wordsOf(kind, lv) {
  const pre = kind === 'vocab' ? 'vocab' : 'idioms';
  const files = packFiles(new RegExp(`${pre}-l${lv}\\.json$`));
  const packs = await Promise.all(files.map(load));
  return packs.flatMap(p => p.words || []);
}
const dueCount = () => Object.values(P.cards).filter(c => c.d <= Date.now()).length;
const learnedCount = () => Object.values(P.cards).filter(c => c.b >= 1).length;

// ---- 簡易 Markdown ----
const inline = s => esc(s).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').replace(/\*(.+?)\*/g, '<i>$1</i>');
function md(src) {
  return String(src || '').split(/\n\s*\n/).map(b => {
    const ls = b.split('\n');
    if (/^## /.test(b)) return `<h3>${inline(b.slice(3))}</h3>`;
    if (/^### /.test(b)) return `<h4>${inline(b.slice(4))}</h4>`;
    if (ls.every(l => /^- /.test(l))) return `<ul>${ls.map(l => `<li>${inline(l.slice(2))}</li>`).join('')}</ul>`;
    if (ls.every(l => /^>/.test(l))) return `<blockquote>${ls.map(l => inline(l.replace(/^>\s?/, ''))).join('<br>')}</blockquote>`;
    if (ls.every(l => /^\|/.test(l))) {
      const rows = ls.filter(l => !/^\|[\s\-:|]+\|?$/.test(l)).map(l => l.replace(/^\||\|$/g, '').split('|'));
      return `<table>${rows.map((r, i) => `<tr>${r.map(c => `<${i ? 'td' : 'th'}>${inline(c.trim())}</${i ? 'td' : 'th'}>`).join('')}</tr>`).join('')}</table>`;
    }
    return `<p>${ls.map(inline).join('<br>')}</p>`;
  }).join('');
}

function view(title, html, back) {
  $title.textContent = title;
  backTo = back || '';
  $back.hidden = !back;
  $app.innerHTML = html;
  window.scrollTo(0, 0);
}
const go = h => { location.hash = h; };
$back.onclick = () => go(backTo);

// ---- 画面 ----
function home() {
  const tiles = [
    ['#/words/vocab', '英単語', 'Lv1〜7 カード学習・4択'],
    ['#/words/idioms', '英熟語', 'Lv1〜7 カード学習・4択'],
    ['#/grammar', '文法・語法', '解説と演習'],
    ['#/reading', '長文読解', '本文・訳・設問'],
  ].map(([h, t, s]) => `<a class="tile" href="${h}"><b>${t}</b><span>${s}</span></a>`).join('')
    + SOON.map(t => `<div class="tile off"><b>${t}<em class="badge">準備中</em></b><span>後日追加</span></div>`).join('');
  const nt = P.newToday.date === today() ? P.newToday.n : 0;
  view('英語マスター', `
    <div class="stats"><div class="stat"><b>${dueCount()}</b><span>今日の復習</span></div>
    <div class="stat"><b>${nt}</b><span>今日の新規</span></div>
    <div class="stat"><b>${learnedCount()}</b><span>学習済み語</span></div></div>
    <a class="btn" href="#/review" style="text-decoration:none">復習を始める（${dueCount()}件）</a>
    <h2>分野</h2><div class="grid">${tiles}</div>`);
}

function levelPicker(kind) {
  view(KINDS[kind], `<div class="grid">${LEVELS.map(l => `<a class="tile" href="#/words/${kind}/${l}"><b>Lv${l}</b><span>${KINDS[kind]}</span></a>`).join('')}</div>`, '#/');
}

async function levelPage(kind, lv) {
  const words = await wordsOf(kind, lv);
  const known = words.filter(w => (P.cards[w.id] || {}).b >= 1).length;
  const due = words.filter(w => P.cards[w.id] && P.cards[w.id].d <= Date.now()).length;
  view(`Lv${lv} ${KINDS[kind]}`, `
    <div class="card"><b>${known} / ${words.length}</b> 語 学習済み<div class="progress"><i style="width:${words.length ? known / words.length * 100 : 0}%"></i></div>
    <span class="muted small">復習待ち ${due} 件</span></div>
    <a class="btn" href="#/study/${kind}/${lv}" style="text-decoration:none">カード学習</a>
    <a class="btn sub" href="#/quiz/${kind}/${lv}" style="text-decoration:none">4択クイズ（10問）</a>
    <h2>一覧</h2><div class="card">${words.map(w => `<div class="list-item"><b>${esc(w.headword)}</b><span>${esc((w.meanings || []).join('、'))}</span></div>`).join('')}</div>`, `#/words/${kind}`);
}

// 間隔反復の簡易版：覚えた→箱+1（1,3,7,14,30,60日）、もう一度→箱0・当日中に再出題
function cardSession(words, title, back) {
  const now = Date.now();
  const due = words.filter(w => P.cards[w.id] && P.cards[w.id].d <= now);
  const fresh = words.filter(w => !P.cards[w.id]).slice(0, NEW_PER_SESSION);
  let queue = shuffle(due).slice(0, 30).concat(fresh), total = queue.length, done = 0, missed = new Set(), flipped = false;
  const draw = () => {
    if (!queue.length) {
      view(title, `<div class="card center"><h2>お疲れさまでした</h2><p>${total ? `${total} 枚を学習しました。` : '今は学習するカードがありません。'}</p></div><a class="btn" href="${back}" style="text-decoration:none">戻る</a>`, back);
      return;
    }
    const w = queue[0]; flipped = false;
    view(title, `
      <div class="muted small">残り ${queue.length} 枚</div><div class="progress"><i style="width:${total ? done / total * 100 : 0}%"></i></div>
      <div class="card flash" id="card"><div class="hw">${esc(w.headword)}</div>
      <div class="muted">${esc(w.pos || '')} ${esc(w.ipa || '')}</div><div class="muted small" style="margin-top:12px">タップして答えを見る</div></div>
      <div id="act"></div>`, back);
    const flip = () => {
      if (flipped) return; flipped = true;
      const ex = w.example ? `<div class="ex en">${esc(w.example.en)}<br><span class="muted">${esc(w.example.ja)}</span></div>` : '';
      document.getElementById('card').innerHTML = `<div class="hw">${esc(w.headword)}</div><div class="mean">${esc((w.meanings || []).join('、'))}</div><div class="muted">${esc(w.pos || '')} ${esc(w.ipa || '')}</div>${ex}${w.note ? `<div class="muted small">${esc(w.note)}</div>` : ''}`;
      document.getElementById('act').innerHTML = `<div class="row"><button class="btn ng" id="again">もう一度</button><button class="btn ok" id="got">覚えた</button></div>`;
      document.getElementById('again').onclick = () => rate(false);
      document.getElementById('got').onclick = () => rate(true);
    };
    document.getElementById('card').onclick = flip;
    const rate = ok => {
      const c = P.cards[w.id], isNew = !c;
      if (isNew) { const t = today(); if (P.newToday.date !== t) P.newToday = { date: t, n: 0 }; P.newToday.n++; }
      queue.shift();
      if (ok) {
        const b = missed.has(w.id) ? 0 : Math.min(((c || { b: 0 }).b) + 1, INTERVALS.length);
        P.cards[w.id] = { b, d: Date.now() + INTERVALS[Math.max(b - 1, 0)] * DAY };
        done++;
      } else {
        missed.add(w.id);
        P.cards[w.id] = { b: 0, d: Date.now() };
        queue.splice(Math.min(3, queue.length), 0, w);
      }
      bump(); save(); draw();
    };
  };
  draw();
}

async function study(kind, lv) {
  const words = await wordsOf(kind, lv);
  cardSession(words, `Lv${lv} ${KINDS[kind]}`, `#/words/${kind}/${lv}`);
}
async function review() {
  const ids = Object.keys(P.cards).filter(id => P.cards[id].d <= Date.now());
  const all = (await Promise.all(packFiles(/(vocab|idioms)-l\d\.json$/).map(load))).flatMap(p => p.words || []);
  const set = new Set(ids);
  const words = all.filter(w => set.has(w.id));
  cardSession(words, '復習', '#/');
}

// 問題の出題（選択・空所補充のみ対応）
function runQuiz(list, title, back, onAnswer) {
  let i = 0, right = 0;
  const next = () => {
    if (i >= list.length) {
      view(title, `<div class="card center"><h2>結果</h2><p style="font-size:28px;margin:0"><b>${right} / ${list.length}</b></p></div><a class="btn" href="${back}" style="text-decoration:none">戻る</a>`, back);
      return;
    }
    const q = list[i];
    const fb = ok => `<div class="fb card">${ok ? '<b style="color:var(--ok)">正解</b>' : `<b style="color:var(--ng)">不正解</b>　正解：${esc(q.answers[0])}`}<div class="prose">${md(q.explanation)}</div></div><button class="btn" id="nx">${i + 1 < list.length ? '次へ' : '結果を見る'}</button>`;
    const finish = ok => { if (ok) right++; if (onAnswer) onAnswer(q, ok); bump(); save(); document.getElementById('nx').onclick = () => { i++; next(); }; };
    const head = `<div class="muted small">${i + 1} / ${list.length}</div><div class="progress"><i style="width:${i / list.length * 100}%"></i></div><div class="card"><div class="muted small">${esc(q.prompt || '')}</div><div style="font-size:18px;margin-top:6px">${esc(q.sentence || q.question || '')}</div></div>`;
    if (q.type === 'fill') {
      view(title, `${head}<input id="ans" class="choice" autocapitalize="off" autocomplete="off" placeholder="答えを入力"><button class="btn" id="ok">答え合わせ</button><div id="res"></div>`, back);
      document.getElementById('ok').onclick = () => {
        const v = document.getElementById('ans').value.trim().toLowerCase();
        const ok = q.answers.some(a => a.trim().toLowerCase() === v);
        document.getElementById('ok').remove(); document.getElementById('ans').disabled = true;
        document.getElementById('res').innerHTML = fb(ok); finish(ok);
      };
    } else {
      view(title, `${head}${q.choices.map((c, k) => `<button class="choice" data-k="${k}">${esc(c)}</button>`).join('')}<div id="res"></div>`, back);
      $app.querySelectorAll('.choice').forEach(b => b.onclick = () => {
        const c = q.choices[+b.dataset.k], ok = q.answers.includes(c);
        $app.querySelectorAll('.choice').forEach(x => { x.disabled = true; if (q.answers.includes(q.choices[+x.dataset.k])) x.classList.add('right'); });
        if (!ok) b.classList.add('wrong');
        document.getElementById('res').innerHTML = fb(ok); finish(ok);
      });
    }
  };
  next();
}
const playable = ex => ex.filter(e => (e.type === 'choice' && e.choices) || (e.type === 'fill' && e.answers));
const markEx = (q, ok) => { P.ex[q.id] = ok ? 1 : 0; };

async function wordQuiz(kind, lv) {
  const words = await wordsOf(kind, lv);
  const pool = words.filter(w => (w.meanings || []).length);
  const qs = shuffle(pool).slice(0, 10).map(w => {
    const m = w.meanings.join('、');
    const wrong = shuffle(pool.filter(x => x.id !== w.id)).map(x => x.meanings.join('、')).filter((v, i, a) => v !== m && a.indexOf(v) === i).slice(0, 3);
    return { id: w.id, type: 'choice', prompt: '意味として最も適切なものを選びなさい。', sentence: w.headword, choices: shuffle([m, ...wrong]), answers: [m], explanation: (w.example ? `${w.example.en}\n${w.example.ja}` : '') };
  });
  runQuiz(qs, `Lv${lv} ${KINDS[kind]} クイズ`, `#/words/${kind}/${lv}`, (q, ok) => { if (!ok && P.cards[q.id]) P.cards[q.id] = { b: 0, d: Date.now() }; });
}

async function grammar() {
  const units = (await load('packs/grammar-core.json')).units;
  const lvs = [...new Set(units.map(u => u.level))].sort((a, b) => a - b);
  let cur = lvs[0];
  const draw = () => view('文法・語法', `<div class="seg">${lvs.map(l => `<button class="${l === cur ? 'on' : ''}" data-l="${l}">Lv${l}</button>`).join('')}</div>
    <div class="grid" style="margin-top:12px">${units.filter(u => u.level === cur).map(u => {
      const ex = playable(u.exercises || []), done = ex.filter(e => P.ex[e.id] === 1).length;
      return `<a class="tile" href="#/unit/${u.id}"><b>${esc(u.title)}</b><span>${esc(u.category || '')} ・ ${done}/${ex.length}問正解</span></a>`; }).join('')}</div>`, '#/');
  draw();
  $app.onclick = e => { const b = e.target.closest('.seg button'); if (b) { cur = +b.dataset.l; draw(); } };
}
async function unit(id) {
  const u = (await load('packs/grammar-core.json')).units.find(x => x.id === id);
  if (!u) return go('#/grammar');
  const ex = playable(u.exercises || []);
  view(u.title, `<div class="card prose">${md(u.explanation)}${(u.examples || []).map(e => `<div class="ex">${esc(e.en)}<br><span class="muted">${esc(e.ja)}</span></div>`).join('')}</div>
    ${ex.length ? `<button class="btn" id="go">演習に進む（${ex.length}問）</button>` : ''}`, '#/grammar');
  const b = document.getElementById('go');
  if (b) b.onclick = () => runQuiz(shuffle(ex), u.title, `#/unit/${id}`, markEx);
}

async function reading() {
  const ps = (await load('packs/reading-core.json')).passages;
  view('長文読解', `<div class="grid">${ps.map(p => `<a class="tile" href="#/passage/${p.id}"><b>${esc(p.title)}</b><span>Lv${p.level} ・ ${esc(p.topic || '')} ・ 約${p.targetMinutes || '?'}分</span></a>`).join('')}</div>`, '#/');
}
async function passage(id) {
  const p = (await load('packs/reading-core.json')).passages.find(x => x.id === id);
  if (!p) return go('#/reading');
  const ex = playable(p.questions || []);
  view(p.title, `<div class="card prose">${p.paragraphs.map((t, i) => `<p lang="en">${esc(t)}</p><p class="muted small tr" hidden>${esc((p.translation || [])[i] || '')}</p>`).join('')}</div>
    <button class="btn sub" id="tr">日本語訳を表示／非表示</button>
    ${(p.glossary || []).length ? `<h2>語句</h2><div class="card">${p.glossary.map(g => `<div class="list-item"><b>${esc(g.term)}</b><span>${esc(g.meaning)}</span></div>`).join('')}</div>` : ''}
    ${ex.length ? `<button class="btn" id="go">設問に進む（${ex.length}問）</button>` : ''}`, '#/reading');
  document.getElementById('tr').onclick = () => $app.querySelectorAll('.tr').forEach(e => e.hidden = !e.hidden);
  const b = document.getElementById('go');
  if (b) b.onclick = () => runQuiz(ex, p.title, `#/passage/${id}`, markEx);
}

async function route() {
  const [r, a, b] = location.hash.replace(/^#\//, '').split('/');
  try {
    if (!r) home();
    else if (r === 'words' && !b) levelPicker(a);
    else if (r === 'words') await levelPage(a, b);
    else if (r === 'study') await study(a, b);
    else if (r === 'quiz') await wordQuiz(a, b);
    else if (r === 'review') await review();
    else if (r === 'grammar') await grammar();
    else if (r === 'unit') await unit(a);
    else if (r === 'reading') await reading();
    else if (r === 'passage') await passage(a);
    else home();
  } catch (e) {
    view('エラー', `<div class="card">読み込めませんでした。<br><span class="muted small">${esc(e.message)}</span></div>`, '#/');
  }
}

(async () => {
  try {
    await window.ToolStorage.ready;
    const raw = await window.ToolStorage.getItem('progress');
    if (raw) P = Object.assign(P, JSON.parse(raw));
    manifest = await (await fetch('content/manifest.json')).json();
  } catch (e) { $app.innerHTML = `<p class="center muted">起動に失敗しました：${esc(e.message)}</p>`; return; }
  window.addEventListener('hashchange', route);
  route();
})();
