'use strict';
// 플레이 기록. 사람이 한 판을 하고 바로 적는 양식과 지난 기록. 게임 저장 폴더는 읽지도 쓰지도 않는다.
(function () {
  const $ = s => document.querySelector(s);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
  const DRAFT = 'moira-playlog-draft-v1';
  let data = null, open = false, tab = 'new', form = null, saving = false;

  async function req(url, options) {
    const r = await fetch(url, options);
    let d;
    try { d = await r.json(); } catch { throw new Error('서버 응답을 읽을 수 없습니다.'); }
    if (!r.ok) throw new Error(d.error || '요청 실패 (' + r.status + ')');
    return d;
  }

  const pad = n => String(n).padStart(2, '0');
  function nowLocal() { const d = new Date(); return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + 'T' + pad(d.getHours()) + ':' + pad(d.getMinutes()); }
  const blank = () => ({played_at: nowLocal(), witch: '', result: '', minutes: '', sound: '', resolution: '', memo: '', answers: {}});

  function loadDraft() {
    try { const v = JSON.parse(localStorage.getItem(DRAFT) || 'null'); if (v && typeof v === 'object' && v.answers) return v; } catch { /* 깨진 임시 저장은 버린다 */ }
    return null;
  }
  const saveDraft = () => { try { localStorage.setItem(DRAFT, JSON.stringify(form)); } catch { /* 저장 공간이 없으면 임시 저장만 건너뛴다 */ } };

  async function load() {
    $('#playlog').innerHTML = '<p class="empty">불러오는 중…</p>';
    try {
      data = await req('/api/playtests');
      if (!form) form = loadDraft() || blank();
      $('#playlog-count').textContent = data.records.length;
    } catch (e) {
      $('#playlog').innerHTML = '<p class="empty">플레이 기록을 불러오지 못했습니다. ' + esc(e.message) + '</p>';
      data = null;
    }
  }

  const buildText = b => !b || !b.commit ? '읽지 못함(git을 쓸 수 없음)' : '커밋 ' + b.commit + (b.dirty === null ? '' : b.dirty ? ' · 작업 트리에 바꾼 파일 ' + b.changed_files + '개' : ' · 작업 트리 변경 없음');
  const opt = (table, cur) => Object.entries(table).map(([k, v]) => `<option value="${esc(k)}" ${cur === k ? 'selected' : ''}>${esc(v)}</option>`).join('');

  function question(q) {
    const a = form.answers[q.id] || {score: 0, note: ''};
    const scale = [1, 2, 3, 4, 5].map(n => `<label class="pl-pt ${a.score === n ? 'on' : ''}" title="${esc(data.scale[n])}"><input type="radio" name="s-${esc(q.id)}" value="${n}" data-q="${esc(q.id)}" ${a.score === n ? 'checked' : ''}><span>${n}</span></label>`).join('');
    return `<div class="pl-q"><p class="pl-qt">${esc(q.text)}</p>${q.hint ? `<p class="pl-hint">${esc(q.hint)}</p>` : ''}<div class="pl-scale" role="radiogroup" aria-label="${esc(q.text)}">${scale}<button type="button" class="pl-clear" data-clear="${esc(q.id)}">지우기</button></div><input class="pl-note" type="text" maxlength="400" data-note="${esc(q.id)}" value="${esc(a.note)}" placeholder="한 줄 메모(선택)"></div>`;
  }

  function formView() {
    const o = data.options;
    const head = `<div class="pl-head">
<label>플레이한 날짜·시각<input type="datetime-local" data-f="played_at" value="${esc(form.played_at)}"></label>
<label>마녀<select data-f="witch">${opt(o.witch, form.witch)}</select></label>
<label>판 결과<select data-f="result">${opt(o.result, form.result)}</select></label>
<label>판 길이(분)<input type="number" inputmode="numeric" min="0" max="600" data-f="minutes" value="${esc(form.minutes)}" placeholder="예: 12"></label>
<label>소리<select data-f="sound">${opt(o.sound, form.sound)}</select></label>
<label>해상도<input type="text" maxlength="20" data-f="resolution" value="${esc(form.resolution)}" placeholder="예: 1920x1080"></label>
<div class="pl-build"><span>빌드(저장할 때 git으로 읽음)</span><b>${esc(buildText(data.build))}</b></div></div>`;
    const groups = data.questions.map(g => `<fieldset class="pl-group"><legend>${esc(g.name)}</legend><p class="pl-src">${g.from_doc ? '문서에서 읽음 · ' : '문서에서 읽지 못해 기본 질문 · '}${esc(g.source)}</p>${g.items.map(question).join('')}</fieldset>`).join('');
    const legend = Object.entries(data.scale).map(([k, v]) => k + ' ' + v).join(' · ');
    return `<form id="pl-form" novalidate><p class="pl-help">한 판을 끝낸 뒤 바로 적으세요. 점수는 질문에 대한 느낌입니다(${esc(legend)}). 모르겠으면 비워 두세요. 판 결과는 직접 고릅니다. 게임 저장 폴더는 읽지 않습니다.</p>${head}${groups}
<label class="pl-memo">자유 메모<textarea data-f="memo" maxlength="10000" placeholder="그 밖에 느낀 것, 막힌 곳, 버그">${esc(form.memo)}</textarea></label>
<div class="pl-actions"><button type="submit" class="primary">기록 저장</button><button type="button" id="pl-reset" class="danger">양식 비우기</button><span id="pl-feedback" role="status" aria-live="polite"></span></div></form>`;
  }

  const stars = n => n ? n + '점' : '미응답';
  function listView() {
    if (!data.records.length) return '<p class="empty">아직 저장된 기록이 없습니다. 「새 기록」에서 한 판을 적어 보세요.</p>';
    return data.records.map(r => {
      const b = r.build || {}, ans = Object.values(r.answers || {});
      const head = [data.options.witch[r.witch] || '', data.options.result[r.result] || '', r.minutes != null ? r.minutes + '분' : '', r.sound ? '소리 ' + (data.options.sound[r.sound] || '') : '', r.resolution].filter(Boolean).join(' · ');
      return `<details class="pl-rec"><summary><b>${esc(r.played_at)}</b> ${esc(head)} <small>${ans.filter(a => a.score).length}개 답</small></summary>
<p class="pl-src">${esc(b.commit ? '커밋 ' + b.commit + (b.dirty ? ' (변경 있음)' : '') : '커밋 기록 없음')} · 저장 ${esc(r.saved_at || '')} · ${esc(r.id)}.json</p>
<ul class="pl-ans">${ans.map(a => `<li><span class="pl-score s${a.score}">${stars(a.score)}</span> <span>${esc(a.group_name)} · ${esc(a.text)}</span>${a.note ? `<em>${esc(a.note)}</em>` : ''}</li>`).join('') || '<li>답한 질문 없음</li>'}</ul>
${r.memo ? `<p class="pl-memo-text">${esc(r.memo)}</p>` : ''}</details>`;
    }).join('');
  }

  function trendView() {
    if (!data.trend.length) return '<p class="empty">점수를 매긴 기록이 생기면 질문별 변화가 여기에 나옵니다.</p>';
    const rows = data.trend.map(t => {
      const s = t.points.map(p => p.score), last = s[s.length - 1], prev = s.length > 1 ? s[s.length - 2] : null;
      const arrow = prev === null ? '' : last > prev ? ' <span class="up">▲</span>' : last < prev ? ' <span class="down">▼</span>' : ' <span>＝</span>';
      return `<tr><td>${esc(t.group_name)}</td><td>${esc(t.text)}</td><td class="pl-nums" title="${esc(t.points.map(p => p.played_at + ' ' + p.score + '점').join('\n'))}">${s.map(v => `<span class="pl-score s${v}">${v}</span>`).join('<i>→</i>')}${arrow}</td><td>${s.length}회</td></tr>`;
    }).join('');
    return `<p class="pl-help">오래된 기록부터 순서대로 나열한 점수입니다. 질문 문장이 문서에서 바뀌면 다른 질문으로 따로 셉니다. 점수는 내 느낌이며 이 툴이 잰 값이 아닙니다.</p><div class="table-wrap"><table class="data-table"><thead><tr><th>구분</th><th>질문</th><th>점수 변화</th><th>횟수</th></tr></thead><tbody>${rows}</tbody></table></div>`;
  }

  function render() {
    const p = $('#playlog');
    if (!data) return;
    const tabs = [['new', '새 기록'], ['list', '지난 기록 (' + data.records.length + ')'], ['trend', '점수 변화']];
    const warn = (data.warnings || []).map(w => `<p class="alert warn">${esc(w)}</p>`).join('');
    const body = tab === 'new' ? formView() : tab === 'list' ? listView() : trendView();
    const top = p.scrollTop;
    p.innerHTML = `<div class="g-bar"><h2>플레이 기록</h2><div class="g-seg" role="group" aria-label="보기">${tabs.map(([k, v]) => `<button type="button" data-ptab="${k}" class="${tab === k ? 'on' : ''}">${esc(v)}</button>`).join('')}</div></div>${warn}${body}`;
    p.scrollTop = top;
  }

  function show(on) {
    open = on;
    document.body.classList.toggle('playlog-mode', on);
    $('#playlog').hidden = !on;
    $('#open-playlog').classList.toggle('active', on);
    if (on) {
      document.dispatchEvent(new CustomEvent('view-open', {detail: 'playlog'}));
      document.querySelectorAll('[data-category],[data-all]').forEach(b => b.classList.remove('active'));
      load().then(render);
    }
  }

  function payload() {
    const answers = {};
    Object.entries(form.answers).forEach(([k, a]) => { if (a.score || a.note) answers[k] = {score: a.score || 0, note: a.note || ''}; });
    const min = String(form.minutes).trim();
    return {played_at: form.played_at.replace('T', ' '), witch: form.witch, result: form.result, minutes: min === '' ? null : Number(min),
      sound: form.sound, resolution: form.resolution, answers, memo: form.memo};
  }

  async function submit() {
    if (saving) return;
    const fb = $('#pl-feedback'), btn = $('#pl-form button[type=submit]');
    if (!form.played_at) { fb.textContent = '날짜·시각을 넣어 주세요.'; return; }
    if (form.minutes !== '' && !/^\d{1,3}$/.test(String(form.minutes).trim())) { fb.textContent = '판 길이는 0~600 사이 숫자(분)로 적어 주세요.'; return; }
    saving = true; btn.disabled = true; fb.textContent = '저장 중…';
    try {
      const r = await req('/api/playtests', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(payload())});
      try { localStorage.removeItem(DRAFT); } catch { /* 무시 */ }
      form = blank();
      await load();
      tab = 'list';
      render();
      const f = $('#playlog .pl-rec'); if (f) f.open = true;
      $('#playlog').insertAdjacentHTML('afterbegin', '<p class="pl-saved" role="status">저장했습니다: _local/playtests/' + esc(r.id) + '.json</p>');
    } catch (e) {
      fb.textContent = '저장하지 못했습니다. ' + e.message + ' 입력한 내용은 그대로 두었습니다.';
    } finally { saving = false; if (btn) btn.disabled = false; }
  }

  document.addEventListener('view-open', ev => { if (ev.detail !== 'playlog' && open) show(false); });
  document.addEventListener('click', ev => {
    const t = ev.target;
    if (t.closest('#open-playlog')) return show(true);
    if (open && t.closest('[data-category],[data-all]')) show(false);
    if (!open || !$('#playlog').contains(t)) return;
    const tb = t.closest('[data-ptab]'), clr = t.closest('[data-clear]');
    if (tb) { tab = tb.dataset.ptab; render(); }
    else if (clr) { delete form.answers[clr.dataset.clear]; saveDraft(); render(); }
    else if (t.closest('#pl-reset') && confirm('입력한 내용을 모두 비울까요?')) { form = blank(); saveDraft(); render(); }
  });
  document.addEventListener('input', ev => {
    const t = ev.target;
    if (!open || !form || !$('#playlog').contains(t)) return;
    if (t.dataset.f) form[t.dataset.f] = t.value;
    else if (t.dataset.note) { const a = form.answers[t.dataset.note] || (form.answers[t.dataset.note] = {score: 0, note: ''}); a.note = t.value; }
    else if (t.dataset.q) {
      const a = form.answers[t.dataset.q] || (form.answers[t.dataset.q] = {score: 0, note: ''});
      a.score = Number(t.value);
      t.closest('.pl-scale').querySelectorAll('.pl-pt').forEach(l => l.classList.toggle('on', l.querySelector('input').checked));
    } else return;
    saveDraft();
  });
  document.addEventListener('submit', ev => { if (ev.target.id === 'pl-form') { ev.preventDefault(); submit(); } });
  if (location.hash === '#playlog') show(true);
  fetch('/api/playtests').then(r => r.json()).then(d => { $('#playlog-count').textContent = d.records.length; }).catch(() => {});
})();
