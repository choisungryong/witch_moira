'use strict';
// 점검 화면. 읽기 전용: 가장 최근 점검(tools/dev/audit.py) 결과를 표로 보여 주고, 다시 돌리기만 서버에 부탁한다.
// 숫자는 점검 도구가 센 것이다. 이 화면은 세지 않고 품질을 판정하지 않는다.
(function () {
  const $ = s => document.querySelector(s);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
  let data = null, open = false, running = false, message = '';

  async function call(url, options) {
    const r = await fetch(url, options);
    let d;
    try { d = await r.json(); } catch { throw new Error('서버 응답을 읽을 수 없습니다.'); }
    if (!r.ok) throw new Error(d.error || '요청 실패 (' + r.status + ')');
    return d;
  }

  function delta(m) {
    if (m.delta === null || m.delta === undefined) return '<span class="au-first">처음</span>';
    if (m.delta === 0) return '<span class="au-same">＝</span>';
    const arrow = m.delta > 0 ? '▲ +' + m.delta : '▼ ' + m.delta;
    return `<span class="${m.worse ? 'au-worse' : 'au-better'}">${arrow}${m.worse ? ' 나빠짐' : ''}</span>`;
  }

  function lineHtml(l) {
    if (l.status === 'unseen') {
      return `<section class="au-line au-unseen"><h3>${esc(l.title)} <small>${esc(l.id)}</small></h3><p><b>못 봄</b> — ${esc(l.reason || '')}${l.worse ? ' <span class="au-worse">지난번에는 볼 수 있었음(나빠짐으로 셈)</span>' : ''}</p></section>`;
    }
    const rows = l.metrics.map(m => `<tr><td>${esc(m.label)}</td><td class="au-num">${esc(m.value)}</td><td class="au-num">${m.previous === null || m.previous === undefined ? '-' : esc(m.previous)}</td><td>${delta(m)}</td></tr>`).join('');
    const detail = (l.detail || []).length ? `<details><summary>자세히 ${l.detail.length}줄</summary><ul>${l.detail.slice(0, 80).map(t => `<li>${esc(t)}</li>`).join('')}</ul></details>` : '';
    return `<section class="au-line ${l.worse ? 'au-line-worse' : ''}"><h3>${esc(l.title)} <small>${esc(l.id)}${l.previous_run ? ' · 지난번 ' + esc(l.previous_run) : ''}</small></h3>
<table class="data-table"><thead><tr><th>항목</th><th>지금</th><th>지난번</th><th>차이</th></tr></thead><tbody>${rows}</tbody></table>${detail}</section>`;
  }

  function render() {
    const p = $('#audit');
    if (!data) return;
    const res = data.result;
    const head = `<h2>점검</h2><p class="tl-note">${esc(res ? res.notice : '이 점검은 기록의 유무와 일치만 본다. 품질·재미·저작권의 실제 여부는 보지 않는다.')}</p>`;
    const bar = `<div class="au-bar"><button id="au-run" class="primary" type="button" ${running || data.running ? 'disabled' : ''}>${running || data.running ? '점검하는 중…(1분쯤 걸립니다)' : '다시 돌리기'}</button><span class="bl-help">${esc(message)}</span></div>`;
    if (!res) {
      p.innerHTML = head + bar + '<p class="g-empty">아직 점검 기록이 없습니다. 「다시 돌리기」를 누르면 첫 기록(기준선)을 만듭니다. 명령: <code>python tools/dev/audit.py</code></p>';
      return;
    }
    const worse = res.worse || [];
    const summary = `<p class="au-sum ${worse.length ? 'au-worse' : ''}">${worse.length ? '지난번보다 나빠진 줄: ' + worse.map(esc).join(', ') : '지난번보다 나빠진 줄 없음'} · 만든 때 ${esc(res.made_at)} · 기록 폴더 ${esc(data.folder)}</p>`;
    p.innerHTML = head + bar + summary + res.lines.map(lineHtml).join('') +
      '<p class="bl-help">이 화면은 읽기만 합니다. 다시 돌리기는 점검 도구(audit.py)를 서버가 한 번에 하나씩 실행해 _local/audit/ 에 새 기록을 남기며, 게임 데이터와 메모는 건드리지 않습니다. 점검이 일부 줄만 돌린 기록이면 나머지 줄의 「지난번」은 그 줄을 마지막으로 돌린 기록입니다.</p>';
  }

  async function load() { data = await call('/api/audit'); running = !!data.running; }

  async function rerun() {
    if (running) return;
    running = true; message = ''; render();
    try {
      data = await call('/api/audit/run', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: '{}'});
      message = '새 기록을 만들었습니다.';
    } catch (e) { message = '다시 돌리지 못했습니다. ' + e.message; try { await load(); } catch {} }
    running = false; render();
  }

  async function show(on) {
    open = on;
    document.body.classList.toggle('audit-mode', on);
    $('#audit').hidden = !on;
    $('#open-audit').classList.toggle('active', on);
    if (!on) return;
    document.dispatchEvent(new CustomEvent('view-open', {detail: 'audit'}));
    document.querySelectorAll('[data-category],[data-all]').forEach(b => b.classList.remove('active'));
    if (!data) {
      $('#audit').innerHTML = '<p class="g-empty">점검 기록을 읽는 중…</p>';
      try { await load(); } catch (e) { $('#audit').innerHTML = `<p class="g-empty">점검 기록을 열지 못했습니다. ${esc(e.message)}</p>`; return; }
    }
    render();
  }

  document.addEventListener('view-open', ev => { if (ev.detail !== 'audit' && open) show(false); });
  document.addEventListener('click', ev => {
    const t = ev.target;
    if (t.closest('#open-audit')) return show(true);
    if (open && t.closest('#au-run')) return rerun();
    if (open && t.closest('[data-category],[data-all]')) show(false);
  });
})();
