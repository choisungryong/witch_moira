'use strict';
// 균형 실험실. 균형 시뮬레이터(모델)에 값을 바꿔 넣고 결과를 본다. 게임 데이터 파일은 읽기만 하고 쓰지 않는다.
(function () {
  const $ = s => document.querySelector(s);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
  let meta = null, open = false, base = {}, changes = {}, sel = {policies: null, witches: null, seeds: 10, gear: ''};
  let last = null, prev = null, running = false, timer = null, exps = [], pick = [], compareOn = false, notice = '';
  const pct = v => v === null || v === undefined ? '-' : Math.round(v * 100) + '%';
  const num = (v, d) => v === null || v === undefined ? '-' : (Math.round(v * Math.pow(10, d ?? 2)) / Math.pow(10, d ?? 2)).toString();
  const MARK = {in: ['안', 'in'], low: ['낮음', 'low'], high: ['높음', 'high']};
  const markTag = m => m && MARK[m] ? `<span class="bl-mk ${MARK[m][1]}" title="목표 범위 ${m === 'in' ? '안' : m === 'low' ? '아래' : '위'}">${MARK[m][0]}</span>` : '';

  async function req(url, options) {
    const r = await fetch(url, options);
    let d;
    try { d = await r.json(); } catch { throw new Error('서버 응답을 읽을 수 없습니다.'); }
    if (!r.ok) throw new Error(d.error || '요청 실패 (' + r.status + ')');
    return d;
  }
  const post = (url, body) => req(url, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)});

  function targetText(t, digits) {
    if (!t) return '';
    const [lo, hi] = t, f = x => digits ? Number(x).toFixed(digits) : Math.round(x * 100) + '%';
    if (lo !== null && hi !== null) return f(lo) + '~' + f(hi);
    return lo !== null ? f(lo) + ' 이상' : hi !== null ? f(hi) + ' 이하' : '';
  }
  function delta(cur, old, unit) {
    if (cur === null || cur === undefined || old === null || old === undefined) return '';
    const d = unit === 'pp' ? (cur - old) * 100 : cur - old;
    const small = unit === 'pp' ? Math.abs(d) < 0.5 : Math.abs(d) < 0.005;
    if (small) return '';
    const txt = unit === 'pp' ? Math.abs(Math.round(d)) + '%p' : unit === 'n' ? String(Math.abs(d)) : Math.abs(d).toFixed(2);
    return ` <span class="bl-d ${d > 0 ? 'up' : 'down'}" title="직전 실행 대비">${d > 0 ? '▲' : '▼'}${txt}</span>`;
  }

  // ---- 데이터 읽기 ----------------------------------------------------------------------
  function allRows() {
    const rows = [];
    meta.spells.forEach(g => g.rows.forEach(r => rows.push(r)));
    meta.spell_common.forEach(r => rows.push(r));
    meta.rhythm.forEach(g => g.rows.forEach(r => rows.push(r)));
    (meta.calibration.params || []).forEach(r => rows.push({key: r.key, value: r.value, editable: true}));
    return rows;
  }
  async function loadMeta(spells, preset) {
    const q = new URLSearchParams();
    if (spells) q.set('spells', spells);
    if (preset) q.set('preset', preset);
    meta = await req('/api/balance/meta?' + q);
    base = {};
    allRows().forEach(r => { if (r.key && r.editable) base[r.key] = r.value; });
    if (!sel.policies) sel.policies = meta.policies.map(p => p.id);
    if (!sel.witches) sel.witches = meta.witches.map(w => w.id);
  }
  async function loadExps() {
    try { exps = (await req('/api/balance/experiments')).experiments; } catch (e) { exps = []; notice = '실험 목록을 불러오지 못했습니다. ' + e.message; }
  }

  // ---- 왼쪽: 값 ------------------------------------------------------------------------
  const fmtVal = v => typeof v === 'number' ? String(v) : String(v);
  function rowHtml(r) {
    if (!r.editable || !r.key) return `<tr class="bl-ro"><td class="bl-l">${esc(r.label)}<small>${esc(r.path)}</small></td><td class="bl-o">${esc(fmtVal(r.value))}</td><td colspan="2" class="bl-na">이 경로는 고칠 수 없음</td></tr>`;
    const cur = r.key in changes ? changes[r.key] : r.value;
    return `<tr data-row="${esc(r.key)}" class="${r.key in changes ? 'chg' : ''}"><td class="bl-l">${esc(r.label)}<small>${esc(r.path || r.key)}</small></td><td class="bl-o">${esc(fmtVal(r.value))}</td><td><input type="number" step="any" data-bk="${esc(r.key)}" value="${esc(fmtVal(cur))}" aria-label="${esc(r.label)}"></td><td><button type="button" class="bl-rs" data-reset="${esc(r.key)}" title="원래 값으로">↺</button></td></tr>`;
  }
  const tableHtml = rows => `<table class="bl-vt"><thead><tr><th>값</th><th>원래</th><th>실험</th><th></th></tr></thead><tbody>${rows.map(rowHtml).join('')}</tbody></table>`;
  function group(id, title, sub, rows, openIt) {
    if (!rows.length) return '';
    return `<details class="bl-g" data-grp="${esc(id)}" ${openIt ? 'open' : ''}><summary><b>${esc(title)}</b> <small>${esc(sub || '')}</small> <span class="bl-cnt"></span></summary>${tableHtml(rows)}</details>`;
  }
  const ELEM = {ember: '불꽃', frost: '냉기', arc: '번개'}, ROLE = {basic: '기본기', ring: '원형'};
  function leftHtml() {
    const m = meta;
    const files = m.spell_files.map(f => `<option value="${esc(f.id)}" ${f.id === m.spells_id ? 'selected' : ''}>${esc(f.label)}</option>`).join('');
    const presets = m.presets.map(p => `<option value="${esc(p.id)}" ${p.id === m.preset ? 'selected' : ''}>${esc(p.label)}</option>`).join('');
    const spells = m.spells.map(g => group('sp-' + g.short, `${ELEM[g.element] || g.element || ''} ${ROLE[g.role] || g.role || ''}`, g.short, g.rows, false)).join('');
    const pol = {};
    m.policies.forEach(p => (pol[p.class] = pol[p.class] || []).push(p));
    const polHtml = m.classes.map(c => `<fieldset class="bl-pf"><legend>${esc(c.label)} <small>${c.target ? '목표 ' + targetText(c.target) : ''}</small></legend>${(pol[c.id] || []).map(p => `<label><input type="checkbox" data-pol="${esc(p.id)}" ${sel.policies.includes(p.id) ? 'checked' : ''}> ${esc(p.label)} <small>${esc(p.id)}</small></label>`).join('')}</fieldset>`).join('');
    const wit = m.witches.map(w => `<label><input type="checkbox" data-wit="${esc(w.id)}" ${sel.witches.includes(w.id) ? 'checked' : ''}> ${esc(w.label)} <small>${esc(w.id)}</small></label>`).join('');
    const calib = (m.calibration.params || []).map(r => ({key: r.key, path: r.name, label: r.name, value: r.value, editable: true}));
    const src = Object.entries(m.calibration.source_counts || {}).map(([k, v]) => `${esc(k)} ${v}`).join(' · ');
    return `${(m.warnings || []).map(w => `<p class="g-warn">${esc(w)}</p>`).join('')}
<section class="bl-box"><h3>1. 바탕</h3><label>주문 묶음<select id="bl-file">${files}</select></label><label>프리셋<select id="bl-preset">${presets}</select></label>
<p class="bl-help">프리셋이 정한 값(봉인 처치 수 등)이 「원래」 열에 들어 있습니다. 주문 묶음이나 프리셋을 바꾸면 바꾼 값은 비워집니다.</p></section>
<section class="bl-box"><h3>2. 스킬 값 <small id="bl-total"></small></h3><p class="bl-help">숫자 칸을 고치면 「바꾼 값」으로 표시되고 원래 값은 옆에 남습니다. ↺은 되돌리기입니다.</p>
<button type="button" id="bl-clear" class="quiet">바꾼 값 모두 되돌리기</button>${spells}${group('sp-common', '공통 규칙(축·진화·상태 등)', 'axis · evolve · statuses …', m.spell_common, false)}<div id="bl-orphans"></div></section>
<section class="bl-box"><h3>3. 적(리듬) 쪽 값</h3><p class="bl-help">마디마다 나오는 수, 간격, 체력 배율입니다. 게임의 전투 수치 파일을 읽은 값에 프리셋을 얹은 것입니다.</p>${m.rhythm.map(g => group('rh-' + g.id, g.title, '', g.rows, false)).join('')}</section>
<section class="bl-box"><h3>4. 모델 상수 <small>가설 포함</small></h3><p class="bl-help">시뮬레이터 안의 계산용 상수입니다. 출처: ${src || '-'} (fit=실측에 맞춤, spec=명세, hypo=가설, guess=추정). 게임 값이 아닙니다.</p>${group('calib', '모델 상수 보기', '', calib, false)}
${(m.calibration.report_lines || []).length ? `<details class="bl-g"><summary>맞춤 때 시뮬레이터가 낸 글 일부 <small>이 툴이 잰 값이 아님</small></summary><ul class="text-lines">${m.calibration.report_lines.map(l => `<li>${esc(l)}</li>`).join('')}</ul></details>` : ''}</section>
<section class="bl-box"><h3>5. 어떻게 돌릴까</h3><div class="bl-two"><div><b>찍는 방식</b><div class="bl-pols">${polHtml}</div><button type="button" class="quiet" data-allpol="1">전부 고르기</button> <button type="button" class="quiet" data-allpol="0">전부 비우기</button></div>
<div><b>마녀</b><div class="bl-wits">${wit}</div><label>판 수(시드 개수)<input id="bl-seeds" type="number" min="1" max="${m.limits.seeds}" value="${sel.seeds}"></label><label>장비 묶음<input id="bl-gear" type="text" maxlength="60" value="${esc(sel.gear)}" placeholder="비우면 장비 없음"></label><p class="bl-help">${esc(m.gear_note)}</p></div></div></section>
<div class="bl-runbar"><button type="button" id="bl-run" class="primary">실행</button><span id="bl-est"></span><span id="bl-status" role="status" aria-live="polite"></span></div>`;
  }

  function refreshCounts() {
    const per = {};
    document.querySelectorAll('#bl-left details[data-grp]').forEach(d => {
      const n = d.querySelectorAll('tr.chg').length;
      const c = d.querySelector(':scope > summary .bl-cnt');
      if (c) { c.textContent = n ? `· 바꾼 값 ${n}개` : ''; c.classList.toggle('on', n > 0); }
      per[d.dataset.grp] = n;
    });
    const total = Object.keys(changes).length;
    const t = $('#bl-total'); if (t) t.textContent = total ? `· 바꾼 값 ${total}개` : '· 바꾼 값 없음';
    const orphan = Object.keys(changes).filter(k => !(k in base));
    const o = $('#bl-orphans');
    if (o) o.innerHTML = orphan.length ? `<p class="bl-help">표에 없는 바꾼 값(불러온 실험에서 온 것):</p><ul class="text-lines">${orphan.map(k => `<li>${esc(k)} = ${esc(changes[k])} <button type="button" class="link-button" data-drop="${esc(k)}">지우기</button></li>`).join('')}</ul>` : '';
    const runs = (sel.policies || []).length * (sel.witches || []).length * (Number(sel.seeds) || 0);
    const est = $('#bl-est');
    if (est) { est.textContent = `정책 ${sel.policies.length} × 마녀 ${sel.witches.length} × ${sel.seeds}판 = ${runs}판`; est.classList.toggle('bad', runs > meta.limits.runs || runs === 0); }
  }

  function setChange(key, raw) {
    const v = parseFloat(raw);
    if (raw === '' || !Number.isFinite(v) || v === base[key]) delete changes[key]; else changes[key] = v;
    const tr = document.querySelector(`#bl-left tr[data-row="${CSS.escape(key)}"]`);
    if (tr) tr.classList.toggle('chg', key in changes);
    refreshCounts();
  }

  // ---- 오른쪽: 결과 ---------------------------------------------------------------------
  function polLabel(id) { const p = meta && meta.policies.find(x => x.id === id); return p ? p.label : id; }
  function witLabel(id) { const w = meta && meta.witches.find(x => x.id === id); return w ? w.label : id; }
  function deathsText(cell) { return (cell.deaths || []).slice(0, 2).map(d => `${d.beat}(${d.cause}) ${d.count}`).join(', '); }

  function resultHtml() {
    if (!last) return '<p class="g-empty">왼쪽에서 값을 고르고 「실행」을 누르면 이곳에 결과가 나옵니다. 처음에는 아무것도 바꾸지 않고 눌러 기준 결과를 보세요.</p>';
    const a = last.data.analysis, pa = prev ? prev.data.analysis : null, v = a.verdict;
    const pcells = pa ? pa.cells : {};
    const head = `<div class="bl-verdict ${v.ok ? 'ok' : 'bad'}" role="status"><span class="bl-vtag">${v.ok ? '서열 성립' : '서열 깨짐'}</span><b>${esc(v.headline)}</b>${pa ? `<small>직전: ${esc(pa.verdict.ok ? '성립' : '깨짐')} → 지금: ${esc(v.ok ? '성립' : '깨짐')}${pa.verdict.ok !== v.ok ? ' (바뀜)' : ''}</small>` : ''}</div>`;
    const stat = `<p class="bl-stat">목표 범위 안 <b>${a.in_target}</b> / ${a.judged_cells}칸${pa ? delta(a.in_target, pa.in_target, 'n') : ''} · 정체(600초) <b>${a.stalls}</b> / ${a.runs}판${pa ? delta(a.stalls, pa.stalls, 'n') : ''} · 걸린 시간 ${last.data.elapsed_s}초 · 바꾼 값 ${last.data.request.sets.length}개</p>`;
    // 정책 x 마녀
    const wit = a.witches;
    let rows = '', lastCls = null;
    a.policies.forEach(p => {
      const cls = p.split(':')[0], cr = a.class_rows.find(r => r.cls === cls);
      if (cls !== lastCls) { lastCls = cls; rows += `<tr class="bl-cls"><td colspan="${wit.length + 2}">${esc(cr ? cr.label : cls)} <small>${cr && cr.target ? '목표 ' + targetText(cr.target) : '목표 없음'}</small></td></tr>`; }
      const dsum = {};
      wit.forEach(w => (a.cells[p + '|' + w] ? a.cells[p + '|' + w].deaths : []).forEach(d => { const k = d.beat + '(' + d.cause + ')'; dsum[k] = (dsum[k] || 0) + d.count; }));
      const dtxt = Object.entries(dsum).sort((x, y) => y[1] - x[1]).slice(0, 2).map(([k, n]) => `${k} ${n}`).join(', ');
      rows += `<tr><td class="bl-pn">${esc(polLabel(p))}<small>${esc(p)}</small></td>${wit.map(w => {
        const c = a.cells[p + '|' + w];
        if (!c) return '<td>-</td>';
        const old = pcells[p + '|' + w];
        return `<td class="bl-c ${c.mark || ''}" title="판 길이 중앙 ${num(c.secs_median, 0)}초 · ${esc(deathsText(c))}">${pct(c.win_rate)} ${markTag(c.mark)}${delta(c.win_rate, old ? old.win_rate : null, 'pp')}<small>${num(c.secs_median, 0)}초</small></td>`;
      }).join('')}<td class="bl-dt">${esc(dtxt) || '-'}</td></tr>`;
    });
    const table = `<h3>정책 × 마녀 승률 <small>칸 색: 목표 범위 안(초록) / 밖(주황). ▲▼은 직전 실행과의 차</small></h3><div class="table-wrap"><table class="data-table bl-rt"><thead><tr><th>찍는 방식</th>${wit.map(w => `<th>${esc(witLabel(w))}</th>`).join('')}<th>주로 막힌 마디(원인)</th></tr></thead><tbody>${rows}</tbody></table></div>`;
    // 서열 줄
    const ord = `<h3>서열 · 시너지와 하나만 쌓기의 차</h3><div class="table-wrap"><table class="data-table"><thead><tr><th>마녀</th><th>판정</th><th>순서(승률)</th><th>시너지−하나만 <small>목표 50%p 이상</small></th><th>시너지 길 최저</th><th>길 사이 승률 차 <small>목표 10%p 이내</small></th><th>길 사이 판 길이 차 <small>목표 15% 이내</small></th></tr></thead><tbody>${v.witches.map(x => `<tr><td>${esc(x.label)}</td><td>${x.judged ? (x.ok ? '<b class="bl-okt">성립</b>' : '<b class="bl-badt">깨짐</b>') : '판정 불가'}</td><td>${x.seq.map(s => `${esc(s.label)} ${pct(s.value)}`).join(' > ')}${x.broken ? `<small class="bl-badt">${esc(x.broken)}</small>` : ''}</td><td>${x.gap_pp === null ? '-' : Math.round(x.gap_pp) + '%p ' + (x.gap_ok ? '<span class="bl-mk in">안</span>' : '<span class="bl-mk low">모자람</span>')}</td><td>${pct(x.syn_min)}</td><td>${x.path_spread_pp === null ? '-' : Math.round(x.path_spread_pp) + '%p'}</td><td>${x.path_secs_spread_pct === null ? '-' : Math.round(x.path_secs_spread_pct) + '%'}</td></tr>`).join('')}</tbody></table></div>`;
    // 정책류
    const cls = `<h3>정책 종류별 평균 승률 <small>목표는 설계 문서 P7</small></h3><div class="table-wrap"><table class="data-table"><thead><tr><th>종류</th><th>목표</th>${wit.map(w => `<th>${esc(witLabel(w))}</th>`).join('')}<th>평균</th></tr></thead><tbody>${a.class_rows.map(r => {
      const o = pa ? pa.class_rows.find(x => x.cls === r.cls) : null;
      return `<tr><td>${esc(r.label)}</td><td>${esc(targetText(r.target))}</td>${wit.map(w => `<td>${pct(r.per_witch[w])}${delta(r.per_witch[w], o ? o.per_witch[w] : null, 'pp')}</td>`).join('')}<td><b>${pct(r.mean)}</b> ${markTag(r.mark)}${delta(r.mean, o ? o.mean : null, 'pp')}</td></tr>`;
    }).join('')}</tbody></table></div>`;
    // 힘 ÷ 위협
    const rbeats = a.beats;
    const rt = `<h3>마디별 힘 ÷ 위협 <small>1보다 크면 처리가 앞섬. 목표는 설계 문서 P4(무리 기준, 없는 칸은 목표 없음)</small></h3><div class="table-wrap"><table class="data-table"><thead><tr><th>종류</th>${rbeats.map(b => `<th>${esc(b)}</th>`).join('')}</tr></thead><tbody>${a.r_rows.map(r => {
      const o = pa ? pa.r_rows.find(x => x.cls === r.cls) : null;
      return `<tr><td>${esc(r.label)}</td>${rbeats.map(b => { const c = r.beats[b] || {}; return `<td title="목표 ${esc(targetText(c.target, 2) || '없음')}">${num(c.value, 2)} ${markTag(c.mark)}${delta(c.value, o && o.beats[b] ? o.beats[b].value : null)}</td>`; }).join('')}</tr>`;
    }).join('')}</tbody></table></div>`;
    // 죽는 마디
    const dth = `<h3>죽는 마디와 원인 <small>전체 ${a.runs}판 가운데</small></h3>${a.deaths.length ? `<ul class="text-lines bl-deaths">${a.deaths.map(d => `<li><b>${esc(d.beat)}</b> ${esc(d.cause)} · ${d.count}판</li>`).join('')}</ul>` : '<p class="bl-help">죽은 판이 없습니다.</p>'}<p class="bl-help">정체(600초 안에 끝나지 않음): ${a.stalls}판.</p>`;
    // 모르는 키
    const extraCells = Object.entries(a.cells).filter(([, c]) => Object.keys(c.extras || {}).length);
    const extras = extraCells.length || a.unknown_top_keys.length ? `<details class="bl-g"><summary>그 밖에 시뮬레이터가 내놓은 값 <small>이 화면이 이름을 모르는 값을 그대로 보여 줍니다</small></summary>${a.unknown_top_keys.length ? `<p class="bl-help">결과 머리의 새 키: ${esc(a.unknown_top_keys.join(', '))}</p>` : ''}${extraCells.length ? `<div class="table-wrap"><table class="data-table"><thead><tr><th>칸</th>${a.unknown_cell_keys.map(k => `<th>${esc(k)}</th>`).join('')}</tr></thead><tbody>${extraCells.map(([k, c]) => `<tr><td>${esc(k)}</td>${a.unknown_cell_keys.map(x => `<td>${esc(typeof c.extras[x] === 'object' && c.extras[x] ? JSON.stringify(c.extras[x]) : c.extras[x])}</td>`).join('')}</tr>`).join('')}</tbody></table></div>` : ''}</details>` : '';
    const raw = `<details class="bl-g"><summary>시뮬레이터 원문 보고 보기</summary><pre>${esc(last.data.report_text)}</pre></details>`;
    return `${head}${stat}<p class="bl-cmd">같은 값으로 명령줄에서 돌리려면: <code>${esc(last.data.command)}</code></p>${ord}${table}${cls}${rt}${dth}${extras}${raw}${saveForm()}`;
  }

  function saveForm() {
    return `<section class="bl-box"><h3>이 결과를 실험으로 저장</h3><div class="bl-save"><label>이름<input id="bl-name" type="text" maxlength="60" placeholder="예: 승2 생성 양 6"></label><label>메모<textarea id="bl-memo" maxlength="4000" placeholder="무엇을 보려고 했는지, 알게 된 것"></textarea></label>
<div class="bl-actions"><button type="button" class="primary" id="bl-save">실험 저장</button><button type="button" id="bl-export-now">지금 바꾼 값 내보내기(--set 묶음)</button><span id="bl-save-fb" role="status"></span></div></div></section>`;
  }

  // ---- 실험 목록·견주기 -----------------------------------------------------------------
  function expsHtml() {
    const list = exps.map(e => {
      const s = e.summary || {}, n = (e.settings.sets || []).length;
      return `<li class="bl-exp"><label><input type="checkbox" data-pick="${esc(e.id)}" ${pick.includes(e.id) ? 'checked' : ''}> <b>${esc(e.name)}</b></label><small>${esc(e.saved_at)} · 바꾼 값 ${n}개 · ${esc(s.headline || '결과 요약 없음')}</small>${e.memo ? `<em>${esc(e.memo)}</em>` : ''}
<span class="bl-ea"><button type="button" class="link-button" data-load="${esc(e.id)}">값 불러오기</button><button type="button" class="link-button" data-export="${esc(e.id)}">내보내기</button></span></li>`;
    }).join('');
    const cmp = compareOn && pick.length === 2 ? compareHtml(exps.find(e => e.id === pick[0]), exps.find(e => e.id === pick[1])) : '';
    return `<h3>저장한 실험 <small>${exps.length}개 · _local/balance-lab/experiments/</small></h3>${notice ? `<p class="g-warn">${esc(notice)}</p>` : ''}${list ? `<ul class="bl-exps">${list}</ul>` : '<p class="g-empty">저장한 실험이 없습니다.</p>'}
<div class="bl-actions"><button type="button" id="bl-compare" ${pick.length === 2 ? '' : 'disabled'}>고른 둘 나란히 견주기${pick.length === 2 ? '' : ' (둘을 고르세요)'}</button><span class="bl-help">실험 저장은 모델의 값만 남깁니다. 게임 데이터는 바뀌지 않습니다.</span><span id="bl-exp-fb" role="status"></span></div>${cmp}`;
  }

  function compareHtml(A, B) {
    if (!A || !B) return '';
    const sa = A.summary || {}, sb = B.summary || {};
    const ka = {}, kb = {};
    (A.settings.sets || []).forEach(s => (ka[s.key] = s.value));
    (B.settings.sets || []).forEach(s => (kb[s.key] = s.value));
    const keys = [...new Set([...Object.keys(ka), ...Object.keys(kb)])];
    const setRows = keys.map(k => `<tr class="${ka[k] !== kb[k] ? 'chg' : ''}"><td>${esc(k)}</td><td>${k in ka ? esc(ka[k]) : '<small>원래 값</small>'}</td><td>${k in kb ? esc(kb[k]) : '<small>원래 값</small>'}</td></tr>`).join('');
    const ca = sa.cells || {}, cb = sb.cells || {};
    const ckeys = [...new Set([...Object.keys(ca), ...Object.keys(cb)])];
    const cell = (x, y) => x ? pct(x.win_rate) : '-';
    const dd = (x, y) => x && y && x.win_rate !== null && y.win_rate !== null ? ((y.win_rate - x.win_rate) * 100) : null;
    const cRows = ckeys.map(k => { const d = dd(ca[k], cb[k]); const [p, w] = [k.slice(0, k.lastIndexOf('|')), k.slice(k.lastIndexOf('|') + 1)]; return `<tr><td>${esc(polLabel(p))} · ${esc(witLabel(w))}</td><td>${cell(ca[k])}</td><td>${cell(cb[k])}</td><td>${d === null ? '-' : d === 0 ? '＝' : `<span class="bl-d ${d > 0 ? 'up' : 'down'}">${d > 0 ? '▲' : '▼'}${Math.abs(Math.round(d))}%p</span>`}</td></tr>`; }).join('');
    const cl = {};
    (sa.class_rows || []).forEach(r => (cl[r.cls] = [r, null]));
    (sb.class_rows || []).forEach(r => { (cl[r.cls] = cl[r.cls] || [null, null])[1] = r; });
    const clRows = Object.entries(cl).map(([c, [x, y]]) => { const d = x && y && x.mean !== null && y.mean !== null ? (y.mean - x.mean) * 100 : null; return `<tr><td>${esc((x || y).label)}</td><td>${pct(x ? x.mean : null)}</td><td>${pct(y ? y.mean : null)}</td><td>${d === null ? '-' : d === 0 ? '＝' : `<span class="bl-d ${d > 0 ? 'up' : 'down'}">${d > 0 ? '▲' : '▼'}${Math.abs(Math.round(d))}%p</span>`}</td></tr>`; }).join('');
    const sameSetup = A.settings.preset === B.settings.preset && A.settings.spells === B.settings.spells && A.settings.seeds === B.settings.seeds;
    return `<div class="bl-cmpbox"><h3>견주기</h3><div class="bl-two"><div class="bl-verdict ${sa.ok ? 'ok' : 'bad'}"><span class="bl-vtag">A</span><b>${esc(A.name)}</b><small>${esc(sa.headline || '결과 요약 없음')}</small></div><div class="bl-verdict ${sb.ok ? 'ok' : 'bad'}"><span class="bl-vtag">B</span><b>${esc(B.name)}</b><small>${esc(sb.headline || '결과 요약 없음')}</small></div></div>
${sameSetup ? '' : '<p class="g-warn">두 실험의 프리셋·주문 묶음·판 수가 다릅니다. 승률 차가 값 때문인지 설정 때문인지 가려 보세요.</p>'}
<h4>바뀐 값 (A와 B가 다른 줄은 강조)</h4><div class="table-wrap"><table class="data-table"><thead><tr><th>값</th><th>A</th><th>B</th></tr></thead><tbody>${setRows || '<tr><td colspan="3">두 실험 모두 바꾼 값이 없습니다.</td></tr>'}</tbody></table></div>
<h4>종류별 평균 승률 (A → B)</h4><div class="table-wrap"><table class="data-table"><thead><tr><th>종류</th><th>A</th><th>B</th><th>차</th></tr></thead><tbody>${clRows}</tbody></table></div>
<details class="bl-g"><summary>칸별 승률 (A → B)</summary><div class="table-wrap"><table class="data-table"><thead><tr><th>칸</th><th>A</th><th>B</th><th>차</th></tr></thead><tbody>${cRows}</tbody></table></div></details></div>`;
  }

  // ---- 화면 만들기 ----------------------------------------------------------------------
  function render() {
    const p = $('#balance');
    if (!meta) return;
    const keepL = $('#bl-left') ? $('#bl-left').scrollTop : 0, keepR = $('#bl-right') ? $('#bl-right').scrollTop : 0;
    p.innerHTML = `<div class="bl-banner" role="note"><b>모델의 답이며 게임의 답이 아니다.</b><span><em>믿어도 되는 것</em> 서열, 값의 방향</span><span><em>안 되는 것</em> 정확한 승률</span></div>
<div class="bl-cols"><div id="bl-left" class="bl-col">${leftHtml()}</div><div id="bl-right" class="bl-col"><div id="bl-result">${resultHtml()}</div><section class="bl-box" id="bl-exps">${expsHtml()}</section></div></div>`;
    $('#bl-left').scrollTop = keepL; $('#bl-right').scrollTop = keepR;
    refreshCounts();
  }

  async function show(on) {
    open = on;
    document.body.classList.toggle('balance-mode', on);
    $('#balance').hidden = !on;
    $('#open-balance').classList.toggle('active', on);
    if (!on) return;
    document.dispatchEvent(new CustomEvent('view-open', {detail: 'balance'}));
    document.querySelectorAll('[data-category],[data-all]').forEach(b => b.classList.remove('active'));
    if (!meta) {
      $('#balance').innerHTML = '<p class="g-empty">시뮬레이터에 값을 묻는 중… (몇 초 걸립니다)</p>';
      try { await Promise.all([loadMeta(), loadExps()]); } catch (e) { $('#balance').innerHTML = `<p class="g-empty">균형 실험실을 열지 못했습니다. ${esc(e.message)}</p>`; return; }
    }
    render();
  }

  function currentSettings() {
    return {preset: meta.preset, spells: meta.spells_id, sets: Object.entries(changes).map(([key, value]) => ({key, value})),
      policies: sel.policies.slice(), witches: sel.witches.slice(), seeds: Number(sel.seeds), gear: sel.gear.trim() || null};
  }

  async function runNow() {
    if (running) return;
    const btn = $('#bl-run'), st = $('#bl-status'), t0 = Date.now();
    running = true; btn.disabled = true;
    timer = setInterval(() => { st.textContent = `계산 중… ${Math.round((Date.now() - t0) / 1000)}초`; }, 500);
    st.textContent = '계산 중…';
    try {
      const data = await post('/api/balance/run', currentSettings());
      prev = last; last = {data, at: new Date()};
      $('#bl-result').innerHTML = resultHtml();
      st.textContent = '';
    } catch (e) { st.textContent = '실행하지 못했습니다. ' + e.message; st.classList.add('bad'); }
    finally { running = false; clearInterval(timer); btn.disabled = false; }
  }

  function summaryOf(a, data) {
    const cells = {};
    Object.entries(a.cells).forEach(([k, c]) => { cells[k] = {win_rate: c.win_rate, secs_median: c.secs_median, mark: c.mark, stalls: c.stalls}; });
    const r = {};
    a.r_rows.forEach(x => { r[x.cls] = Object.fromEntries(Object.entries(x.beats).map(([b, v]) => [b, v.value])); });
    return {headline: a.verdict.headline, ok: a.verdict.ok, in_target: a.in_target, judged_cells: a.judged_cells, stalls: a.stalls, runs: a.runs, elapsed_s: data.elapsed_s,
      class_rows: a.class_rows.map(x => ({cls: x.cls, label: x.label, per_witch: x.per_witch, mean: x.mean})), cells, r,
      verdict_witches: a.verdict.witches.map(x => ({witch: x.witch, ok: x.ok, gap_pp: x.gap_pp, broken: x.broken})), command: data.command};
  }

  function download(name, obj) {
    const url = URL.createObjectURL(new Blob([JSON.stringify(obj, null, 1)], {type: 'application/json'}));
    const a = document.createElement('a'); a.href = url; a.download = name; document.body.append(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  async function doExport(body, fb) {
    try {
      const r = await post('/api/balance/export', body);
      download(r.path.split('/').pop(), r.bundle);
      fb.textContent = '내보냈습니다: ' + r.path + ' (다운로드도 함께 시작됩니다)';
    } catch (e) { fb.textContent = '내보내지 못했습니다. ' + e.message; }
  }

  async function loadSettings(e) {
    const s = e.settings;
    if (s.spells !== meta.spells_id || s.preset !== meta.preset) await loadMeta(s.spells, s.preset);
    changes = {};
    (s.sets || []).forEach(x => { if (x.value !== base[x.key]) changes[x.key] = x.value; });
    sel.policies = (s.policies && s.policies.length ? s.policies : meta.policies.map(p => p.id)).slice();
    sel.witches = (s.witches && s.witches.length ? s.witches : meta.witches.map(w => w.id)).slice();
    sel.seeds = s.seeds; sel.gear = s.gear || '';
    render();
    $('#bl-status').textContent = `「${e.name}」의 값을 불러왔습니다. 실행을 누르면 같은 조건으로 다시 돕니다.`;
  }

  document.addEventListener('view-open', ev => { if (ev.detail !== 'balance' && open) show(false); });
  document.addEventListener('click', async ev => {
    const t = ev.target;
    if (t.closest('#open-balance')) return show(true);
    if (open && t.closest('[data-category],[data-all]')) show(false);
    if (!open || !$('#balance').contains(t)) return;
    const q = s => t.closest(s);
    if (q('#bl-run')) return runNow();
    if (q('[data-reset]')) { const k = q('[data-reset]').dataset.reset; const i = document.querySelector(`#bl-left input[data-bk="${CSS.escape(k)}"]`); delete changes[k]; if (i) i.value = base[k]; document.querySelector(`#bl-left tr[data-row="${CSS.escape(k)}"]`)?.classList.remove('chg'); return refreshCounts(); }
    if (q('[data-drop]')) { delete changes[q('[data-drop]').dataset.drop]; return refreshCounts(); }
    if (q('#bl-clear')) { if (Object.keys(changes).length && !confirm('바꾼 값을 모두 원래대로 되돌릴까요?')) return; changes = {}; return render(); }
    if (q('[data-allpol]')) { sel.policies = q('[data-allpol]').dataset.allpol === '1' ? meta.policies.map(p => p.id) : []; return render(); }
    if (q('#bl-save')) {
      const fb = $('#bl-save-fb'), name = $('#bl-name').value.trim();
      if (!name) { fb.textContent = '실험 이름을 적어 주세요.'; return; }
      if (!last) { fb.textContent = '먼저 실행해 결과를 얻으세요.'; return; }
      try {
        // 마지막 실행의 설정으로 저장한다(왼쪽을 그 뒤에 바꿨어도 결과와 짝이 맞게).
        const r = await post('/api/balance/experiments', {name, memo: $('#bl-memo').value, settings: last.data.request, summary: summaryOf(last.data.analysis, last.data)});
        await loadExps(); $('#bl-exps').innerHTML = expsHtml(); fb.textContent = '저장했습니다: ' + r.id;
      } catch (e) { fb.textContent = '저장하지 못했습니다. ' + e.message; }
      return;
    }
    if (q('#bl-export-now')) return doExport({name: ($('#bl-name') || {}).value || '지금 바꾼 값', memo: ($('#bl-memo') || {}).value || '', settings: currentSettings()}, $('#bl-save-fb'));
    if (q('[data-export]')) return doExport({id: q('[data-export]').dataset.export}, $('#bl-exp-fb'));
    if (q('[data-load]')) { const e = exps.find(x => x.id === q('[data-load]').dataset.load); if (e) await loadSettings(e); return; }
    if (q('#bl-compare')) { compareOn = true; $('#bl-exps').innerHTML = expsHtml(); }
  });
  document.addEventListener('change', async ev => {
    const t = ev.target;
    if (!open || !$('#balance').contains(t)) return;
    if (t.id === 'bl-file' || t.id === 'bl-preset') {
      if (Object.keys(changes).length && !confirm('주문 묶음이나 프리셋을 바꾸면 바꾼 값이 비워집니다. 계속할까요?')) { render(); return; }
      changes = {};
      const spells = t.id === 'bl-file' ? t.value : meta.spells_id, preset = t.id === 'bl-preset' ? t.value : meta.preset;
      $('#bl-status').textContent = '값을 다시 읽는 중…';
      try { await loadMeta(spells, preset); render(); } catch (e) { $('#bl-status').textContent = '다시 읽지 못했습니다. ' + e.message; }
    } else if (t.dataset.pol !== undefined) { sel.policies = [...document.querySelectorAll('[data-pol]')].filter(x => x.checked).map(x => x.dataset.pol); refreshCounts(); }
    else if (t.dataset.wit !== undefined) { sel.witches = [...document.querySelectorAll('[data-wit]')].filter(x => x.checked).map(x => x.dataset.wit); refreshCounts(); }
    else if (t.dataset.pick !== undefined) {
      pick = pick.filter(x => x !== t.dataset.pick);
      if (t.checked) pick.push(t.dataset.pick);
      if (pick.length > 2) pick = pick.slice(-2);
      compareOn = false; $('#bl-exps').innerHTML = expsHtml();
    }
  });
  document.addEventListener('input', ev => {
    const t = ev.target;
    if (!open || !$('#balance').contains(t)) return;
    if (t.dataset.bk) setChange(t.dataset.bk, t.value);
    else if (t.id === 'bl-seeds') { sel.seeds = t.value === '' ? 0 : Math.floor(Number(t.value)); refreshCounts(); }
    else if (t.id === 'bl-gear') sel.gear = t.value;
  });
  if (location.hash === '#balance') show(true);
})();
