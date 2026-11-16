'use strict';
// 원화 시안 갤러리. 그림과 색인은 읽기만 하고, 판정과 메모는 이 도구의 로컬 상태에만 저장한다.
(function () {
  const $ = s => document.querySelector(s);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
  const verdicts = {like: '마음에 듦', hold: '보류', drop: '탈락'};
  const filters = {all: '전체', adopted: '채택·확정만', pending: '검토 대기만'};
  const ADOPT = ['방향 채택', '확정'];
  let data = null, state = {revision: 0, records: {}}, filter = 'all', open = false;
  let modal = null, list = [], idx = 0, pinned = null, signature = '', timer = 0;
  const enc = id => encodeURIComponent(id);
  const thumb = e => '/drafts/thumb/' + enc(e.id);
  const full = e => '/drafts/full/' + enc(e.id);
  const mine = id => ({verdict: '', notes: '', ...(state.records[id] || {})});
  const kind = e => e.group === '확정 원화' ? 'canon' : ADOPT.includes(e.status) ? 'adopt' : e.status === '탈락' ? 'drop' : '';

  async function req(url, options) {
    const r = await fetch(url, options);
    let d;
    try { d = await r.json(); } catch { throw new Error('서버 응답을 읽을 수 없습니다.'); }
    if (!r.ok) { const err = new Error(d.error || '요청 실패 (' + r.status + ')'); err.status = r.status; throw err; }
    return d;
  }

  async function load() {
    try {
      data = await req('/api/drafts');
      state = data.decisions;
      const sig = JSON.stringify([data.items.map(i => i.id + i.status + i.note), data.canonical.length, state.revision]);
      const changed = sig !== signature;
      signature = sig;
      $('#gallery-count').textContent = data.items.length + data.canonical.length;
      if (open && changed && !modal) render();
    } catch (e) {
      if ($('#gallery')) $('#gallery').innerHTML = '<p class="g-empty">시안을 불러오지 못했습니다. ' + esc(e.message) + '</p>';
    }
  }

  const visible = e => filter === 'all' || (filter === 'adopted' ? ADOPT.includes(e.status) : e.status === '검토 대기');

  function card(e) {
    const m = mine(e.id), k = kind(e);
    return `<button type="button" class="g-card ${k}" data-draft="${esc(e.id)}" title="${esc(e.title)}"><img class="pic" loading="lazy" src="${esc(thumb(e))}" alt="${esc(e.title)}"><span class="g-tag">${esc(e.status)}</span>${m.verdict ? `<span class="g-mine ${m.verdict}">내 판정 ${verdicts[m.verdict]}</span>` : ''}<span class="cap"><b>${esc(e.title)}</b><span>${esc(e.created)}${m.notes ? ' · 메모 있음' : ''}</span></span></button>`;
  }

  function render() {
    const g = $('#gallery');
    if (!data) return;
    const items = data.items.filter(visible);
    let html = `<div class="g-bar"><h2>원화 시안</h2><div class="g-seg" role="group" aria-label="상태별 보기">${Object.entries(filters).map(([k, v]) => `<button type="button" data-gfilter="${k}" class="${filter === k ? 'on' : ''}">${v}</button>`).join('')}</div><button type="button" id="g-reload" class="quiet">시안 다시 읽기</button><span>${items.length} / ${data.items.length}장${data.thumbnails ? '' : ' · 작은 그림을 만들 수 없어 원본을 그대로 씁니다(Pillow 없음)'}</span></div>`;
    html += (data.warnings || []).map(w => `<p class="g-warn">${esc(w)}</p>`).join('');
    if (data.canonical.length) html += `<h3 class="g-group">확정 원화 · 비교 기준</h3><div class="g-grid">${data.canonical.map(card).join('')}</div>`;
    const groups = [];
    data.characters.forEach(c => { if (!groups.includes(c.group)) groups.push(c.group); });
    groups.forEach(gr => {
      const chars = data.characters.filter(c => c.group === gr);
      const body = chars.map(c => {
        const mineItems = items.filter(e => e.character === c.character);
        if (!mineItems.length) return '';
        return `<h4 class="g-char">${esc(c.name)}<small>${mineItems.length}장</small></h4><div class="g-grid">${mineItems.map(card).join('')}</div>`;
      }).join('');
      if (body) html += `<h3 class="g-group">${esc(gr)}</h3>` + body;
    });
    if (!data.items.length) html += '<p class="g-empty">아직 시안이 없습니다. 색인(_local/art/drafts/index.json)에 항목이 생기면 여기에 나타납니다.</p>';
    else if (!items.length) html += '<p class="g-empty">이 조건에 맞는 시안이 없습니다. 위에서 「전체」를 골라 보세요.</p>';
    const top = g.scrollTop;
    g.innerHTML = html;
    g.scrollTop = top;
  }

  function show(on) {
    open = on;
    document.body.classList.toggle('gallery-mode', on);
    $('#gallery').hidden = !on;
    $('#open-gallery').classList.toggle('active', on);
    if (on) {
      document.querySelectorAll('[data-category],[data-all]').forEach(b => b.classList.remove('active'));
      load().then(render);
      clearInterval(timer);
      timer = setInterval(() => { if (open && !modal) load(); }, 20000);
    } else clearInterval(timer);
  }

  function openModal(id) {
    list = [...data.canonical, ...data.items.filter(visible)];
    idx = Math.max(0, list.findIndex(e => e.id === id));
    pinned = null;
    modal = document.createElement('div');
    modal.className = 'g-modal';
    modal.setAttribute('role', 'dialog');
    modal.setAttribute('aria-label', '시안 크게 보기');
    document.body.append(modal);
    drawModal();
  }

  function closeModal() { if (modal) { modal.remove(); modal = null; render(); } }

  function drawModal() {
    const e = list[idx], m = mine(e.id), p = pinned && list.find(x => x.id === pinned) || (pinned ? data.items.find(x => x.id === pinned) : null);
    const fig = (x, label) => `<figure><img src="${esc(full(x))}" alt="${esc(x.title)}"><figcaption>${label ? label + ' · ' : ''}${esc(x.title)} · ${esc(x.status)}</figcaption></figure>`;
    modal.innerHTML = `<div class="g-top"><button type="button" data-g="prev">← 이전</button><button type="button" data-g="next">다음 →</button><span>${idx + 1} / ${list.length}</span><span class="sp"></span><button type="button" data-g="pin" class="${p ? 'on' : ''}">${p ? '비교 해제' : '이 시안과 나란히 비교'}</button><button type="button" data-g="close">닫기 (Esc)</button></div>
<div class="g-body"><div class="g-stage">${p && p.id !== e.id ? fig(p, '고정') : ''}${fig(e, p && p.id !== e.id ? '지금' : '')}</div>
<aside class="g-side"><h3>${esc(e.title)}</h3><dl><dt>상태</dt><dd>${esc(e.status)}</dd><dt>구분</dt><dd>${esc(e.group)}</dd>${e.tool ? `<dt>도구</dt><dd>${esc(e.tool)}</dd>` : ''}${e.model ? `<dt>모델</dt><dd>${esc(e.model)}</dd>` : ''}${e.created ? `<dt>만든 때</dt><dd>${esc(e.created)}</dd>` : ''}<dt>메모(색인)</dt><dd>${esc(e.note) || '—'}</dd></dl>
${e.has_prompt ? '<details id="g-prompt"><summary>프롬프트 전문</summary><pre>불러오는 중…</pre></details>' : ''}
<h3 style="font-size:15px;margin-top:14px">내 판정과 메모</h3>
<div class="row" role="group" aria-label="내 판정">${Object.entries(verdicts).map(([k, v]) => `<button type="button" data-verdict="${k}" class="${m.verdict === k ? 'on' : ''}">${v}</button>`).join('')}<button type="button" data-verdict="">해제</button></div>
<textarea id="g-notes" maxlength="10000" placeholder="이 시안에 대한 생각을 적어 두세요.">${esc(m.notes)}</textarea>
<div class="row"><button type="button" data-g="savenote">메모 저장</button><span id="g-feedback" role="status" aria-live="polite"></span></div>
<p style="color:#9aa496;font-size:12px">판정과 메모는 이 도구의 로컬 기록에만 저장됩니다. 색인과 그림은 바뀌지 않습니다.</p></aside></div>`;
    const d = $('#g-prompt');
    if (d) d.addEventListener('toggle', async () => {
      if (!d.open || d.dataset.loaded) return;
      d.dataset.loaded = '1';
      try {
        const r = await fetch('/drafts/prompt/' + enc(e.id));
        d.querySelector('pre').textContent = r.ok ? await r.text() : '프롬프트를 읽지 못했습니다.';
      } catch { d.querySelector('pre').textContent = '프롬프트를 읽지 못했습니다.'; }
    });
  }

  async function saveMine(changes) {
    const e = list[idx], fb = $('#g-feedback');
    if (fb) fb.textContent = '저장 중…';
    try {
      state = await req('/api/drafts/state', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({revision: state.revision, id: e.id, changes})});
      signature = '';
      drawKeep();
      $('#g-feedback').textContent = '저장했습니다.';
    } catch (err) {
      if (err.status === 409) {
        state = await req('/api/drafts/state');
        if (fb) fb.textContent = '다른 곳에서 먼저 저장되었습니다. 다시 눌러 저장하세요.';
      } else if (fb) fb.textContent = '저장하지 못했습니다. ' + err.message;
    }
  }

  function drawKeep() { const t = $('#g-notes') ? $('#g-notes').value : null; drawModal(); if (t !== null) $('#g-notes').value = t; }

  function go(n) { idx = (idx + n + list.length) % list.length; drawModal(); }

  document.addEventListener('click', ev => {
    const t = ev.target;
    if (t.closest('#open-gallery')) return show(true);
    if (open && t.closest('[data-category],[data-all]')) show(false);
    if (modal && modal.contains(t)) {
      const g = t.closest('[data-g]'), v = t.closest('[data-verdict]');
      if (v) saveMine({verdict: v.dataset.verdict});
      else if (g) {
        const a = g.dataset.g;
        if (a === 'close') closeModal();
        else if (a === 'prev') go(-1);
        else if (a === 'next') go(1);
        else if (a === 'pin') { pinned = pinned ? null : list[idx].id; drawKeep(); }
        else if (a === 'savenote') saveMine({notes: $('#g-notes').value});
      }
      return;
    }
    if (!open) return;
    const card = t.closest('[data-draft]'), f = t.closest('[data-gfilter]');
    if (card) openModal(card.dataset.draft);
    else if (f) { filter = f.dataset.gfilter; render(); }
    else if (t.closest('#g-reload')) load().then(render);
  });

  document.addEventListener('keydown', ev => {
    if (!modal) return;
    if (ev.key === 'Escape') closeModal();
    else if (/^(TEXTAREA|INPUT)$/.test(ev.target.tagName)) return;
    else if (ev.key === 'ArrowLeft') go(-1);
    else if (ev.key === 'ArrowRight') go(1);
  });

  load();
})();
