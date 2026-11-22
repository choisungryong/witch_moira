'use strict';
// 캐릭터 화면. 게임을 띄우지 않고 주인공 몸의 클립(걷기·달리기 등)을 나란히 돌려 보고, 동작 배율과 이동 속도를 따로 움직이며
// 발 미끄러짐을 숫자로 본다. 숫자는 계산(모델의 답)과 이 화면 안 측정이다. 게임에서 잰 값이 아니다.
// 게임 파일은 쓰지 않는다. 고른 값은 /api/picks 에 저장되고, 게임 자리표에는 에이전트가 tools/art/motion_apply.py 로 옮긴다.
// 3D 는 tools/manager/vendor/three (오프라인). 바깥 주소로 요청하지 않는다.
(function () {
  const $ = s => document.querySelector(s);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
  const RATE_MIN = 0.3, RATE_MAX = 2.5, SPEED_MIN = 2.0, SPEED_MAX = 8.0;
  const STANCE_MARGIN = 0.03, SAMPLE_DT = 1 / 120;
  const fx = (x, d) => (x === null || x === undefined || Number.isNaN(x)) ? '-' : Number(x).toFixed(d);

  // 계산식. tools/art/motion_math.py 와 같은 식이며, 화면이 스스로 서버가 준 표와 견준다(data-selfcheck).
  const strideFor = (v, L, r) => v * L / r;
  const rateFromContract = (v, L, stride) => v * L / stride;
  const rateNoSlip = (v, g, s) => v / (g * s);
  const slipOf = (v, r, g, s) => v - r * g * s;

  let open = false, lines = null, lineId = '', detail = null, picks = null, T = null, loaders = null;
  let gltfs = {}, state = null, cells = {}, raf = 0, last = 0, frames = 0, webgl = false, loadError = '', rig = null, building = 0, pendingRefresh = false;
  let saving = false;
  let tripo = null, tripoView = '', tripoWant = '', tv = null, tripoBusy = false;

  async function call(url, options) {
    const r = await fetch(url, options);
    let d;
    try { d = await r.json(); } catch { throw new Error('서버 응답을 읽을 수 없습니다.'); }
    if (!r.ok) { const e = new Error(d.error || '요청 실패 (' + r.status + ')'); e.status = r.status; e.data = d; throw e; }
    return d;
  }

  // ---------------------------------------------------------------- 주소(해시)
  function parseHash() {
    const m = /^#character(?:\/([^?]*))?(?:\?(.*))?$/.exec(location.hash || '');
    if (!m) return null;
    const q = new URLSearchParams(m[2] || '');
    return {id: decodeURIComponent(m[1] || ''), q};
  }
  function parseCell(text) {
    if (!text) return null;
    const [head, rate] = text.split('@');
    const [a, b] = head.includes(':') ? head.split(':') : ['body', head];
    return {src: a === 'motions' ? 'motions' : 'body', clip: b, rate: rate === undefined || rate === '' ? null : Number(rate)};
  }
  function cellText(c) {
    return (c.src === 'motions' ? 'motions:' : '') + c.clip + (c.rate === null ? '' : '@' + Number(c.rate.toFixed(3)));
  }
  function writeHash() {
    if (!state) return;
    const q = new URLSearchParams();
    q.set('a', cellText(state.a)); q.set('b', cellText(state.b));
    q.set('v', String(Number(state.v.toFixed(2))));
    q.set('cam', state.cam === 'game' ? String(detail.game.camera.size) : state.cam === 'cand' ? String(detail.game.camera.size_candidate) : 'free');
    if (tripoView) q.set('tripo', tripoView);
    history.replaceState(null, '', '#character/' + encodeURIComponent(lineId) + '?' + q.toString());
    const box = $('#ch-url');
    if (box) box.value = location.href;
  }

  // ---------------------------------------------------------------- 상태
  function gameSpeed() { return detail && detail.game.base_speed.value; }
  function bodyScale() { return (detail.contract && detail.contract.scale) || 1; }
  function runClip() { return detail.run_clip || 'run'; }

  function defaultState(q) {
    const gs = gameSpeed();
    const a = parseCell(q && q.get('a')) || {src: 'body', clip: runClip(), rate: null};
    const b = parseCell(q && q.get('b')) || {src: 'body', clip: 'walk', rate: null};
    let v = q && q.get('v') ? Number(q.get('v')) : gs;
    if (!Number.isFinite(v)) v = gs || 5.8;
    const camq = q && q.get('cam');
    const gcam = detail.game.camera;
    let cam = camq === null || camq === undefined ? 'free' : 'game';   // 주소에 카메라가 없으면 돌려 보기(게임 카메라에서는 몸이 작게 보인다)
    if (camq === 'free') cam = 'free';
    else if (camq !== null && camq !== undefined && gcam.size_candidate && Math.abs(Number(camq) - gcam.size_candidate) < 1e-6) cam = 'cand';
    else if (gcam.size === null) cam = 'free';
    return {a, b, v: Math.min(SPEED_MAX, Math.max(SPEED_MIN, v)), cam, look: true, px: false};
  }
  function rateOf(c) {
    if (c.rate !== null) return c.rate;
    if (c.src === 'body' && c.clip === runClip() && detail.rate_now) return detail.rate_now;
    return 1;
  }
  function clipInfo(c) {
    const g = gltfs[c.src];
    const anim = g && g.animations.find(a => a.name === c.clip);
    const rep = ((c.src === 'motions' ? detail.motions : detail.body) || {}).clips || {};
    const r = rep[c.clip] || null;
    if (!anim) return null;
    return {anim, L: (r && r.length_s) || anim.duration, g_toe: r ? r.g_toe : null, g_hips: r ? r.g_hips : null, from_report: !!r};
  }

  // ---------------------------------------------------------------- 3D 준비
  async function loadThree() {
    if (T) return;
    const [three, gl, oc, su] = await Promise.all([import('three'), import('three/addons/loaders/GLTFLoader.js'), import('three/addons/controls/OrbitControls.js'), import('three/addons/utils/SkeletonUtils.js')]);
    T = three; loaders = {GLTFLoader: gl.GLTFLoader, OrbitControls: oc.OrbitControls, SkeletonUtils: su};
  }
  async function loadGlbs() {
    gltfs = {};
    const loader = new loaders.GLTFLoader();
    if (detail.media.body) gltfs.body = await loader.loadAsync(detail.media.body.url);
    if (detail.media.motions) {
      try { gltfs.motions = await loader.loadAsync(detail.media.motions.url); } catch (e) { loadError += ' 후보 묶음을 읽지 못함: ' + e.message; }
    }
  }
  const boneNamed = (root, suffix) => { let f = null; root.traverse(o => { if (!f && o.name && o.name.endsWith(suffix) && (o.isBone || o.type === 'Bone' || o.type === 'Object3D' || o.type === 'Group')) f = o; }); return f; };

  // 발끝 뼈와 앞 방향. 이름은 glb 안에서 mixamorig:LeftToeBase 가 mixamorigLeftToeBase 로 바뀌어 있을 수 있어 끝 글자로 찾는다.
  function buildRig() {
    rig = null;
    if (!gltfs.body) return;
    const root = loaders.SkeletonUtils.clone(gltfs.body.scene);
    const holder = new T.Group(); holder.add(root);
    holder.updateMatrixWorld(true);
    const toeL = boneNamed(root, 'LeftToeBase'), toeR = boneNamed(root, 'RightToeBase'), footL = boneNamed(root, 'LeftFoot');
    const names = [];
    root.traverse(o => { if (o.isBone) names.push(o.name); });
    rig = {holder, root, toeL, toeR, yaw: 0, boneNames: names};
    if (toeL && footL) {
      const a = new T.Vector3(), b = new T.Vector3();
      toeL.getWorldPosition(a); footL.getWorldPosition(b);
      const x = a.x - b.x, z = a.z - b.z;
      if (Math.hypot(x, z) > 1e-6) rig.yaw = Math.atan2(-x, z);
    }
    holder.rotation.y = rig.yaw; holder.scale.setScalar(bodyScale());
  }

  // 화면 안 측정: 클립을 1/120 s 간격으로 샘플해 디딤 구간의 땅 기준 수평 속도 RMS(m/s). 그림과 따로 계산한다.
  function measure(c, v) {
    const info = clipInfo(c);
    if (!rig || !info || !rig.toeL || !rig.toeR) return null;
    const rate = rateOf(c), Lc = info.anim.duration;
    const mixer = new T.AnimationMixer(rig.root);
    const action = mixer.clipAction(info.anim); action.play();
    const K = Math.max(8, Math.round(Lc / (rate * SAMPLE_DT))), dt = Lc / (rate * K);
    const P = [[], []], tmp = new T.Vector3();
    for (let k = 0; k < K; k++) {
      action.time = Lc * k / K; mixer.update(0); rig.holder.updateMatrixWorld(true);
      [rig.toeL, rig.toeR].forEach((b, i) => { b.getWorldPosition(tmp); P[i].push([tmp.x, tmp.y, tmp.z]); });
    }
    mixer.stopAllAction(); mixer.uncacheRoot(rig.root);
    let sumSq = 0, n = 0, sumVz = 0, ymin = Infinity;
    for (let i = 0; i < 2; i++) for (const p of P[i]) ymin = Math.min(ymin, p[1]);
    for (let i = 0; i < 2; i++) {
      for (let k = 0; k < K; k++) {
        const a = P[i][k], b = P[i][(k + 1) % K];
        if (a[1] > ymin + STANCE_MARGIN || b[1] > ymin + STANCE_MARGIN) continue;
        const vx = (b[0] - a[0]) / dt, vz = (b[2] - a[2]) / dt + v;
        sumSq += vx * vx + vz * vz; sumVz += (b[2] - a[2]) / dt; n++;
      }
    }
    const s = bodyScale();
    return {rms: n ? Math.sqrt(sumSq / n) : null, samples: n, ymin,
            g_meas: n ? -sumVz / n / (rate * s) : null, samples_total: 2 * K};
  }

  // ---------------------------------------------------------------- 칸(3D)
  function makeFloor() {
    const c = document.createElement('canvas'); c.width = c.height = 128;
    const g = c.getContext('2d');
    g.fillStyle = '#2a3338'; g.fillRect(0, 0, 128, 128);
    g.fillStyle = '#1d2427'; g.fillRect(0, 0, 64, 64); g.fillRect(64, 64, 64, 64);
    const tex = new T.CanvasTexture(c);
    tex.colorSpace = T.SRGBColorSpace;
    tex.wrapS = tex.wrapT = T.RepeatWrapping; tex.repeat.set(30, 30);
    tex.anisotropy = 4;
    const m = new T.Mesh(new T.PlaneGeometry(60, 60), new T.MeshBasicMaterial({map: tex}));
    m.rotation.x = -Math.PI / 2;
    return {mesh: m, tex};
  }
  const DOTS = 700, DOT_LIFE = 1.6;
  function makeDots() {
    const geo = new T.BufferGeometry();
    const pos = new Float32Array(DOTS * 3).fill(-1000), col = new Float32Array(DOTS * 3);
    geo.setAttribute('position', new T.BufferAttribute(pos, 3)); geo.setAttribute('color', new T.BufferAttribute(col, 3));
    const pts = new T.Points(geo, new T.PointsMaterial({size: 5, sizeAttenuation: false, vertexColors: true}));
    pts.frustumCulled = false;
    return {pts, pos, col, age: new Float32Array(DOTS).fill(99), tint: new Float32Array(DOTS * 3), next: 0};
  }

  function lightRig(scene) {
    const look = detail.look, on = state.look && look;
    const keyE = on ? (look.light_key ?? 0.65) : 1.6, fillE = on ? (look.light_fill ?? 0.38) : 0.85;
    const dir = (rx, ry) => new T.Vector3(0, 0, -1).applyEuler(new T.Euler(rx * Math.PI / 180, ry * Math.PI / 180, 0, 'YXZ'));
    const key = new T.DirectionalLight(0xeddbc4, keyE * Math.PI), fill = new T.DirectionalLight(0x7faad8, fillE * Math.PI);
    key.position.copy(dir(-42, -35).multiplyScalar(-10)); fill.position.copy(dir(-28, 145).multiplyScalar(-10));
    scene.add(key, fill, new T.AmbientLight(0xffffff, on ? 0.9 : 0.6));
  }
  function applyLook() {
    const look = detail.look, mul = state.look && look && look.albedo_mul;
    for (const k of Object.keys(gltfs)) gltfs[k].scene.traverse(o => {
      if (!o.isMesh) return;
      (Array.isArray(o.material) ? o.material : [o.material]).forEach(m => {
        if (!m || !m.color) return;
        if (!m.userData.baseColor) m.userData.baseColor = m.color.clone();
        m.color.copy(m.userData.baseColor);
        if (mul) m.color.multiply(new T.Color(mul[0], mul[1], mul[2]));
      });
    });
  }

  function buildCell(key) {
    const el = $('#ch-stage-' + key);
    const cell = {key, el, ok: false};
    cells[key] = cell;
    try {
      cell.canvas = document.createElement('canvas'); el.prepend(cell.canvas);
      cell.renderer = new T.WebGLRenderer({canvas: cell.canvas, antialias: true, alpha: false, preserveDrawingBuffer: true});
      cell.renderer.setPixelRatio(1);
      cell.renderer.setClearColor(0x0c0f10, 1);
    } catch (e) {
      cell.canvas.remove(); cell.canvas = null; cell.renderer = null;
      $('#ch-note-' + key).textContent = '이 브라우저에서 3D를 그릴 수 없습니다(' + e.message.slice(0, 80) + '). 수치는 그대로 계산됩니다.';
      return cell;
    }
    webgl = true;
    cell.scene = new T.Scene();
    const f = makeFloor(); cell.floor = f; cell.scene.add(f.mesh);
    cell.dots = makeDots(); cell.scene.add(cell.dots.pts);
    lightRig(cell.scene);
    cell.holder = new T.Group();
    if (gltfs.body) {
      cell.model = loaders.SkeletonUtils.clone(gltfs.body.scene);
      cell.model.traverse(o => { if (o.isSkinnedMesh) o.frustumCulled = false; });
      cell.holder.add(cell.model);
      cell.holder.rotation.y = rig ? rig.yaw : 0; cell.holder.scale.setScalar(bodyScale());
      cell.scene.add(cell.holder);
      cell.mixer = new T.AnimationMixer(cell.model);
      cell.toeL = boneNamed(cell.model, 'LeftToeBase'); cell.toeR = boneNamed(cell.model, 'RightToeBase');
    }
    cell.ok = true;
    setCamera(cell);
    const ro = new ResizeObserver(() => resizeCell(cell)); ro.observe(el); cell.ro = ro;
    resizeCell(cell);
    return cell;
  }
  function resizeCell(cell) {
    if (!cell.renderer) return;
    const w = Math.max(10, cell.el.clientWidth), h = Math.max(10, cell.el.clientHeight);
    cell.renderer.setSize(w, h, false);
    fitCamera(cell);
  }
  function fitCamera(cell) {
    const cam = cell.camera; if (!cam) return;
    const aspect = Math.max(10, cell.el.clientWidth) / Math.max(10, cell.el.clientHeight);
    if (cam.isOrthographicCamera) {
      const h = cell.camSize; cam.left = -h * aspect / 2; cam.right = h * aspect / 2; cam.top = h / 2; cam.bottom = -h / 2;
    } else cam.aspect = aspect;
    cam.updateProjectionMatrix();
  }
  function setCamera(cell) {
    if (!cell.ok) return;
    if (cell.controls) { cell.controls.dispose(); cell.controls = null; }
    const gc = detail.game.camera;
    if (state.cam === 'free' || gc.size === null || !gc.offset) {
      cell.camera = new T.PerspectiveCamera(30, 16 / 9, 0.1, 200);
      cell.camera.position.set(3.6, 2.3, 5.6);
      cell.controls = new loaders.OrbitControls(cell.camera, cell.canvas);
      cell.controls.target.set(0, 1.25, 0); cell.controls.update();
      cell.camSize = null;
    } else {
      cell.camSize = state.cam === 'cand' ? gc.size_candidate : gc.size;
      cell.camera = new T.OrthographicCamera(-1, 1, 1, -1, 0.1, 200);
      cell.camera.position.set(...gc.offset); cell.camera.lookAt(0, 0, 0);
    }
    fitCamera(cell);
    cell.px = null;
  }
  function pxHeight(cell) {
    if (!cell.ok || !cell.model || !cell.camera || !cell.camera.isOrthographicCamera) return null;
    cell.scene.updateMatrixWorld(true); cell.camera.updateMatrixWorld(true);
    const v = new T.Vector3(); let lo = Infinity, hi = -Infinity;
    cell.model.traverse(o => {
      if (!o.isSkinnedMesh) return;
      const n = o.geometry.attributes.position.count;
      for (let i = 0; i < n; i += 3) { o.getVertexPosition(i, v); v.applyMatrix4(o.matrixWorld).project(cell.camera); lo = Math.min(lo, v.y); hi = Math.max(hi, v.y); }
    });
    return hi > lo ? (hi - lo) / 2 * 1080 : null;
  }
  function playClip(cell, c) {
    if (!cell.ok || !cell.mixer) return;
    const info = clipInfo(c);
    cell.mixer.stopAllAction();
    if (!info) { cell.action = null; return; }
    cell.action = cell.mixer.clipAction(info.anim); cell.action.reset().play();
  }

  // ---------------------------------------------------------------- 화면 구성
  function clipNames(src) { const g = gltfs[src]; return g ? g.animations.map(a => a.name) : []; }

  function cellHtml(key) {
    const c = state[key];
    const srcs = [['body', '몸']].concat(gltfs.motions ? [['motions', '후보 묶음']] : []);
    return `<section class="ch-cell" id="ch-cell-${key}" aria-label="칸 ${key.toUpperCase()}"><h3>칸 ${key.toUpperCase()}</h3>
<div class="ch-controls"><label>클립 출처<select data-k="${key}" data-f="src">${srcs.map(([v, t]) => `<option value="${v}" ${c.src === v ? 'selected' : ''}>${t}</option>`).join('')}</select></label>
<label>클립<select data-k="${key}" data-f="clip">${clipNames(c.src).map(n => `<option ${c.clip === n ? 'selected' : ''}>${esc(n)}</option>`).join('')}</select></label></div>
<div class="ch-rate"><label style="flex:1;min-width:150px">동작 배율<span style="display:flex;gap:8px;align-items:center"><input type="range" min="${RATE_MIN}" max="${RATE_MAX}" step="0.01" data-k="${key}" data-f="rate" aria-label="칸 ${key.toUpperCase()} 동작 배율"><output class="ch-num" id="ch-rate-${key}"></output></span></label></div>
<div class="ch-group" style="margin-bottom:8px"><button type="button" data-k="${key}" data-act="noslip">미끄럼 없는 배율로</button><button type="button" data-k="${key}" data-act="game">게임 지금 값</button></div>
<div class="ch-stage" id="ch-stage-${key}"><p class="ch-note" id="ch-note-${key}"></p></div>
<table class="data-table ch-metrics" id="ch-metrics-${key}"><tbody></tbody></table></section>`;
  }
  function buildScreen() {
    const root = $('#character');
    const gs = detail.game.base_speed, gc = detail.game.camera;
    const camBtn = (id, label, ok) => `<button type="button" data-cam="${id}" ${ok ? '' : 'disabled'} aria-pressed="false">${label}</button>`;
    root.innerHTML = `<h2>캐릭터</h2>
<p class="alert info">걸음 값은 계산한 값(모델의 답)과 이 화면 안에서 잰 값입니다. 게임에서 잰 값이 아닙니다. 몸 보고서의 지면 속도는 ±6% 어긋날 수 있습니다. 색과 밝기는 근사이며 게임과 같지 않습니다. 게임 파일은 이 화면이 바꾸지 않습니다.</p>
<div id="ch-warn"></div>
<div class="ch-bar">
<label>캐릭터 줄<select id="ch-line">${lines.lines.map(l => `<option value="${esc(l.id)}" ${l.id === lineId ? 'selected' : ''} ${l.has_body ? '' : 'disabled'}>${esc(l.name)}${l.has_body ? '' : ' (몸 없음)'}</option>`).join('')}</select></label>
<div><div class="bl-help">카메라</div><div class="ch-group" id="ch-cams">${camBtn('game', gc.size === null ? '게임 (읽지 못함)' : '게임 ' + gc.size, gc.size !== null && gc.offset)}${camBtn('cand', '게임 ' + gc.size_candidate + ' (후보)', gc.size !== null && gc.offset)}${camBtn('free', '자유(돌려 보기)', true)}</div></div>
<div><div class="bl-help">표시</div><div class="ch-group"><button type="button" id="ch-look" aria-pressed="true">겉모습 반영(근사)</button><button type="button" id="ch-px" aria-pressed="false">1080p 크기</button></div></div>
</div>
<section class="ch-speed" aria-label="이동 속도"><div class="ch-row"><label style="flex:1;min-width:200px">이동 속도 (m/s, 두 칸 공통)<span class="ch-row"><input type="range" id="ch-v" min="${SPEED_MIN}" max="${SPEED_MAX}" step="0.1" aria-label="이동 속도"><output class="ch-num" id="ch-v-out"></output></span></label>
<button type="button" id="ch-v-game">게임 값으로</button></div>
<div class="ch-ticks" id="ch-ticks"></div>
<p class="bl-help" id="ch-v-note"></p></section>
<div class="ch-pair">${cellHtml('a')}${cellHtml('b')}</div>
<section class="ch-pick" aria-label="고르기"><h3>고르기</h3><p class="bl-help">칸마다 판정을 정하고 저장하면 디렉터가 읽습니다. 게임에는 바로 들어가지 않습니다.</p>
<div class="ch-pair">${['a', 'b'].map(k => `<div><fieldset><legend>칸 ${k.toUpperCase()}</legend><div class="ch-radios" role="radiogroup" aria-label="칸 ${k.toUpperCase()} 판정">${[['', '표시 없음'], ['pick', '이걸로'], ['reject', '아님'], ['hold', '보류']].map(([v, t]) => `<label><input type="radio" name="ch-verdict-${k}" value="${v}" ${v === '' ? 'checked' : ''}>${t}</label>`).join('')}</div></fieldset><label>한 줄 말<input type="text" id="ch-note-in-${k}" maxlength="300" placeholder="예: 조금 빠른 걸음이 낫다"></label></div>`).join('')}</div>
<div class="ch-link"><button type="button" class="primary" id="ch-save">저장</button><span class="bl-help" id="ch-save-msg" role="status" aria-live="polite"></span></div>
<h4 style="margin-top:12px">이 줄의 기록</h4><ul class="ch-records" id="ch-records"></ul></section>
<section class="ch-pick" aria-label="바로 가는 주소"><h3>바로 가는 주소</h3><div class="ch-link"><input id="ch-url" readonly aria-label="지금 상태의 주소"><button type="button" id="ch-copy">주소 복사</button><span class="bl-help" id="ch-copy-msg"></span></div></section>
<section class="ch-pick" aria-label="그림과 영상"><h3>그림과 영상</h3><div id="ch-media"></div></section>
<details class="ch-pick" id="ch-tripo" aria-label="3D 만들기(수동)"><summary><b>3D 만들기(수동)</b></summary><div id="ch-tripo-body"><p class="bl-help">읽는 중…</p></div></details>
<section class="ch-pick" aria-label="단계"><h3>단계</h3><p class="bl-help">${esc(detail.stages_note)}</p></section>`;
    $('#ch-ticks').innerHTML = gs.value ? `<span style="left:${(gs.value - SPEED_MIN) / (SPEED_MAX - SPEED_MIN) * 100}%">▲ 게임 ${gs.value}</span>` : '';
    renderMedia();
    loadTripo();
  }

  // ---------------------------------------------------------------- 3D 만들기(수동): 보낼 그림, 받은 모델
  const kb = n => n >= 1048576 ? (n / 1048576).toFixed(1) + ' MB' : Math.max(1, Math.round(n / 1024)) + ' KB';
  async function loadTripo() {
    const body = $('#ch-tripo-body'), id = lineId;
    try { tripo = await call('/api/characters/' + encodeURIComponent(id) + '/tripo'); } catch (e) { if (body) body.innerHTML = `<p class="alert warn">불러오지 못했습니다. ${esc(e.message)}</p>`; return; }
    if (id !== lineId || !$('#ch-tripo-body')) return;
    renderTripo();
    const root = $('#character');
    root.setAttribute('data-tripo-inputs', tripo.inputs.map(r => r.name + ':' + r.width + 'x' + r.height).join(','));
    root.setAttribute('data-tripo-outputs', tripo.outputs.length);
    if (tripoWant) {
      const row = tripo.outputs.find(r => r.name === tripoWant);
      tripoWant = '';
      if (row) { $('#ch-tripo').open = true; viewGlb(row); }
    }
  }
  function renderTripo() {
    const t = tripo, body = $('#ch-tripo-body');
    if (!t.work_found) { body.innerHTML = `<p class="alert warn">작업 폴더를 찾지 못함: ${esc(t.work_root)}</p><p class="bl-help">${esc(t.rule)}</p>`; return; }
    const imgs = t.inputs.map(r => `<figure><img loading="lazy" src="${esc(r.url)}" alt="${esc(r.name)}"><figcaption>${esc(r.name)}<br>${r.width ? r.width + '×' + r.height + ' 화소' : '크기 모름'} · ${kb(r.bytes)}</figcaption>
<div class="ch-group"><a class="ch-dl" href="${esc(r.url)}" download="${esc(r.name)}">내려받기</a><button type="button" data-tripo="copy" data-path="${esc(r.path)}">경로 복사</button></div></figure>`).join('');
    const outs = t.outputs.map(r => `<tr><td>${esc(r.name)}</td><td>${kb(r.bytes)}</td><td>${esc(r.received)}</td><td>${r.error ? esc(r.error) : (r.triangles === null || r.triangles === undefined ? '삼각형 수 모름' : r.triangles.toLocaleString() + '개') + ' · 질감 ' + (r.has_texture ? '있음' : '없음') + ' · 뼈대 ' + (r.has_skin ? '있음' : '없음')}</td><td><button type="button" data-tripo="view" data-key="${esc(r.key)}">돌려 보기</button></td></tr>`).join('');
    body.innerHTML = `<h4>보낼 그림</h4><p class="bl-help">${esc(t.in_path)}</p>
${imgs ? `<div class="ch-media">${imgs}</div>` : `<p class="bl-help">${t.in_exists ? '이 폴더가 비어 있습니다.' : '이 폴더가 아직 없습니다.'} 한 장에 여러 면이 든 시트가 있으면 아래 명령으로 나눕니다(이 화면이 실행하지는 않습니다).</p><pre class="ch-cmd">${esc(t.split_cmd)}</pre>`}
<div class="ch-group" style="margin:8px 0"><button type="button" data-tripo="open" data-folder="tripo_in">폴더 열기</button><span class="bl-help" id="ch-tripo-open-in"></span></div>
<h4>받은 모델</h4><p class="bl-help">${esc(t.out_path)} · 받은 .glb 는 이름에 시각을 붙여 저장하고 덮어쓰지 않습니다(상한 ${Math.round(t.limit_bytes / 1048576)} MB). 지우는 것은 탐색기에서 합니다.</p>
<label class="ch-drop" id="ch-drop" tabindex="0">.glb 파일을 여기에 끌어다 놓거나 눌러서 고르세요<input type="file" id="ch-tripo-file" accept=".glb" hidden></label>
<p class="bl-help" id="ch-tripo-msg" role="status" aria-live="polite"></p>
${outs ? `<div class="table-wrap"><table class="data-table"><thead><tr><th>이름</th><th>크기</th><th>받은 때</th><th>머리에서 읽은 것</th><th></th></tr></thead><tbody>${outs}</tbody></table></div>` : '<p class="bl-help">받은 모델이 아직 없습니다.</p>'}
<div class="ch-group" style="margin:8px 0"><button type="button" data-tripo="open" data-folder="tripo_out">폴더 열기</button><span class="bl-help" id="ch-tripo-open-out"></span></div>
<div class="ch-stage" id="ch-tripo-stage" hidden><p class="ch-note" id="ch-tripo-note"></p></div>
<details><summary>손으로 하는 순서</summary><ol class="ch-steps">
<li>Tripo에서 여러 면으로 만들기를 고르고, 정면 칸에 front, 뒤 칸에 back, 왼쪽 칸에 left 그림을 넣습니다. 오른쪽 칸은 비웁니다.</li>
<li>쿼드, 면 수 20000~25000, 공개 설정은 비공개로 합니다.</li>
<li>내보내기 전에 돌려서 봅니다: 땋은 머리가 목덜미에서 시작하는가, 등에 머리 덩어리가 없는가, 치마와 다리 사이가 막히지 않았는가, 머리핀이 한쪽에 하나인가, 팔이 몸통에 붙지 않았는가.</li>
<li>무료 재시도는 내보내기 전에 씁니다. 내보내면 재시도가 사라집니다. 한 번에 여러 개를 뽑았으면 얼굴(두 눈의 크기와 높이, 입의 자리)을 보고 고릅니다.</li>
<li>텍스처는 정면·뒤 두 장으로, 해상도는 높게(8K 체험이 있으면 그것으로). 얼굴이 어긋나면 해상도가 가장 크게 듣습니다.</li>
<li>텍스처를 입힌 뒤 GLB로 내보내 이 칸에 넣습니다. 리깅은 아직 하지 않습니다.</li>
<li>좌우가 뒤집혀 나오면 옆 그림을 오른쪽 칸으로 옮겨 다시 만듭니다.</li></ol></details>`;
  }
  function disposeTripoViewer() {
    if (!tv) return;
    if (tv.raf) cancelAnimationFrame(tv.raf);
    if (tv.ro) tv.ro.disconnect();
    if (tv.controls) tv.controls.dispose();
    if (tv.renderer) tv.renderer.dispose();
    if (tv.canvas) tv.canvas.remove();
    tv = null;
  }
  async function viewGlb(row) {
    const stage = $('#ch-tripo-stage'), note = $('#ch-tripo-note'), root = $('#character');
    if (!stage) return;
    stage.hidden = false; disposeTripoViewer(); tripoView = row.name; writeHash();
    note.textContent = '불러오는 중…'; root.setAttribute('data-tripo-viewer', 'loading');
    try {
      if (!T) await loadThree();
      const canvas = document.createElement('canvas'); stage.prepend(canvas);
      const renderer = new T.WebGLRenderer({canvas, antialias: true, preserveDrawingBuffer: true});
      renderer.setPixelRatio(1); renderer.setClearColor(0x0c0f10, 1);
      tv = {canvas, renderer};
      const scene = new T.Scene();
      const grid = new T.GridHelper(10, 20, 0x475660, 0x2d373c); scene.add(grid);
      scene.add(new T.HemisphereLight(0xffffff, 0x445055, 1.4));
      const key = new T.DirectionalLight(0xffffff, 2.2); key.position.set(3, 6, 4); scene.add(key);
      const g = await new loaders.GLTFLoader().loadAsync(row.url);
      const obj = g.scene;
      let box = new T.Box3().setFromObject(obj); const size = box.getSize(new T.Vector3());
      const k = size.y > 1e-6 ? 2 / size.y : 1; obj.scale.setScalar(k);
      box = new T.Box3().setFromObject(obj); const c = box.getCenter(new T.Vector3());
      obj.position.set(-c.x, -box.min.y, -c.z); scene.add(obj);
      const camera = new T.PerspectiveCamera(30, 16 / 9, 0.1, 100); camera.position.set(2.6, 1.7, 4.2);
      const controls = new loaders.OrbitControls(camera, canvas); controls.target.set(0, 1, 0); controls.update();
      Object.assign(tv, {scene, camera, controls});
      const fit = () => { const w = Math.max(10, stage.clientWidth), h = Math.max(10, stage.clientHeight); renderer.setSize(w, h, false); camera.aspect = w / h; camera.updateProjectionMatrix(); };
      tv.ro = new ResizeObserver(fit); tv.ro.observe(stage); fit();
      const loop = () => { if (!tv) return; tv.raf = requestAnimationFrame(loop); controls.update(); renderer.render(scene, camera); };
      loop();
      note.textContent = row.name + ' · 선 자세(동작 없음), 돌려 볼 수 있습니다. 원래 높이 ' + size.y.toFixed(2) + ' 를 2 로 맞춰 보입니다.';
      root.setAttribute('data-tripo-viewer', 'loaded'); root.setAttribute('data-tripo-name', row.name);
      root.setAttribute('data-tripo-height', size.y.toFixed(3));
    } catch (e) {
      note.textContent = '돌려 보지 못했습니다: ' + e.message;
      root.setAttribute('data-tripo-viewer', 'error');
    }
  }
  async function uploadGlb(file) {
    const msg = $('#ch-tripo-msg');
    if (tripoBusy || !file) return;
    if (!file.name.toLowerCase().endsWith('.glb')) { msg.textContent = '.glb 파일만 받습니다.'; return; }
    if (file.size > tripo.limit_bytes) { msg.textContent = '파일이 너무 큽니다(상한 ' + Math.round(tripo.limit_bytes / 1048576) + ' MB).'; return; }
    tripoBusy = true; msg.textContent = '올리는 중… (' + kb(file.size) + ')';
    try {
      const d = await call('/api/characters/' + encodeURIComponent(lineId) + '/tripo_out?name=' + encodeURIComponent(file.name),
        {method: 'POST', headers: {'Content-Type': 'application/octet-stream'}, body: file});
      tripo = d.tripo; disposeTripoViewer(); renderTripo();
      $('#ch-tripo-msg').textContent = '저장했습니다: ' + d.saved;
      $('#character').setAttribute('data-tripo-saved', d.saved);
    } catch (e) { msg.textContent = '저장하지 못했습니다. ' + e.message; }
    tripoBusy = false;
  }
  async function tripoClick(el) {
    const act = el.dataset.tripo;
    if (act === 'copy') {
      const done = () => { el.textContent = '복사함'; setTimeout(() => { el.textContent = '경로 복사'; }, 1500); };
      (navigator.clipboard ? navigator.clipboard.writeText(el.dataset.path) : Promise.reject()).then(done, () => { el.textContent = el.dataset.path; });
    } else if (act === 'open') {
      const f = el.dataset.folder, out = $(f === 'tripo_in' ? '#ch-tripo-open-in' : '#ch-tripo-open-out');
      try {
        const d = await call('/api/characters/' + encodeURIComponent(lineId) + '/open', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({folder: f})});
        out.textContent = d.opened ? '탐색기로 열었습니다.' : '없음: ' + d.reason;
      } catch (e) { out.textContent = '열지 못했습니다. ' + e.message; }
    } else if (act === 'view') {
      const row = tripo.outputs.find(r => r.key === el.dataset.key);
      if (row) viewGlb(row);
    }
  }
  function renderMedia() {
    const m = detail.media, order = ['main', 'apose_front', 'apose_back', 'apose_side'];
    const figs = order.filter(k => m[k]).map(k => `<figure><img loading="lazy" src="${esc(m[k].url)}" alt="${esc(m[k].label)}"><figcaption>${esc(m[k].label)}</figcaption></figure>`);
    const vids = Object.keys(m).filter(k => k.startsWith('idle_video_')).map(k => `<figure><video controls preload="none" loop muted src="${esc(m[k].url)}"></video><figcaption>${esc(m[k].label)}</figcaption></figure>`);
    const miss = detail.missing_media.map(k => ({main: '메인 이미지', apose_front: 'A자세 앞', apose_back: 'A자세 뒤', apose_side: 'A자세 옆'}[k] || '대기 영상')).filter((v, i, a) => a.indexOf(v) === i);
    $('#ch-media').innerHTML = `<div class="ch-media">${figs.join('')}${vids.join('')}</div>${miss.length ? `<p class="bl-help">없음: ${esc(miss.join(', '))}</p>` : ''}`;
  }

  // ---------------------------------------------------------------- 수치
  function cellNumbers(key) {
    const c = state[key], info = clipInfo(c), v = state.v, s = bodyScale(), r = rateOf(c);
    const out = {key, clip: c.clip, rate: r, info};
    if (!info) return out;
    out.L = info.L; out.stride = strideFor(v, info.L, r);
    out.g = info.g_toe;
    if (info.g_toe) {
      out.slip = slipOf(v, r, info.g_toe, s); out.slipPct = out.slip / v * 100;
      out.r0 = rateNoSlip(v, info.g_toe, s); out.vNoSlip = r * info.g_toe * s;
    }
    return out;
  }
  function slipWords(x) { return Math.abs(x) < 0.05 ? '거의 없음' : x > 0 ? '발이 땅 위로 끌림' : '발이 헛돎(러닝머신)'; }
  function renderMetrics(key, n) {
    const body = $('#ch-metrics-' + key + ' tbody');
    if (!n.info) { body.innerHTML = '<tr><td>클립</td><td>이 출처에 "' + esc(state[key].clip) + '" 클립이 없습니다</td></tr>'; return; }
    const c = state[key], info = n.info, meas = cells[key] && cells[key].meas;
    const rows = [
      ['동작 배율 r', fx(n.rate, 3)],
      ['주기 길이 L', fx(n.L, 5) + ' s' + (info.from_report ? '' : ' (클립 길이)')],
      ['보폭 계약 값 v×L/r', fx(n.stride, 3) + ' m'],
      ['계산 미끄러짐', n.slip === undefined ? '지면 속도 없음' : fx(n.slip, 2) + ' m/s (' + fx(n.slipPct, 0) + '%) ' + slipWords(n.slip)],
      ['측정 미끄러짐(이 화면, 디딤 RMS)', meas ? (meas.rms === null ? '디딤 구간 없음' : fx(meas.rms, 2) + ' m/s · 디딤 ' + meas.samples + '표본') : (rig && rig.toeL ? '-' : '발끝 뼈를 찾지 못함')],
      ['미끄럼 없는 배율 r0', n.r0 === undefined ? '-' : fx(n.r0, 2) + (n.r0 > RATE_MAX || n.r0 < RATE_MIN ? ' (막대 범위 밖)' : '')],
      ['미끄럼 없는 이동 속도(이 배율에서)', n.vNoSlip === undefined ? '-' : fx(n.vNoSlip, 2) + ' m/s'],
      ['지면 속도 출처', info.from_report ? `몸 보고서 · 발끝 ${fx(info.g_toe, 2)} / 엉덩이 ${fx(info.g_hips, 2)} m/s (±6%)` + (meas && meas.g_meas ? ` · 이 화면 발끝 ${fx(meas.g_meas, 2)}` : '') : '보고서에 없음'],
    ];
    if (state.px) rows.push(['1080p 크기에서 키', cells[key] && cells[key].px ? fx(cells[key].px, 0) + ' 화소' : (state.cam === 'free' ? '자유 카메라에서는 재지 않음' : '-')]);
    body.innerHTML = rows.map(([a, b]) => `<tr><td>${esc(a)}</td><td>${esc(b)}</td></tr>`).join('');
  }

  function selfcheck() {
    let ok = true;
    for (const c of detail.selfcheck) {
      const e = [[strideFor(c.v, c.L, c.r), c.stride], [slipOf(c.v, c.r, c.g, c.s), c.slip], [rateNoSlip(c.v, c.g, c.s), c.r0], [rateFromContract(c.v, c.L, c.stride), c.rate_from_stride]];
      for (const [a, b] of e) if (!(Math.abs(a - b) < 1e-9)) ok = false;
    }
    return ok;
  }

  function refresh() {
    if (!state || !detail) return;
    const root = $('#character');
    for (const k of ['a', 'b']) {
      const c = state[k];
      const slider = document.querySelector(`input[data-k="${k}"][data-f="rate"]`);
      const r = rateOf(c);
      if (slider && document.activeElement !== slider) slider.value = r;
      $('#ch-rate-' + k).textContent = fx(r, 2);
      const meas = cells[k] ? (cells[k].meas = measureSafe(c, state.v)) : null;
      const n = cellNumbers(k);
      if (cells[k] && cells[k].ok) {
        if (state.cam === 'free') cells[k].px = null; else if (cells[k].px == null) cells[k].px = pxHeight(cells[k]);
      }
      renderMetrics(k, n);
      const set = (name, val) => root.setAttribute('data-' + k + '-' + name, val === null || val === undefined ? '' : String(val));
      set('clip', c.clip); set('source', c.src); set('rate', fx(n.rate, 3)); set('length', n.L === undefined ? '' : fx(n.L, 5));
      set('stride', n.stride === undefined ? '' : fx(n.stride, 3));
      set('slip-calc', n.slip === undefined ? '' : fx(n.slip, 3)); set('slip-calc-pct', n.slipPct === undefined ? '' : fx(n.slipPct, 1));
      set('g-toe', n.g === undefined || n.g === null ? '' : fx(n.g, 4)); set('r0', n.r0 === undefined ? '' : fx(n.r0, 3));
      set('slip-measured', meas && meas.rms !== null ? fx(meas.rms, 3) : ''); set('stance-samples', meas ? meas.samples : '');
      set('px1080', cells[k] && cells[k].px ? fx(cells[k].px, 1) : '');
      if (cells[k] && cells[k].ok) {
        const pk = c.src + ':' + c.clip;
        if (cells[k].playing !== pk) { playClip(cells[k], c); cells[k].playing = pk; }
      }
    }
    root.setAttribute('data-v', fx(state.v, 2)); root.setAttribute('data-cam', state.cam);
    root.setAttribute('data-base-speed', gameSpeed() === null ? '' : gameSpeed());
    root.setAttribute('data-camera-size', detail.game.camera.size === null ? '' : detail.game.camera.size);
    root.setAttribute('data-toe-bones', rig ? [rig.toeL && rig.toeL.name, rig.toeR && rig.toeR.name].filter(Boolean).join(',') : '');
    root.setAttribute('data-facing-yaw-deg', rig ? fx(rig.yaw * 180 / Math.PI, 1) : '');
    root.setAttribute('data-selfcheck', selfcheck() ? 'ok' : 'mismatch');
    $('#ch-v').value = state.v; $('#ch-v-out').textContent = fx(state.v, 1);
    const gs = gameSpeed();
    $('#ch-v-note').textContent = gs === null ? '게임의 이동 속도를 읽지 못했습니다: ' + detail.game.base_speed.error
      : Math.abs(state.v - gs) < 0.05 ? `게임 값 ${gs} m/s (${detail.game.base_speed.source} ${detail.game.base_speed.line}줄)`
      : `코어 값(${gs} m/s)과 다름 — 제안으로만 저장됩니다. 이동 속도는 전투 균형이라 이 화면에서 게임에 적용되지 않습니다.`;
    document.querySelectorAll('#ch-cams button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.cam === state.cam)));
    $('#ch-look').setAttribute('aria-pressed', String(state.look)); $('#ch-px').setAttribute('aria-pressed', String(state.px));
    writeHash();
  }
  function measureSafe(c, v) { try { return measure(c, v); } catch (e) { console.warn('측정 실패', e); return null; } }
  function scheduleRefresh() { if (pendingRefresh) return; pendingRefresh = true; requestAnimationFrame(() => { pendingRefresh = false; refresh(); }); }

  // ---------------------------------------------------------------- 그리기 루프
  function frame(now) {
    raf = requestAnimationFrame(frame);
    const dt = Math.min(0.1, (now - (last || now)) / 1000); last = now;
    for (const k of ['a', 'b']) {
      const cell = cells[k];
      if (!cell || !cell.ok) continue;
      const rate = rateOf(state[k]);
      if (cell.mixer) { cell.mixer.update(dt * rate); }
      cell.floor.tex.offset.y -= state.v * dt / 2;
      const d = cell.dots, v3 = new T.Vector3();
      for (let i = 0; i < DOTS; i++) {
        d.age[i] += dt;
        if (d.age[i] > DOT_LIFE) { d.pos[i * 3 + 1] = -1000; continue; }
        d.pos[i * 3 + 2] -= state.v * dt;
        const f = 1 - d.age[i] / DOT_LIFE;
        d.col[i * 3] = d.tint[i * 3] * f; d.col[i * 3 + 1] = d.tint[i * 3 + 1] * f; d.col[i * 3 + 2] = d.tint[i * 3 + 2] * f;
      }
      if (cell.toeL && cell.meas && cell.meas.ymin !== undefined) {
        cell.holder.updateMatrixWorld(true);
        [[cell.toeL, [1, 0.75, 0.35]], [cell.toeR, [0.45, 0.75, 1]]].forEach(([b, tint]) => {
          b.getWorldPosition(v3);
          if (v3.y <= cell.meas.ymin + STANCE_MARGIN + 1e-4) {
            const i = d.next; d.next = (d.next + 1) % DOTS;
            d.pos[i * 3] = v3.x; d.pos[i * 3 + 1] = 0.02; d.pos[i * 3 + 2] = v3.z; d.age[i] = 0; d.tint.set(tint, i * 3);
          }
        });
      }
      d.pts.geometry.attributes.position.needsUpdate = true; d.pts.geometry.attributes.color.needsUpdate = true;
      if (cell.controls) cell.controls.update();
      cell.renderer.render(cell.scene, cell.camera);
    }
    frames++;
    if (frames === 3) markReady();
  }
  function markReady() {
    const root = $('#character');
    root.setAttribute('data-webgl', webgl ? '1' : '0');
    root.setAttribute('data-overflow-x', String(root.scrollWidth > root.clientWidth + 1 || document.documentElement.scrollWidth > document.documentElement.clientWidth + 1));
    root.setAttribute('data-view-w', String(document.documentElement.clientWidth));
    root.setAttribute('data-ready', '1');
  }
  function startLoop() { if (!raf) { last = 0; raf = requestAnimationFrame(frame); } }
  function stopLoop() { if (raf) { cancelAnimationFrame(raf); raf = 0; } }

  // ---------------------------------------------------------------- 고름 저장
  function recordsHtml() {
    const rows = Object.entries((picks && picks.records) || {}).filter(([, r]) => r.subject === detail.subject).sort((a, b) => (b[1].created || '').localeCompare(a[1].created || ''));
    if (!rows.length) return '<li class="bl-help">아직 기록이 없습니다.</li>';
    const L = {pick: '이걸로', reject: '아님', hold: '보류', note: '말만'};
    return rows.slice(0, 12).map(([id, r]) => { const v = r.values || {}; return `<li><span class="ch-badge">${esc(L[r.verdict] || r.verdict)}</span><span class="ch-badge">${r.status === 'open' ? '열림' : '닫힘'}</span>${esc(v.clip || '')} ${v.rate !== undefined ? '× ' + esc(fx(v.rate, 3)) : ''} · 속도 ${esc(v.speed_seen ?? '')} · ${esc(r.created)}${r.note ? ' · “' + esc(r.note) + '”' : ''}<br><small class="bl-help">${esc(id)}</small></li>`; }).join('');
  }
  function valuesFor(key) {
    const c = state[key], n = cellNumbers(key), gs = gameSpeed();
    if (!n.info) return null;
    const meas = cells[key] && cells[key].meas;
    const vals = {line: lineId, slot: detail.slot, clip: c.clip, clip_source: c.src, rate: Number(n.rate.toFixed(4)), speed_seen: Number(state.v.toFixed(2)),
      speed_game: gs, L: Number(n.L.toFixed(5)), stride_world_m: Number(n.stride.toFixed(3)),
      slip_calc_mps: n.slip === undefined ? null : Number(n.slip.toFixed(3)),
      slip_measured_mps: meas && meas.rms !== null ? Number(meas.rms.toFixed(3)) : null,
      camera: state.cam === 'game' ? detail.game.camera.size : state.cam === 'cand' ? detail.game.camera.size_candidate : 'free', look: state.look};
    if (gs !== null) vals.contract_now = Number(strideFor(gs, n.L, n.rate).toFixed(3));
    if (gs !== null && Math.abs(state.v - gs) >= 0.05) vals.contract_if_speed = Number(strideFor(state.v, n.L, n.rate).toFixed(3));
    return vals;
  }
  async function savePicks() {
    if (saving) return;
    const msg = $('#ch-save-msg'), btn = $('#ch-save');
    const todo = [];
    for (const k of ['a', 'b']) {
      const verdict = (document.querySelector(`input[name="ch-verdict-${k}"]:checked`) || {}).value || '';
      const note = $('#ch-note-in-' + k).value.trim();
      if (!verdict && !note) continue;
      const values = valuesFor(k);
      if (!values && verdict) { msg.textContent = '칸 ' + k.toUpperCase() + '의 클립을 읽지 못해 저장하지 않았습니다.'; return; }
      const gs = gameSpeed(), proposals = [];
      if (values && gs !== null && Math.abs(state.v - gs) >= 0.05) {
        proposals.push({to: 'design-lead', what: 'hero BASE_SPEED', value: Number(state.v.toFixed(2)), why: `화면에서 본 이동 속도(게임 ${gs} m/s). ${values.clip} × ${values.rate}에서 계산 미끄러짐 ${values.slip_calc_mps} m/s`});
      }
      todo.push({screen: 'character', subject: detail.subject, verdict: verdict || 'note', note: (k === 'a' ? '[칸 A] ' : '[칸 B] ') + note, values: values || {}, proposals});
    }
    if (!todo.length) { msg.textContent = '판정을 고르거나 한 줄 말을 적으세요.'; return; }
    saving = true; btn.disabled = true; msg.textContent = '저장 중…';
    try {
      let ids = [];
      for (const record of todo) {
        picks = await call('/api/picks', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({revision: picks.revision, action: 'add', record})});
        ids.push(picks.id);
      }
      msg.textContent = '저장했습니다: ' + ids.join(', ');
    } catch (e) {
      if (e.status === 409) { picks = await call('/api/picks'); msg.textContent = '다른 곳에서 먼저 저장되었습니다. 입력한 것은 그대로 두었으니 다시 저장하면 됩니다.'; }
      else msg.textContent = '저장하지 못했습니다. ' + e.message;
    } finally { saving = false; btn.disabled = false; $('#ch-records').innerHTML = recordsHtml(); }
  }

  // ---------------------------------------------------------------- 열기
  async function openLine(id, q) {
    const gen = ++building;
    stopLoop(); disposeCells(); disposeTripoViewer(); tripoView = ''; tripoWant = (q && q.get('tripo')) || '';
    $('#character').removeAttribute('data-ready');
    $('#character').innerHTML = '<p class="empty">캐릭터를 읽는 중…</p>';
    try {
      lineId = id;
      detail = await call('/api/characters/' + encodeURIComponent(id));
      if (gen !== building) return;
      loadError = '';
      state = defaultState(q);
      let threeOk = true;
      try { await loadThree(); } catch (e) { threeOk = false; loadError = '3D 묶음을 불러오지 못했습니다: ' + e.message; }
      if (threeOk) { try { await loadGlbs(); } catch (e) { loadError += ' 몸 파일을 불러오지 못했습니다: ' + e.message; gltfs = {}; } }
      if (gen !== building) return;
      for (const k of ['a', 'b']) { const names = clipNames(state[k].src); if (names.length && !names.includes(state[k].clip)) state[k].clip = names.includes(k === 'a' ? runClip() : 'walk') ? (k === 'a' ? runClip() : 'walk') : names[0]; }
      buildScreen();
      const warn = detail.warnings.concat(loadError ? [loadError] : []);
      $('#ch-warn').innerHTML = warn.map(w => `<p class="alert warn">${esc(w)}</p>`).join('');
      if (threeOk && gltfs.body) {
        buildRig();
        if (rig && (!rig.toeL || !rig.toeR)) $('#ch-warn').insertAdjacentHTML('beforeend', `<p class="alert warn">발끝 뼈(LeftToeBase, RightToeBase)를 찾지 못해 측정 미끄러짐을 잴 수 없습니다. 몸의 뼈 이름: ${esc(rig.boneNames.slice(0, 40).join(', '))}</p>`);
        buildCell('a'); buildCell('b');
      } else {
        for (const k of ['a', 'b']) { $('#ch-note-' + k).textContent = '3D 없이 계산만 보입니다.'; cells[k] = {key: k, ok: false}; }
      }
      document.querySelectorAll('[data-k]').forEach(el => el.removeAttribute('data-bound'));
      applyLook();
      refresh();
      $('#ch-records').innerHTML = recordsHtml();
      writeHash();
      if (webgl) startLoop(); else markReady();
    } catch (e) {
      $('#character').innerHTML = `<h2>캐릭터</h2><p class="alert warn">캐릭터를 열지 못했습니다. ${esc(e.message)}</p>`;
      $('#character').setAttribute('data-ready', '1');
    }
  }
  function disposeCells() {
    for (const k of Object.keys(cells)) { const c = cells[k]; if (c.ro) c.ro.disconnect(); if (c.controls) c.controls.dispose(); if (c.renderer) { c.renderer.dispose(); } }
    cells = {}; webgl = false; frames = 0; rig = null;
  }

  async function show(on) {
    open = on;
    document.body.classList.toggle('character-mode', on);
    $('#character').hidden = !on;
    $('#open-character').classList.toggle('active', on);
    if (!on) { stopLoop(); disposeTripoViewer(); return; }
    document.dispatchEvent(new CustomEvent('view-open', {detail: 'character'}));
    document.querySelectorAll('[data-category],[data-all]').forEach(b => b.classList.remove('active'));
    if (detail && lines) { startLoop(); return; }
    $('#character').innerHTML = '<p class="empty">캐릭터 목록을 읽는 중…</p>';
    try {
      [lines, picks] = await Promise.all([call('/api/characters'), call('/api/picks')]);
    } catch (e) { $('#character').innerHTML = `<p class="empty">캐릭터 목록을 열지 못했습니다. ${esc(e.message)}</p>`; return; }
    const h = parseHash();
    const first = lines.lines.find(l => l.has_body);
    const id = (h && h.id && lines.lines.some(l => l.id === h.id && l.has_body)) ? h.id : (first && first.id);
    if (!id) { $('#character').innerHTML = '<h2>캐릭터</h2><p class="empty">몸 파일이 있는 캐릭터 줄이 없습니다. 주인공 몸은 저장소에 올라가지 않아 이 작업 폴더에 없을 수 있습니다.</p>'; $('#character').setAttribute('data-ready', '1'); return; }
    await openLine(id, h && h.id === id ? h.q : null);
  }

  // ---------------------------------------------------------------- 입력
  document.addEventListener('view-open', ev => { if (ev.detail !== 'character' && open) show(false); });
  document.addEventListener('click', ev => {
    const t = ev.target;
    if (t.closest('#open-character')) return show(true);
    if (!open) return;
    if (t.closest('[data-category],[data-all]')) return show(false);
    const tr = t.closest('[data-tripo]');
    if (tr) return tripoClick(tr);
    const act = t.closest('[data-act]');
    if (act) {
      const k = act.dataset.k, c = state[k], n = cellNumbers(k);
      if (act.dataset.act === 'noslip' && n.r0 !== undefined) c.rate = Math.min(RATE_MAX, Math.max(RATE_MIN, Number(n.r0.toFixed(3))));
      if (act.dataset.act === 'game') { c.src = 'body'; c.clip = runClip(); c.rate = detail.rate_now ? Number(detail.rate_now.toFixed(4)) : null; fillClipSelect(k); }
      refresh(); return;
    }
    const cam = t.closest('#ch-cams button');
    if (cam && !cam.disabled) { state.cam = cam.dataset.cam; for (const k of ['a', 'b']) if (cells[k] && cells[k].ok) setCamera(cells[k]); refresh(); return; }
    if (t.closest('#ch-look')) { state.look = !state.look; applyLook(); rebuildLights(); refresh(); return; }
    if (t.closest('#ch-px')) { state.px = !state.px; refresh(); return; }
    if (t.closest('#ch-v-game')) { if (gameSpeed() !== null) { state.v = gameSpeed(); refresh(); } return; }
    if (t.closest('#ch-save')) return savePicks();
    if (t.closest('#ch-copy')) {
      const url = $('#ch-url').value, msg = $('#ch-copy-msg');
      (navigator.clipboard ? navigator.clipboard.writeText(url) : Promise.reject()).then(() => { msg.textContent = '복사했습니다.'; }, () => { $('#ch-url').select(); msg.textContent = '선택했습니다. 직접 복사하세요(Ctrl+C).'; });
    }
  });
  function fillClipSelect(k) {
    const sel = document.querySelector(`select[data-k="${k}"][data-f="clip"]`), src = document.querySelector(`select[data-k="${k}"][data-f="src"]`);
    if (src) src.value = state[k].src;
    if (sel) sel.innerHTML = clipNames(state[k].src).map(n => `<option ${state[k].clip === n ? 'selected' : ''}>${esc(n)}</option>`).join('');
  }
  function rebuildLights() {
    for (const k of ['a', 'b']) {
      const cell = cells[k]; if (!cell || !cell.ok) continue;
      cell.scene.children.filter(o => o.isLight).forEach(o => cell.scene.remove(o));
      lightRig(cell.scene);
    }
  }
  document.addEventListener('input', ev => {
    if (!open) return;
    const t = ev.target;
    if (t.id === 'ch-v') { state.v = Number(t.value); scheduleRefresh(); return; }
    if (t.dataset && t.dataset.f === 'rate') { state[t.dataset.k].rate = Number(t.value); scheduleRefresh(); }
  });
  document.addEventListener('change', ev => {
    if (!open) return;
    const t = ev.target;
    if (t.id === 'ch-line') { openLine(t.value, null); return; }
    if (t.id === 'ch-tripo-file') { const f = t.files && t.files[0]; t.value = ''; uploadGlb(f); return; }
    if (t.dataset && t.dataset.f === 'src') { const k = t.dataset.k; state[k].src = t.value; state[k].rate = null; const names = clipNames(t.value); if (!names.includes(state[k].clip)) state[k].clip = names[0]; fillClipSelect(k); refresh(); return; }
    if (t.dataset && t.dataset.f === 'clip') { const k = t.dataset.k; state[k].clip = t.value; state[k].rate = null; refresh(); }
  });
  document.addEventListener('dragover', ev => { if (open && ev.target.closest && ev.target.closest('#ch-drop')) { ev.preventDefault(); $('#ch-drop').classList.add('over'); } });
  document.addEventListener('dragleave', ev => { const d = $('#ch-drop'); if (d) d.classList.remove('over'); });
  document.addEventListener('drop', ev => {
    if (!open || !ev.target.closest || !ev.target.closest('#ch-drop')) return;
    ev.preventDefault(); $('#ch-drop').classList.remove('over');
    uploadGlb(ev.dataTransfer && ev.dataTransfer.files && ev.dataTransfer.files[0]);
  });
  window.addEventListener('hashchange', () => {
    const h = parseHash();
    if (!h) return;
    if (!open) return show(true);
    if (lines && h.id && lines.lines.some(l => l.id === h.id && l.has_body)) openLine(h.id, h.q);
  });
  if (parseHash()) show(true);
})();
