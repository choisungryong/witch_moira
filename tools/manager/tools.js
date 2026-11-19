'use strict';
// 도구 색인. 읽기 전용: 파일 머리 주석에서 뽑은 설명과 명령을 역할별로 보여 준다. 도구를 실행하지 않는다.
(function () {
  const $ = s => document.querySelector(s);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
  let data = null, open = false, query = '';

  async function load() {
    const r = await fetch('/api/tools');
    let d;
    try { d = await r.json(); } catch { throw new Error('서버 응답을 읽을 수 없습니다.'); }
    if (!r.ok) throw new Error(d.error || '요청 실패 (' + r.status + ')');
    data = d;
  }

  function toolHtml(t) {
    const ex = (t.examples || []).map(e => `<pre>${esc(e)}</pre>`).join('');
    return `<div class="tl-tool"><b>${esc(t.path)}</b>${t.missing ? ' <span class="tl-miss">색인에는 있는데 파일이 없음</span>' : ''}${t.use ? `<p>${esc(t.use)}</p>` : ''}${t.header ? `<p class="tl-hd">머리 주석: ${esc(t.header)}</p>` : ''}${ex}</div>`;
  }
  const matches = (t, q) => !q || (t.path + ' ' + (t.use || '') + ' ' + (t.header || '')).toLocaleLowerCase().includes(q);

  function render() {
    const p = $('#tools');
    if (!data) return;
    const q = query.toLocaleLowerCase();
    const roles = data.roles.map(r => ({...r, shown: r.tools.filter(t => matches(t, q))})).filter(r => r.shown.length || (!q && !r.tools.length));
    const unm = data.unmapped.filter(t => matches(t, q));
    p.innerHTML = `<h2>도구</h2><p class="alert info">${esc(data.caveat)}</p>
${(data.warnings || []).map(w => `<p class="alert warn">${esc(w)}</p>`).join('')}
${data.reminders.length ? `<section class="tl-remind"><h3>이미 있는데 놓치기 쉬운 것</h3><ul>${data.reminders.map(r => `<li>${esc(r.text)}${r.path ? ` <code>${esc(r.path)}</code>` : ''}</li>`).join('')}</ul></section>` : ''}
<div class="tl-bar"><label>도구 찾기<input id="tl-q" type="search" value="${esc(query)}" placeholder="이름, 하는 일, 명령 일부" autocomplete="off"></label><span class="bl-help">도구 ${data.tool_count}개 · ${esc(data.generated_at)}에 읽음 · 문서로 내보내기: <code>python tools/manager/catalog.py --tools-index</code></span></div>
${roles.map(r => `<details class="tl-role" ${q || r.id === 'everyone' ? 'open' : ''}><summary>${esc(r.label)}<small>${r.shown.length}개</small></summary>${r.about ? `<p class="bl-help">${esc(r.about)}</p>` : ''}${r.shown.map(toolHtml).join('')}</details>`).join('')}
${unm.length ? `<details class="tl-role" ${q ? 'open' : ''}><summary>아직 역할에 묶지 않은 도구<small>${unm.length}개</small></summary><p class="bl-help">tools/manager/tools_index.json 에 더하면 역할별 목록에 나옵니다.</p>${unm.map(toolHtml).join('')}</details>` : ''}
<p class="bl-help">${esc(data.unit_tests_note)}</p>`;
    const inp = $('#tl-q');
    if (inp && query) { inp.focus(); inp.setSelectionRange(query.length, query.length); }
  }

  async function show(on) {
    open = on;
    document.body.classList.toggle('tools-mode', on);
    $('#tools').hidden = !on;
    $('#open-tools').classList.toggle('active', on);
    if (!on) return;
    document.dispatchEvent(new CustomEvent('view-open', {detail: 'tools'}));
    document.querySelectorAll('[data-category],[data-all]').forEach(b => b.classList.remove('active'));
    if (!data) {
      $('#tools').innerHTML = '<p class="empty">도구 목록을 읽는 중…</p>';
      try { await load(); } catch (e) { $('#tools').innerHTML = `<p class="empty">도구 색인을 열지 못했습니다. ${esc(e.message)}</p>`; return; }
    }
    render();
  }

  document.addEventListener('view-open', ev => { if (ev.detail !== 'tools' && open) show(false); });
  document.addEventListener('click', ev => {
    const t = ev.target;
    if (t.closest('#open-tools')) return show(true);
    if (open && t.closest('[data-category],[data-all]')) show(false);
  });
  document.addEventListener('input', ev => {
    if (open && ev.target.id === 'tl-q') { query = ev.target.value; render(); }
  });
})();
