'use strict';
// 스킬 시험실 화면. 스킬·설명·수치·소리 자리는 서버가 데이터 파일에서 매번 읽은 값이고, 이 화면은 세지 않고 판정하지 않는다.
// 장면을 바꾸면 곧바로 시험 창(Godot)에 명령을 보낸다. 창이 없으면 고른 값만 들고 있다가 "시험실 열기"에서 함께 보낸다.
// 소리의 파형·길이·최대 dBFS·RMS 는 브라우저의 Web Audio 가 잰 값이다. 원격에서 열면 body[data-remote="1"] 로 창 띄우기·창 화면 저장 단추를 뺀다.
(function () {
  const $ = s => document.querySelector(s);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
  const remote = () => document.body.dataset.remote === '1';
  const LAYOUTS = [['single', '한 마리'], ['pack', '무리'], ['line', '줄'], ['elite', '우두머리'], ['crowd', '군중']];
  const FORMS = {base: '주력', evolved: '진화', descent: '강림'};
  const DEFAULTS = {layout: 'single', count: 8, motion: 'approach', durable: false, repeat: true, interval_s: 3, speed: 1, juice: true};
  const STATUS_TEXT = {none: '시험 창 없음', starting: '띄우는 중', connected: '연결됨', lost: '끊김'};
  let ov = null, open = false, timer = null, sig = '';
  let sel = {elem: null, form: 'base'}, opts = Object.assign({}, DEFAULTS), audio = {}, hero = false;
  let synced = false, sendTimer = null, message = '', msgKind = 'info', shotName = '', result = null;
  let clips = {A: null, B: null}, clipList = null, clipTimer = null;
  let ctx = null, source = null;
  const analysis = [];            // 이번 방문에서 들어 본 소리의 잰 값

  async function call(url, options) {
    const r = await fetch(url, options);
    let d;
    try { d = await r.json(); } catch { throw Object.assign(new Error('서버 응답을 읽을 수 없습니다.'), {status: r.status}); }
    if (!r.ok) throw Object.assign(new Error(d.error || '요청 실패 (' + r.status + ')'), {status: r.status, data: d});
    return d;
  }
  const post = (path, body) => call('/api/skill-lab/' + path, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body || {})});
  const say = (text, kind) => { message = text; msgKind = kind || 'info'; const b = $('#sl-msg'); if (b) { b.textContent = text; b.className = 'alert ' + msgKind; b.hidden = !text; } };

  const char = () => ov && ov.characters.find(c => c.elem === sel.elem);
  const form = () => { const c = char(); return c && c.forms.find(f => f.form === sel.form); };
  const sceneBody = () => { const c = char(); return Object.assign({character: c.id, skill: c.primary, form: sel.form}, opts); };
  const live = () => ov && ['connected', 'starting'].includes(ov.window.status);

  // ---------------------------------------------------------------- 화면 조립
  function charCards() {
    return ov.characters.map(c => {
      const forms = c.forms.map(f => `<button type="button" class="sl-form ${c.elem === sel.elem && f.form === sel.form ? 'on' : ''}" data-elem="${c.elem}" data-form="${f.form}" ${f.available ? '' : 'disabled'} aria-pressed="${c.elem === sel.elem && f.form === sel.form}">
        <span>${esc(f.label)}</span><small>${esc(f.name || '')}</small></button>`).join('');
      return `<article class="sl-char ${c.elem === sel.elem ? 'on' : ''}"><header><img alt="" src="/api/skill-lab/portrait?id=${c.elem}" ${c.portrait ? '' : 'hidden'}><div><strong>${esc(c.name)}</strong><small>${esc(c.title)}</small></div></header><div class="sl-forms">${forms}</div></article>`;
    }).join('');
  }

  function detailHtml() {
    const f = form(), c = char();
    if (!f) return '';
    let h = `<h3>${esc(f.name || f.label)} <small>${esc(c.name)} · ${esc(f.label)}</small></h3><p>${esc(f.text || '')}</p>`;
    if (f.note) h += `<p class="bl-help">${esc(f.note)}</p>`;
    if (f.table) h += `<div class="table-wrap"><table class="data-table"><thead><tr>${f.table.columns.map(x => `<th>${esc(x)}</th>`).join('')}</tr></thead><tbody>${f.table.rows.map(r => `<tr>${r.map(x => `<td>${esc(x)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
    if (f.pairs) h += '<dl class="properties">' + f.pairs.map(([k, v]) => `<div class="property"><dt>${esc(k)}</dt><dd>${esc(v)}</dd></div>`).join('') + '</dl>';
    return h + '<p class="bl-help">수치는 데이터 파일(growth_quality37.json, descent.json)과 글(ko.po)에서 지금 읽은 값입니다. 이 화면에서 고치지 않습니다.</p>';
  }

  function controlsHtml() {
    const lay = LAYOUTS.map(([k, n]) => `<button type="button" data-layout="${k}" class="${opts.layout === k ? 'on' : ''}" aria-pressed="${opts.layout === k}">${n}</button>`).join('');
    const spd = [0.25, 0.5, 1].map(v => `<button type="button" data-speed="${v}" class="${opts.speed === v ? 'on' : ''}" aria-pressed="${opts.speed === v}">${v === 1 ? '보통' : '×' + v}</button>`).join('');
    const ivs = [1.5, 2, 3, 4, 5, 6].map(v => `<option value="${v}" ${opts.interval_s === v ? 'selected' : ''}>${v}초</option>`).join('');
    const rm = remote();
    return `<div class="sl-bar">
      ${rm ? '' : `<button type="button" id="sl-open" class="primary">시험실 열기</button><button type="button" id="sl-close">닫기</button>`}
      <button type="button" id="sl-cast">지금 시전</button>${rm ? '' : '<button type="button" id="sl-shot">화면 저장</button>'}
    </div>
    <div class="sl-group"><span class="sl-k">적 배치</span><div class="sl-seg">${lay}</div></div>
    <div class="sl-group"><label class="sl-k" for="sl-count">마리 수 <b id="sl-count-n">${opts.count}</b></label><input id="sl-count" type="range" min="1" max="40" value="${opts.count}"></div>
    <div class="sl-group sl-checks">
      <label><input type="radio" name="sl-motion" value="approach" ${opts.motion === 'approach' ? 'checked' : ''}> 다가옴</label>
      <label><input type="radio" name="sl-motion" value="hold" ${opts.motion === 'hold' ? 'checked' : ''}> 제자리</label>
      <label><input type="checkbox" id="sl-durable" ${opts.durable ? 'checked' : ''}> 죽지 않음</label>
      <label><input type="checkbox" id="sl-juice" ${opts.juice ? 'checked' : ''}> 전투 효과</label></div>
    <div class="sl-group sl-checks"><label><input type="checkbox" id="sl-repeat" ${opts.repeat ? 'checked' : ''}> 되풀이</label>
      <label>간격 <select id="sl-interval">${ivs}</select></label>
      <span class="sl-k">느리게</span><div class="sl-seg">${spd}</div></div>
    ${rm ? '' : `<div class="sl-group sl-checks"><label><input type="checkbox" id="sl-hero" ${hero ? 'checked' : ''}> 3D 주인공 모델(바꾸면 창을 다시 띄웁니다)</label></div>`}
    <p class="bl-help">느리게 하면 소리의 높낮이는 바뀌지 않습니다. ${esc(ov.stage_note)}</p>`;
  }

  function statusHtml() {
    const w = ov.window, s = w.state || {};
    let h = `<span class="sl-dot ${w.status}"></span><strong>${STATUS_TEXT[w.status] || w.status}</strong>`;
    if (!w.script_exists) h += '<p class="sl-nowin">시험 창 스크립트(chapter1/tests/skill_lab.gd)가 아직 저장소에 없어 창을 띄울 수 없습니다.</p>';
    if (w.status === 'connected' || w.status === 'lost') {
      const run = s.run || {}, casts = s.casts || {};
      h += ` · 마지막 적용 명령 ${esc(s.applied_seq ?? '-')} · 심장 박동 ${w.heartbeat_age_ms == null ? '-' : (w.heartbeat_age_ms / 1000).toFixed(1) + '초 전'}`;
      h += `<br><small>판 ${esc(run.mode ?? '-')} · 살아 있는 적 ${esc(run.enemies_alive ?? '-')} · 세운 적 ${esc(run.staged ?? '-')} · 시전 ${esc(casts.count ?? 0)}번(마지막 ${esc(casts.last_form || '-')})</small>`;
      const errs = (s.errors || []).concat(((s.audio || {}).load_errors) || []);
      if (errs.length) h += `<ul class="sl-errs">${errs.slice(-4).map(e => `<li>${esc(typeof e === 'string' ? e : JSON.stringify(e))}</li>`).join('')}</ul>`;
    } else if (w.status === 'starting') h += ' · 5~15초 걸립니다';
    return h;
  }

  function slotsFor() {
    const rows = ov.slots.rows, c = char();
    if (!c) return {main: [], other: []};
    const own = (r, form) => r.owner && r.owner.elem === c.elem && r.owner.form === form;
    const main = rows.filter(r => own(r, sel.form)).concat(sel.form === 'evolved' ? rows.filter(r => own(r, 'base')).map(r => Object.assign({}, r, {shared: true})) : []);
    return {main, other: rows.filter(r => !r.owner)};
  }

  function fileButtons(prefix, n) {
    return Array.from({length: n}, (_, i) => `<button type="button" class="sl-play" data-play="${esc(prefix)}&n=${i}" aria-label="듣기 ${i + 1}">▶${n > 1 ? i + 1 : ''}</button>`).join('');
  }

  function slotHtml(r) {
    const cur = r.current, cands = ov.candidates.filter(c => c.slot === r.slot);
    const kind = {adopted: ['채택됨', 'is-ok'], parent: ['부모 소리', 'is-info'], silent: ['무음', 'is-warn']}[cur.kind] || [cur.kind, ''];
    const using = ov.window.override_ids[r.slot];
    const rows = cands.map(c => {
      const chosen = audio[r.slot] === c.id, inWin = using === c.id;
      return `<div class="sl-cand ${chosen ? 'chosen' : ''}"><div class="sl-cand-t"><strong>${esc(c.key)}</strong> <span>${esc(c.label)}</span>
        ${inWin ? '<span class="badge is-ok">창이 지금 씀</span>' : chosen ? '<span class="badge is-info">끼움 고름</span>' : ''}${c.missing.length ? '<span class="badge is-bad">파일 없음</span>' : ''}${c.origin_known ? '' : '<span class="badge deferred" title="후보 목록에 출처가 없음">출처 미확인</span>'}</div>
        <div class="sl-cand-b">${fileButtons('/api/skill-lab/audio?id=' + encodeURIComponent(c.id), c.paths.length)}
        <button type="button" data-fit="${esc(r.slot)}" data-cand="${esc(c.id)}" ${c.missing.length ? 'disabled' : ''}>끼우기</button>
        <button type="button" data-clip-cand="${esc(c.id)}" data-slot="${esc(r.slot)}" ${c.missing.length ? 'disabled' : ''}>이 소리로 영상</button>
        <button type="button" class="sl-adopt" data-adopt="${esc(c.id)}" data-slot="${esc(r.slot)}" ${ov.adopt.available && !c.missing.length ? '' : 'disabled'}>채택</button></div></div>`;
    }).join('') || '<p class="bl-help">이 자리에 올라온 후보가 없습니다.</p>';
    return `<section class="sl-slot" data-slot="${esc(r.slot)}"><h4>${esc(r.label)} <small>${esc(r.slot)}${r.shared ? ' · 기본 스킬의 자리' : ''}</small></h4>
      <div class="sl-cur"><span class="badge ${kind[1]}">${kind[0]}</span> <span>${esc(cur.note || (cur.kind === 'adopted' ? '채택: ' + (cur.candidate || '') + ' ' + (cur.date || '') : ''))}</span>
        ${cur.files.length ? fileButtons('/api/skill-lab/audio?slot=' + encodeURIComponent(r.slot), cur.files.length) : ''}</div>
      ${rows}
      <div class="sl-cand-b"><button type="button" data-unfit="${esc(r.slot)}" ${audio[r.slot] || using ? '' : 'disabled'}>지금 것으로 되돌리기</button>
        <button type="button" data-revert="${esc(r.slot)}" ${cur.kind === 'adopted' && ov.adopt.available ? '' : 'disabled'}>채택 취소</button></div></section>`;
  }

  function soundHtml() {
    const {main, other} = slotsFor();
    let h = '<h3>소리</h3>';
    if (!ov.slots.rows.length) h += `<p class="alert warn">${esc(ov.slots.note)}</p>`;
    else if (!main.length) h += '<p class="bl-help">이 스킬에 묶인 소리 자리가 표에 없습니다.</p>';
    h += main.map(slotHtml).join('');
    if (other.length) h += `<details><summary>소속을 정하지 못한 자리 ${other.length}개</summary>${other.map(slotHtml).join('')}</details>`;
    const known = new Set(ov.slots.rows.map(r => r.slot)), orphan = ov.candidates.filter(c => !known.has(c.slot));
    if (orphan.length) h += `<details ${ov.slots.rows.length ? '' : 'open'}><summary>소리 표에 자리가 없는 후보 ${orphan.length}개(듣기만 됩니다)</summary>${orphan.map(c => `<div class="sl-cand"><div class="sl-cand-t"><strong>${esc(c.key)}</strong> <span>${esc(c.label)}</span> <small>${esc(c.slot)}</small></div><div class="sl-cand-b">${fileButtons('/api/skill-lab/audio?id=' + encodeURIComponent(c.id), c.paths.length)}</div></div>`).join('')}</details>`;
    if (!ov.adopt.available) h += `<p class="bl-help">채택 단추를 껐습니다: ${esc(ov.adopt.reason)}</p>`;
    h += '<p class="bl-help"><b>이 페이지의 채택은 저장소 파일을 고친다. 커밋은 디렉터가 회귀 뒤에.</b></p>';
    h += `<div id="sl-analysis">${analysisHtml()}</div>`;
    if (result) h += resultHtml();
    return h;
  }

  function analysisHtml() {
    if (!analysis.length) return '<p class="bl-help">▶를 누르면 브라우저가 그 소리의 길이와 최대 dBFS·RMS를 잽니다.</p>';
    return `<h4>들어 본 소리의 잰 값(브라우저)</h4><div class="table-wrap"><table class="data-table"><thead><tr><th>소리</th><th>파형</th><th>길이</th><th>최대 dBFS</th><th>RMS dBFS</th></tr></thead><tbody>${analysis.slice(-10).reverse().map((a, i) =>
      `<tr><td>${esc(a.name)}</td><td><canvas width="140" height="28" data-wave="${analysis.length - 1 - i}"></canvas></td><td>${a.dur.toFixed(2)}초</td><td>${a.peak.toFixed(1)}</td><td>${a.rms.toFixed(1)}</td></tr>`).join('')}</tbody></table></div>`;
  }

  function resultHtml() {
    const r = result;
    return `<section class="sl-result"><h4>${esc(r.title)}</h4>${r.pick_warning ? `<p class="alert warn">${esc(r.pick_warning)}</p>` : ''}
      <p>창에 다시 읽기 명령: ${r.reload_sent ? '보냄' : '보내지 않음(창이 떠 있지 않음)'}</p>
      <details open><summary>채택 도구가 낸 결과</summary><pre>${esc(JSON.stringify(r.result, null, 2) || r.output_tail)}</pre></details>
      <details open><summary>git diff --stat</summary><pre>${esc(r.git_diff_stat || '(바뀐 추적 파일 없음)')}</pre></details></section>`;
  }

  function clipHtml() {
    const box = k => {
      const c = clips[k];
      let body = '<p class="bl-help">아직 없습니다.</p>';
      if (c) {
        if (c.state === 'done') body = `<video controls playsinline preload="metadata" src="${esc(c.video)}"></video><p class="bl-help">${esc(c.way_label)} · ${c.size ? (c.size / 1048576).toFixed(1) + ' MB' : ''} · 찍는 데 ${esc(c.seconds)}초${c.cached ? ' · 찍어 둔 것을 다시 씀' : ''}${c.stale ? ' · <b class="au-worse">낡음: ' + esc(c.stale_reason) + '</b>' : ''}</p>`;
        else if (c.state === 'error') body = `<p class="alert bad">영상을 찍지 못했습니다. ${esc(c.error)} <button type="button" data-clip-retry="${esc(c.id)}">다시 시도</button></p>`;
        else body = `<p class="alert info">${c.state === 'queued' ? '대기 중' : '찍는 중 ' + Math.round(c.elapsed_s || 0) + '초'}</p>`;
        if (c.audio_overrides && Object.keys(c.audio_overrides).length) body += `<p class="bl-help">끼운 소리: ${esc(Object.entries(c.audio_overrides).map(([s, f]) => s + ' ← ' + f[0].split('/').pop()).join(', '))}</p>`;
      }
      return `<div class="sl-clip"><h4>${k === 'A' ? '영상 A (지금 소리)' : '영상 B (고른 후보)'}</h4>${body}</div>`;
    };
    const list = clipList && clipList.clips.length ? `<details><summary>찍어 둔 영상 ${clipList.clips.length}개 (${(clipList.bytes / 1048576).toFixed(1)} MB / 상한 ${(clipList.limit_bytes / 1073741824).toFixed(0)} GB)</summary><div class="table-wrap"><table class="data-table"><thead><tr><th>장면</th><th>찍은 때</th><th></th></tr></thead><tbody>${clipList.clips.slice(0, 30).map(c =>
      `<tr><td>${esc(c.scene.character.split('.').pop())} ${esc(c.scene.form)} ${esc(c.scene.layout)}×${c.scene.count}${c.stale ? ' <span class="badge is-warn">낡음</span>' : ''}</td><td>${esc(c.made_at)}</td><td><button type="button" data-clip-show="A" data-id="${c.id}">A에</button><button type="button" data-clip-show="B" data-id="${c.id}">B에</button>${c.stale ? `<button type="button" data-clip-redo="${c.id}">다시 찍기</button>` : ''}</td></tr>`).join('')}</tbody></table></div></details>` : '';
    return `<h3>영상 <small>소리가 든 4초 영상(PC가 찍어 올립니다)</small></h3><div class="sl-bar"><button type="button" id="sl-clip-a" class="primary">지금 소리로 영상 찍기</button></div>
      <div class="sl-clips">${box('A')}${box('B')}</div>${list}`;
  }

  function render() {
    const p = $('#skill-lab');
    if (!ov) return;
    if (!ov.characters.length) { p.innerHTML = `<h2>스킬 시험실</h2><p class="empty">캐릭터·스킬 데이터를 읽지 못했습니다.</p>${warnHtml()}`; p.setAttribute('data-ready', '1'); return; }
    if (!sel.elem) sel.elem = ov.characters[0].elem;
    p.innerHTML = `<h2>스킬 시험실</h2><p class="alert info">캐릭터와 스킬을 고르고 적 배치를 바꾸면 시험 창(게임 코드 그대로)이 따라 바뀝니다. 소리 후보를 끼워 들어 보고, 마음에 들면 채택합니다. <b>이 페이지의 채택은 저장소 파일을 고친다. 커밋은 디렉터가 회귀 뒤에.</b></p>
      <div id="sl-msg" class="alert ${msgKind}" ${message ? '' : 'hidden'}>${esc(message)}</div>${warnHtml()}
      <div class="sl-grid"><div class="sl-col sl-left"><h3>캐릭터와 스킬</h3>${charCards()}</div>
      <div class="sl-col sl-mid"><div id="sl-status" class="sl-status">${statusHtml()}</div>${controlsHtml()}<div id="sl-shot-box"></div>${clipHtml()}<div class="sl-detail">${detailHtml()}</div></div>
      <div class="sl-col sl-right">${soundHtml()}</div></div>`;
    p.setAttribute('data-ready', '1');
    p.setAttribute('data-char', sel.elem); p.setAttribute('data-form', sel.form);
    p.setAttribute('data-candidates', ov.candidates.length); p.setAttribute('data-slots', ov.slots.rows.length);
    p.setAttribute('data-window', ov.window.status);
    drawWaves();
    showShot();
  }

  function warnHtml() { return ov.warnings.length ? `<details class="alert warn"><summary>읽지 못한 것 ${ov.warnings.length}건</summary><ul>${ov.warnings.map(w => `<li>${esc(w)}</li>`).join('')}</ul></details>` : ''; }

  // ---------------------------------------------------------------- 장면 보내기
  function queueSend() {
    if (!live()) return;
    clearTimeout(sendTimer);
    sendTimer = setTimeout(async () => {
      try { await post('scene', {scene: sceneBody(), audio}); say(''); } catch (e) { say('창에 보내지 못했습니다. ' + e.message, 'bad'); }
    }, 150);
  }

  function adoptFromWindow() {      // 창이 이미 떠 있으면 그 창의 장면을 화면에 맞춘다(처음 한 번)
    const w = ov.window, s = w.state;
    if (synced || w.status !== 'connected' || !s || !s.scene) return false;
    synced = true;
    const sc = s.scene, c = ov.characters.find(x => x.id === sc.character);
    if (!c) return false;
    sel = {elem: c.elem, form: FORMS[sc.form] ? sc.form : 'base'};
    Object.keys(DEFAULTS).forEach(k => { if (sc[k] !== undefined) opts[k] = sc[k]; });
    audio = Object.assign({}, w.override_ids || {});
    Object.keys(audio).forEach(k => { if (audio[k].startsWith('(')) delete audio[k]; });
    return true;
  }

  // ---------------------------------------------------------------- 소리 듣기와 재기
  function audioCtx() { return ctx || (ctx = new (window.AudioContext || window.webkitAudioContext)()); }
  async function play(url) {
    try {
      const ac = audioCtx();
      if (ac.state === 'suspended') await ac.resume();
      const r = await fetch(url);
      if (!r.ok) throw new Error('소리 파일을 받지 못했습니다(' + r.status + ')');
      const buf = await ac.decodeAudioData(await r.arrayBuffer());
      if (source) { try { source.stop(); } catch {} }
      source = ac.createBufferSource(); source.buffer = buf; source.connect(ac.destination); source.start();
      const name = decodeURIComponent((url.match(/(?:id|slot)=([^&]+)/) || [])[1] || '?') + ' #' + ((url.match(/n=(\d+)/) || [])[1] ?? '0');
      let peak = 0, sum = 0, n = 0;
      const wave = [];
      for (let ch = 0; ch < buf.numberOfChannels; ch++) {
        const d = buf.getChannelData(ch);
        for (let i = 0; i < d.length; i++) { const v = Math.abs(d[i]); if (v > peak) peak = v; sum += d[i] * d[i]; }
        n += d.length;
      }
      const d0 = buf.getChannelData(0), step = Math.max(1, Math.floor(d0.length / 140));
      for (let i = 0; i < 140; i++) { let m = 0; for (let j = i * step; j < Math.min(d0.length, (i + 1) * step); j++) m = Math.max(m, Math.abs(d0[j])); wave.push(m); }
      const db = v => v > 0 ? 20 * Math.log10(v) : -Infinity;
      analysis.push({name, dur: buf.duration, peak: db(peak), rms: db(Math.sqrt(sum / Math.max(1, n))), wave});
      const a = $('#sl-analysis'); if (a) { a.innerHTML = analysisHtml(); drawWaves(); }
    } catch (e) { say('들을 수 없습니다. ' + e.message, 'bad'); }
  }
  function drawWaves() {
    document.querySelectorAll('canvas[data-wave]').forEach(cv => {
      const a = analysis[+cv.dataset.wave]; if (!a) return;
      const g = cv.getContext('2d'); g.clearRect(0, 0, cv.width, cv.height); g.fillStyle = '#c9ad6a';
      a.wave.forEach((m, i) => { const h = Math.max(1, m * cv.height); g.fillRect(i, (cv.height - h) / 2, 1, h); });
    });
  }

  // ---------------------------------------------------------------- 영상
  async function askClip(slotKey, audioMap) {
    try {
      const j = await post('clip', {scene: sceneBody(), audio: audioMap, way: 'movie'});
      clips[slotKey] = j; render(); pollClips();
    } catch (e) { say('영상을 부탁하지 못했습니다. ' + e.message, 'bad'); }
  }
  function pollClips() {
    clearTimeout(clipTimer);
    const pending = ['A', 'B'].filter(k => clips[k] && ['queued', 'running'].includes(clips[k].state));
    if (!pending.length || !open) return;
    clipTimer = setTimeout(async () => {
      for (const k of pending) {
        try { clips[k] = Object.assign({}, await call('/api/skill-lab/clip/' + clips[k].id)); } catch (e) { clips[k] = Object.assign({}, clips[k], {state: 'error', error: e.message}); }
      }
      if (pending.some(k => clips[k].state === 'done')) { try { clipList = await call('/api/skill-lab/clips'); } catch {} }
      updateClipArea(); pollClips();
    }, 1000);
  }
  function updateClipArea() {
    const keep = document.querySelectorAll('.sl-clip video');
    if ([...keep].length && ['A', 'B'].every(k => !clips[k] || clips[k].state === 'done')) return;
    const mid = $('#skill-lab .sl-mid'); if (!mid) return;
    const y = mid.scrollTop; const old = mid.querySelector('.sl-clips'); if (!old) return;
    const holder = document.createElement('div'); holder.innerHTML = clipHtml();
    const fresh = holder.querySelector('.sl-clips'); old.replaceWith(fresh); mid.scrollTop = y;
  }

  function showShot() {
    const box = $('#sl-shot-box'); if (!box) return;
    const s = ov.window.state;
    const last = s && s.last_shot ? String(s.last_shot).split('/').pop().replace(/\.png$/, '') : '';
    if (last && last === shotName) box.innerHTML = `<figure class="sl-shot"><img alt="시험 창 화면 저장" src="/api/skill-lab/shot?name=${encodeURIComponent(last)}&t=${Date.now()}"><figcaption>${esc(s.last_shot)}</figcaption></figure>`;
  }

  // ---------------------------------------------------------------- 불러오기와 새로 고침
  async function load(force) {
    const d = await call('/api/skill-lab');
    const s = JSON.stringify([d.characters, d.slots, d.candidates, d.adopt, d.warnings]);
    const was = ov; ov = d;
    const justSynced = adoptFromWindow();
    if (!was || force || s !== sig || justSynced) { sig = s; render(); }
    else { const st = $('#sl-status'); if (st) st.innerHTML = statusHtml(); showShot(); refreshChips(); }
    $('#skill-lab').setAttribute('data-window', ov.window.status);
  }
  function refreshChips() { /* 창이 지금 쓰는 소리 표시만 바뀌므로 소리 칸을 다시 그린다(재생 중인 소리는 영향 없음) */
    const col = $('#skill-lab .sl-right'); if (!col || !ov) return;
    const using = JSON.stringify(ov.window.override_ids); if (col.dataset.using === using) return;
    col.dataset.using = using; col.innerHTML = soundHtml(); drawWaves();
  }
  function tick() { if (open) load(false).catch(() => {}); }

  async function show(on) {
    open = on;
    document.body.classList.toggle('skilllab-mode', on);
    $('#skill-lab').hidden = !on;
    $('#open-skill-lab').classList.toggle('active', on);
    clearInterval(timer);
    if (!on) return;
    document.dispatchEvent(new CustomEvent('view-open', {detail: 'skill-lab'}));
    document.querySelectorAll('[data-category],[data-all]').forEach(b => b.classList.remove('active'));
    const hp = new URLSearchParams((location.hash.split('?')[1] || ''));
    if (hp.get('c')) sel.elem = hp.get('c');
    if (hp.get('f') && FORMS[hp.get('f')]) sel.form = hp.get('f');
    if (!ov) $('#skill-lab').innerHTML = '<p class="empty">스킬 시험실을 읽는 중…</p>';
    try { await load(true); clipList = await call('/api/skill-lab/clips'); render(); } catch (e) { $('#skill-lab').innerHTML = `<p class="empty">스킬 시험실을 열지 못했습니다. ${esc(e.message)}</p>`; return; }
    timer = setInterval(tick, 1500);
  }

  // ---------------------------------------------------------------- 조작
  async function adoptFlow(slot, cid) {
    const c = ov.candidates.find(x => x.id === cid);
    const files = c.paths.flatMap((_, i) => [`chapter1/art/audio/slots/${slot}/${c.key}_${i + 1}.wav`, `chapter1/art/audio/slots/${slot}/${c.key}_${i + 1}.wav.import`]).concat(['chapter1/data/audio_map.json', 'chapter1/art/audio/AUDIO-LEDGER.json', 'tools/manager/local-picks.json']);
    const lightning = slot.includes('arc') && slot.endsWith('cast');
    const modal = document.createElement('div'); modal.className = 'sl-modal'; modal.setAttribute('role', 'dialog'); modal.setAttribute('aria-modal', 'true');
    modal.innerHTML = `<div class="sl-modal-box"><h3>채택 확인</h3><p><b>${esc(c.key)}</b>를 <b>${esc(slot)}</b> 자리에 채택합니다.</p>
      <p class="alert warn">이 페이지의 채택은 저장소 파일을 고친다. 커밋은 디렉터가 회귀 뒤에. 일반 게임에서 이 소리가 울리게 됩니다.${lightning ? ' 번개 시전은 지금 일반 실행에서 무음입니다(2026-11-18에 거슬린다고 꺼 둔 것). 채택하면 울립니다.' : ''}</p>
      <p>쓰일 파일(예상 — 실제 목록은 채택 도구가 정하고 끝난 뒤 보여 줍니다)</p><ul>${files.map(f => `<li><code>${esc(f)}</code></li>`).join('')}</ul>
      <div class="sl-bar"><button type="button" class="primary" id="sl-yes">채택</button><button type="button" id="sl-no">취소</button></div></div>`;
    document.body.append(modal);
    $('#sl-no').focus();
    return new Promise(res => {
      const done = v => { modal.remove(); res(v); };
      $('#sl-no').onclick = () => done(false); $('#sl-yes').onclick = () => done(true);
      modal.addEventListener('keydown', e => { if (e.key === 'Escape') done(false); });
    });
  }
  async function doAdopt(slot, cid) {
    if (!await adoptFlow(slot, cid)) return;
    say('채택하는 중…(임포트까지 몇 분 걸릴 수 있습니다)');
    try {
      const r = await post('adopt', {slot, candidate: cid, map_rev: ov.map_rev});
      result = Object.assign({title: '채택했습니다: ' + cid}, r); say('채택했습니다.', 'ok'); await load(true);
    } catch (e) { fail(e); }
  }
  async function doRevert(slot) {
    if (!confirm(slot + ' 자리의 채택을 취소합니다. 채택 도구가 더한 새 파일은 지우고 소리 표에서 이 자리를 뺍니다. 계속할까요?')) return;
    try { const r = await post('revert', {slot, map_rev: ov.map_rev}); result = Object.assign({title: '채택을 취소했습니다: ' + slot}, r); say('채택을 취소했습니다.', 'ok'); await load(true); }
    catch (e) { fail(e); }
  }
  async function fail(e) {
    if (e.status === 409) { say('다른 곳에서 소리 표(audio_map.json)가 먼저 바뀌었습니다. 새로 읽었으니 후보와 현재 상태를 다시 확인하고 한 번 더 누르세요.', 'warn'); await load(true); }
    else say('실패했습니다. ' + e.message + (e.data && e.data.output ? '\n' + e.data.output : ''), 'bad');
  }

  document.addEventListener('view-open', ev => { if (ev.detail !== 'skill-lab' && open) show(false); });
  window.addEventListener('hashchange', () => { if (/^#skill-lab/.test(location.hash) && !open) show(true); });
  document.addEventListener('click', async ev => {
    const t = ev.target;
    if (t.closest('#open-skill-lab')) return show(true);
    if (!open) return;
    if (t.closest('[data-category],[data-all]')) return show(false);
    let b;
    if ((b = t.closest('[data-elem]'))) { sel = {elem: b.dataset.elem, form: b.dataset.form}; render(); queueSend(); return; }
    if ((b = t.closest('[data-layout]'))) { opts.layout = b.dataset.layout; render(); queueSend(); return; }
    if ((b = t.closest('[data-speed]'))) { opts.speed = +b.dataset.speed; render(); queueSend(); return; }
    if ((b = t.closest('[data-play]'))) return play(b.dataset.play);
    if ((b = t.closest('[data-fit]'))) { audio[b.dataset.fit] = b.dataset.cand; render(); queueSend(); if (!live()) say('창이 떠 있지 않아 고른 후보는 "시험실 열기" 때 함께 적용됩니다.'); return; }
    if ((b = t.closest('[data-unfit]'))) { delete audio[b.dataset.unfit]; render(); queueSend(); return; }
    if ((b = t.closest('[data-adopt]'))) return doAdopt(b.dataset.slot, b.dataset.adopt);
    if ((b = t.closest('[data-revert]'))) return doRevert(b.dataset.revert);
    if ((b = t.closest('[data-clip-cand]'))) return askClip('B', {[b.dataset.slot]: b.dataset.clipCand});
    if (t.closest('#sl-clip-a')) return askClip('A', {});
    if ((b = t.closest('[data-clip-retry]'))) { try { clips.A = await post('clip', {retry: b.dataset.clipRetry}); render(); pollClips(); } catch (e) { say(e.message, 'bad'); } return; }
    if ((b = t.closest('[data-clip-show]'))) { try { clips[b.dataset.clipShow] = await call('/api/skill-lab/clip/' + b.dataset.id); render(); } catch (e) { say(e.message, 'bad'); } return; }
    if ((b = t.closest('[data-clip-redo]'))) {
      const old = clipList.clips.find(c => c.id === b.dataset.clipRedo); if (!old) return;
      try { clips.A = await post('clip', {scene: old.scene, audio: old.audio_overrides, way: old.way}); render(); pollClips(); } catch (e) { say(e.message, 'bad'); } return;
    }
    if (t.closest('#sl-open')) {
      say('시험 창을 여는 중…');
      try { const r = await post('open', {scene: sceneBody(), audio, hero_models: hero}); say(r.launched ? '창을 띄웠습니다. 5~15초 뒤 연결됩니다.' : '이미 떠 있는 창에 장면을 보냈습니다.', 'ok'); synced = true; await load(true); }
      catch (e) { say('창을 열지 못했습니다. ' + e.message, 'bad'); }
      return;
    }
    if (t.closest('#sl-close')) { try { await post('close'); say('닫기 명령을 보냈습니다.'); } catch (e) { say(e.message, 'bad'); } return; }
    if (t.closest('#sl-cast')) { try { await post('cast'); } catch (e) { say(e.message, 'bad'); } return; }
    if (t.closest('#sl-shot')) {
      shotName = 'page-' + Date.now();
      try { await post('shot', {name: shotName}); say('화면 저장을 부탁했습니다. 창이 저장하면 아래에 나옵니다.'); } catch (e) { say(e.message, 'bad'); }
    }
  });
  document.addEventListener('input', ev => {
    const t = ev.target;
    if (!open || !t.closest('#skill-lab')) return;
    if (t.id === 'sl-count') { opts.count = +t.value; $('#sl-count-n').textContent = t.value; queueSend(); }
    else if (t.name === 'sl-motion') { opts.motion = t.value; queueSend(); }
    else if (t.id === 'sl-durable') { opts.durable = t.checked; queueSend(); }
    else if (t.id === 'sl-juice') { opts.juice = t.checked; queueSend(); }
    else if (t.id === 'sl-repeat') { opts.repeat = t.checked; queueSend(); }
    else if (t.id === 'sl-interval') { opts.interval_s = +t.value; queueSend(); }
    else if (t.id === 'sl-hero') { hero = t.checked; }
  });
  if (/^#skill-lab/.test(location.hash)) (document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', () => show(true)) : show(true));
})();
