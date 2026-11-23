'use strict';
const $ = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
const statuses = {todo: '대기', in_progress: '진행 중', review: '검토', done: '완료(메모)', deferred: '후순위'};
const priorities = {low: '낮음', normal: '보통', high: '높음', urgent: '긴급'};
let catalog, management = {revision: 0, records: {}}, category = '', selected = '', dirty = false, saving = false;
const fileURL = p => '/files/' + String(p).split('/').map(encodeURIComponent).join('/');
const record = e => ({status: 'todo', priority: 'normal', notes: '', ...(management.records[e.id] || {})});
const link = (path, label) => `<a target="_blank" rel="noopener" href="${esc(fileURL(path))}">${esc(label || path)}</a>`;

async function request(url, options) {
  const r = await fetch(url, options);
  let data;
  try { data = await r.json(); } catch { throw new Error('서버 응답을 읽을 수 없습니다. 서버가 켜져 있는지 확인하세요.'); }
  if (!r.ok) { const err = new Error(data.error || `요청 실패 (${r.status})`); err.status = r.status; throw err; }
  return data;
}

// 서버는 시작할 때의 코드를 그대로 쓴다. 화면 파일은 디스크에서 바로 읽지만 파이썬 코드가 바뀌었거나
// (또는 이 점검 자체를 모르는 오래된 서버면) 새 기능이 빠져 있을 수 있어 머리에 알린다.
async function checkServer() {
  const box = $('#stale-banner');
  if (!box) return;
  let text = '';
  try {
    const r = await fetch('/api/server');
    if (r.status === 404) text = '서버가 낡았습니다. 새 화면 기능 일부가 비어 있을 수 있으니 서버를 끄고 다시 시작하세요.';
    else if (r.ok) {
      const s = await r.json();
      if (s.stale) text = '서버가 낡았습니다. 서버 코드가 바뀐 뒤 다시 시작하지 않았습니다(' + [...s.changed, ...s.added, ...s.removed].join(', ') + '). 서버를 끄고 다시 시작하세요.';
    }
  } catch { /* 연결 문제는 아래 불러오기 안내가 따로 알린다 */ }
  box.textContent = text;
  box.hidden = !text;
}
// 머리의 원격 표시. 로컬 화면에서만 /api/remote(원격 켜짐·마지막 접속)를 묻고, 원격에서 열렸으면(body[data-remote="1"]) 그렇다고만 적는다.
async function remoteBadge() {
  const box = $('#remote-status');
  if (!box) return;
  if (document.body.dataset.remote === '1') {
    box.textContent = '원격으로 보는 중 · 일은 PC가 합니다';
    box.className = 'remote-status on';
    box.hidden = false;
    return;
  }
  try {
    const r = await fetch('/api/remote');
    if (!r.ok) return;
    const s = await r.json();
    if (s.problem) { box.textContent = s.problem; box.className = 'remote-status warn'; }
    else if (s.enabled) {
      box.textContent = '원격 켜짐 · ' + (s.last ? '마지막 접속 ' + s.last.email + ' ' + s.last.time : '아직 접속 없음');
      box.className = 'remote-status on';
    } else { box.textContent = '원격 꺼짐'; box.className = 'remote-status'; }
    box.hidden = false;
  } catch { /* 서버 연결 문제는 다른 곳이 알린다 */ }
}
if (document.body.dataset.remote !== '1') checkServer();
remoteBadge();
setInterval(checkServer, 60000);

async function load(refresh) {
  if (dirty && !confirm('저장하지 않은 메모를 버리고 다시 읽을까요?')) return;
  $('#notice').textContent = '불러오는 중…';
  try {
    [catalog, management] = await Promise.all([request('/api/catalog' + (refresh ? '?refresh=1' : '')), request('/api/management')]);
    dirty = false;
    $('#basis').textContent = catalog.basis;
    $('#generated').textContent = ' · ' + catalog.generated_at + '에 읽음';
    $('#notice').textContent = (catalog.warnings || []).join(' · ');
    $('#total-count').textContent = catalog.entities.length;
    $('#categories').innerHTML = catalog.categories.map(c => `<button data-category="${c.key}">${esc(c.name)}<span>${c.count}</span></button>`).join('');
    $('#usage-filter').innerHTML = '<option value="">전체</option>' + Object.entries(catalog.usage_labels).map(([k, v]) => `<option value="${k}">${esc(v)}</option>`).join('');
    render();
    if (selected && catalog.entities.some(e => e.id === selected)) inspect(selected);
  } catch (e) {
    $('#notice').textContent = `불러오지 못했습니다. ${e.message}`;
    $('#list').innerHTML = '<p class="empty">연결을 기다립니다.</p>';
  }
}

function render() {
  if (!catalog) return;
  const q = $('#search').value.toLocaleLowerCase(), st = $('#status-filter').value, us = $('#usage-filter').value;
  const rows = catalog.entities.filter(e => (!category || e.category === category) && (!q || (e.name + ' ' + e.summary + ' ' + e.id + ' ' + e.type).toLocaleLowerCase().includes(q))
    && (!st || record(e).status === st) && (!us || e.usage === us));
  const cat = catalog.categories.find(c => c.key === category);
  $('#view-context').textContent = cat ? cat.name : '전체';
  $('#view-title').textContent = cat ? cat.name : '게임에 들어 있는 것';
  $('#result-count').textContent = `${rows.length} / ${catalog.entities.length}개`;
  document.querySelectorAll('[data-category]').forEach(b => { const on = b.dataset.category === category; b.classList.toggle('active', on); b.toggleAttribute('aria-current', on); });
  document.querySelector('[data-all]').classList.toggle('active', !category);
  document.querySelector('[data-all]').toggleAttribute('aria-current', !category);
  $('#list').innerHTML = rows.length ? rows.map(e => {
    const r = record(e);
    return `<button class="entity-row ${selected === e.id ? 'selected' : ''}" ${selected === e.id ? 'aria-current="true"' : ''} data-id="${esc(e.id)}"><span><span class="row-name">${esc(e.name)}</span><span class="row-sub">${esc(e.type)} · ${esc(e.summary)}</span></span><span class="row-meta"><span class="badge ${esc(r.status)}">${esc(statuses[r.status] || r.status)}</span></span></button>`;
  }).join('') : '<p class="empty">일치하는 항목이 없습니다.<br>검색어를 줄이거나 거르기를 전체로 바꿔 보세요.</p>';
}

function section(s) {
  const head = `<h4>${esc(s.title)}</h4>`;
  if (s.kind === 'pairs') return head + '<dl class="properties">' + s.rows.map(([k, v]) => `<div class="property"><dt>${esc(k)}</dt><dd>${esc(v)}</dd></div>`).join('') + '</dl>';
  if (s.kind === 'table') return head + `<div class="table-wrap"><table class="data-table"><thead><tr>${s.columns.map(c => `<th>${esc(c)}</th>`).join('')}</tr></thead><tbody>${s.rows.map(r => `<tr>${r.map(c => `<td>${esc(c)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
  return head + '<ul class="text-lines">' + s.items.map(i => `<li>${esc(i)}</li>`).join('') + '</ul>';
}

function inspect(id) {
  const e = catalog.entities.find(x => x.id === id);
  if (!e) return;
  selected = id;
  const r = record(e), cat = catalog.categories.find(c => c.key === e.category);
  const usage = e.usage ? `<section class="detail-section"><h3>게임에서 쓰이나</h3><p><strong>${esc(catalog.usage_labels[e.usage])}</strong></p><ul class="source-list usage-note">${e.usage_notes.map(n => `<li>${esc(n)}</li>`).join('')}</ul><p class="usage-note">진입 장면(ChapterOne.tscn)에서 파일 경로 문자열을 따라간 정적 확인입니다. 「찾지 못함」은 쓰지 않는다는 확정이 아닙니다.</p></section>` : '';
  const sources = [e.source ? `<li>${link(e.source.path, '원본 · ' + e.source.path)}${e.source.line ? ' : ' + e.source.line + '줄' : ''}</li>` : '', ...e.links.map(l => `<li>${link(l.path, l.label + ' · ' + l.path)}</li>`)].join('');
  $('#inspector').innerHTML = `<div class="detail-head"><button type="button" class="back-list link-button">목록으로 돌아가기</button><p class="eyebrow">${esc(cat ? cat.name : '')} · ${esc(e.type)}</p><h2>${esc(e.name)}</h2><div class="detail-id">${esc(e.id)}</div></div>
${e.previews.length ? '<div id="previews"></div>' : ''}${usage}
<section class="detail-section"><h3>내용</h3><p>${esc(e.summary)}</p>${e.sections.map(section).join('')}</section>
<section class="detail-section"><h3>출처</h3><ul class="source-list">${sources || '<li>연결된 출처 문서가 없습니다.</li>'}</ul></section>
<form id="editor" class="detail-section editor"><h3>내 메모</h3><p class="editor-note">상태와 메모만 저장합니다. 게임 수치와 저장 파일은 바뀌지 않습니다. 「완료(메모)」는 내 표시일 뿐 품질 검수 통과가 아닙니다.</p>
<div class="edit-grid"><label>상태<select name="status">${Object.entries(statuses).map(([k, v]) => `<option value="${k}" ${r.status === k ? 'selected' : ''}>${v}</option>`).join('')}</select></label>
<label>우선순위<select name="priority">${Object.entries(priorities).map(([k, v]) => `<option value="${k}" ${r.priority === k ? 'selected' : ''}>${v}</option>`).join('')}</select></label></div>
<label>메모<textarea name="notes" maxlength="10000" placeholder="고칠 점, 확인할 점을 적어 두세요.">${esc(r.notes)}</textarea></label>
<div class="save-line"><button class="primary" type="submit">메모 저장</button><span class="save-feedback" role="status" aria-live="polite"></span></div></form>`;
  e.previews.forEach(preview);
  $('#editor').addEventListener('input', () => { dirty = true; $('.save-feedback').textContent = '저장하지 않은 변경'; });
  $('#editor').addEventListener('submit', save);
}

function preview(item) {
  const host = $('#previews'), url = fileURL(item.path), name = item.path.split('/').pop(), box = document.createElement('section');
  box.className = 'preview';
  if (item.kind === 'image') {
    box.innerHTML = `<img loading="lazy" src="${esc(url)}" alt="${esc(name)}"><p>${esc(name)}</p>`;
    box.querySelector('img').addEventListener('error', () => { box.innerHTML = '<p>그림을 불러오지 못했습니다.</p>'; });
  } else if (item.kind === 'audio') {
    box.innerHTML = `<p>${esc(name)} · 직접 재생</p><audio controls preload="none" src="${esc(url)}"></audio>`;
  } else if (item.kind === 'glb') {
    box.innerHTML = '<button class="primary" type="button">3D 모델 불러오기</button><p>돌려 보고 확대할 수 있습니다. 애니메이션이 있으면 고를 수 있습니다.</p><div class="model-host"></div>';
    box.querySelector('button').onclick = async function () {
      this.disabled = true; this.textContent = '불러오는 중…';
      try {
        await import('/vendor/model-viewer.min.js');
        await customElements.whenDefined('model-viewer');
        const Viewer = customElements.get('model-viewer');
        Viewer.mapURLs(u => { const x = new URL(u, location.href); if (x.origin !== location.origin && !['blob:', 'data:'].includes(x.protocol)) throw new Error('외부 리소스는 허용하지 않습니다.'); return u; });
        const mv = document.createElement('model-viewer');
        mv.setAttribute('camera-controls', ''); mv.setAttribute('interaction-prompt', 'none'); mv.setAttribute('shadow-intensity', '0'); mv.setAttribute('alt', name);
        mv.src = url;
        const target = box.querySelector('.model-host');
        target.append(mv);
        mv.addEventListener('load', () => {
          this.remove();
          const clips = mv.availableAnimations || [];
          const controls = document.createElement('div');
          if (clips.length) {
            const select = document.createElement('select');
            clips.forEach(n => { const o = document.createElement('option'); o.value = n; o.textContent = n; select.append(o); });
            const play = document.createElement('button'); play.className = 'primary'; play.textContent = '애니메이션 재생';
            mv.animationName = clips[0];
            select.onchange = () => { mv.animationName = select.value; mv.pause(); mv.currentTime = 0; play.textContent = '애니메이션 재생'; };
            play.onclick = () => { if (mv.paused) { mv.play(); play.textContent = '일시 정지'; } else { mv.pause(); play.textContent = '애니메이션 재생'; } };
            controls.append(select, play);
          } else controls.textContent = '들어 있는 애니메이션 없음';
          target.append(controls);
        });
        mv.addEventListener('error', ev => { target.textContent = '3D를 불러오지 못했습니다. ' + ((ev.detail && ev.detail.sourceError && ev.detail.sourceError.message) || ''); this.remove(); });
      } catch (err) { this.disabled = false; this.textContent = '3D 다시 불러오기'; box.querySelector('p').textContent = '뷰어를 불러오지 못했습니다. ' + err.message; }
    };
  } else return;
  host.append(box);
}

async function save(event) {
  event.preventDefault();
  if (saving) return;
  const form = event.currentTarget, button = form.querySelector('button[type=submit]'), feedback = form.querySelector('.save-feedback');
  saving = true; button.disabled = true; feedback.textContent = '저장 중…';
  try {
    management = await request('/api/management', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({revision: management.revision, id: selected, changes: Object.fromEntries(new FormData(form))})});
    dirty = false; feedback.textContent = '저장했습니다.'; render();
  } catch (e) {
    if (e.status === 409) {
      management = await request('/api/management');
      feedback.textContent = '다른 곳에서 먼저 저장되었습니다. 입력한 메모는 그대로 두었으니 다시 저장하면 됩니다.';
      const d = document.createElement('details');
      d.innerHTML = `<summary>저장된 최신 기록 보기</summary><pre>${esc(JSON.stringify(management.records[selected] || {}, null, 2))}</pre>`;
      feedback.append(d);
    } else feedback.textContent = '저장하지 못했습니다. ' + e.message;
  } finally { saving = false; button.disabled = false; }
}

function select(id) {
  if (saving) return;
  if (dirty && !confirm('저장하지 않은 메모를 버리고 다른 항목을 열까요?')) return;
  dirty = false; inspect(id); $('#inspector').scrollTop = 0; render();
  if (matchMedia('(max-width:1100px)').matches) $('#inspector').scrollIntoView({block: 'start'});
}

document.addEventListener('click', e => {
  if (e.target.closest('.back-list')) $('#workspace').scrollIntoView({block: 'start'});
  const c = e.target.closest('[data-category]'), all = e.target.closest('[data-all]'), row = e.target.closest('[data-id]');
  if (c) { category = c.dataset.category; render(); }
  if (all) { category = ''; render(); }
  if (row) select(row.dataset.id);
});
['#search', '#status-filter', '#usage-filter'].forEach(s => $(s).addEventListener(s === '#search' ? 'input' : 'change', render));
$('#reload').onclick = () => load(true);
window.addEventListener('beforeunload', e => { if (dirty) { e.preventDefault(); e.returnValue = ''; } });
load(false);
