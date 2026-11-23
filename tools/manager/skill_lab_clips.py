"""「스킬 시험실」의 영상: 장면을 소리가 든 짧은 mp4 로 찍어 캐시하고, 대기열(하나씩, 최대 5)과 낡음 표시를 맡는다.

명세: docs/specs/T12-skill-lab-20261123.ko.md 9.3절. 영상 id = 열쇠(장면 + 끼운 소리 파일들의 sha256 + 찍는 길)와 "판의 판"(데이터·표현·코어·시험 장면 파일의 sha256)을
함께 해시한 24자. 같은 id 는 다시 찍지 않는다. 판이 바뀌면 id 가 달라져 옛 영상은 지워지지 않고 「낡음」으로 보인다.
둘 곳: _local/skill-lab/clips/<id>.mp4 + <id>.json (열쇠, 판, 찍은 시각, 길, 걸린 시간, 크기). 상한 2 GB, 넘으면 오래 안 쓴 것부터 지운다.

실제로 찍는 방식은 SL-B 의 실측 뒤에 정해진다. 그래서 찍는 명령은 하나의 함수(shoot_godot_movie) 뒤에 있고 검사는 가짜 함수로 돈다.
shoot_godot_movie 는 (ㄱ) Movie Maker 의 명세 명령을 그대로 쓴 것이며 실제 Godot 로는 시험하지 않았다(시험 창 스크립트가 아직 없음).
"""
import hashlib, json, os, re, shutil, subprocess, sys, threading, time
from pathlib import Path

try:
    from .catalog import ROOT
    from . import skill_lab
except ImportError:
    from catalog import ROOT
    import skill_lab

MAX_QUEUE = 5
MAX_BYTES = 2 * 1024 ** 3
WAYS = ('movie', 'offline')          # (ㄱ) Movie Maker / (ㄴ) 프레임 + 오프라인 섞기
WAY_LABEL = {'movie': '게임 엔진이 낸 소리', 'offline': '모델의 소리(빠른 비교)'}
ID_RE = re.compile(r'^[0-9a-f]{24}$')
WORLD_FILES = ['chapter1/data/audio_map.json', 'chapter1/data/combat_tuning.json', 'chapter1/data/growth_quality37.json', 'chapter1/data/descent.json']
WORLD_GLOBS = ['chapter1/presentation/*.gd', 'chapter1/view/fx/**/*', 'chapter1/view/actors/**/*', 'chapter1/core/**/*',
               'chapter1/tests/skill_lab.gd', 'chapter1/tests/support/skill_lab_*.gd']
_SIG = {}                     # 경로 -> ((mtime_ns, size), sha) : 안 바뀐 파일은 다시 해시하지 않는다
_LOCK = threading.Lock()
_JOBS = {}                    # id -> 상태 사전(메모리)
_QUEUE = []


def clips_dir(root=None):
    return Path(root or ROOT) / '_local' / 'skill-lab' / 'clips'


def _file_hash(p):
    st = p.stat()
    sig = (st.st_mtime_ns, st.st_size)
    hit = _SIG.get(str(p))
    if hit and hit[0] == sig:
        return hit[1]
    h = skill_lab.file_sha(p)
    _SIG[str(p)] = (sig, h)
    return h


def world_hash(root=None):
    """판의 판: 위 파일들의 (상대 경로, sha256)을 정렬해 해시."""
    root = Path(root or ROOT)
    files = {root / f for f in WORLD_FILES}
    for g in WORLD_GLOBS:
        files.update(p for p in root.glob(g) if p.is_file())
    h = hashlib.sha256()
    for p in sorted(f for f in files if f.is_file()):
        h.update(p.relative_to(root).as_posix().encode('utf-8') + b'\0' + _file_hash(p).encode('ascii') + b'\n')
    return h.hexdigest()


def clip_id(scene, audio_shas, way, world):
    key = json.dumps({'scene': scene, 'audio': audio_shas, 'way': way}, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256((key + '|' + world).encode('utf-8')).hexdigest()[:24]


def _audio_shas(root, audio):
    return {slot: [skill_lab.file_sha(Path(root) / p) for p in paths] for slot, paths in sorted(audio.items())}


def _meta_path(root, cid):
    return clips_dir(root) / (cid + '.json')


def _video_path(root, cid):
    return clips_dir(root) / (cid + '.mp4')


def read_meta(root, cid):
    try:
        d = json.loads(_meta_path(root, cid).read_text(encoding='utf-8'))
        return d if isinstance(d, dict) else None
    except (OSError, ValueError):
        return None


def _public(root, cid, meta, world):
    return {'id': cid, 'state': 'done', 'scene': meta.get('scene'), 'way': meta.get('way'), 'way_label': WAY_LABEL.get(meta.get('way'), ''),
            'made_at': meta.get('made_at'), 'seconds': meta.get('seconds'), 'size': meta.get('size'), 'audio_overrides': meta.get('audio_overrides', {}),
            'stale': meta.get('world') != world, 'stale_reason': '' if meta.get('world') == world else '소리 표/효과·코드 파일이 찍은 뒤에 바뀌었습니다(낡음)',
            'video': '/api/skill-lab/clip/%s/video' % cid}


def status(root, cid):
    """작업 id 의 상태. 메모리의 작업 -> 디스크의 영상 순. 없으면 None."""
    root = Path(root)
    if not isinstance(cid, str) or not ID_RE.match(cid):
        return None
    with _LOCK:
        job = _JOBS.get(cid)
        j = dict(job) if job and job['state'] in ('queued', 'running', 'error') else None
    if j is not None:
        if j['state'] == 'running':
            j['elapsed_s'] = round(time.time() - j['started'], 1)
        if j['state'] in ('queued', 'running'):
            j.update(wait_info(root, cid))
        return j
    meta = read_meta(root, cid)
    if meta and _video_path(root, cid).is_file():
        return _public(root, cid, meta, world_hash(root))
    return None


def typical_seconds(root):
    """최근에 찍은 영상들의 걸린 시간 중앙값(없으면 None). 화면의 '보통 n초' 안내에 쓴다 - 이 PC 에서 잰 값일 뿐 약속이 아니다."""
    d = clips_dir(root)
    secs = []
    if d.is_dir():
        metas = sorted(d.glob('*.json'), key=lambda p: p.stat().st_mtime, reverse=True)[:12]
        for p in metas:
            m = read_meta(root, p.stem) if ID_RE.match(p.stem) else None
            if m and isinstance(m.get('seconds'), (int, float)):
                secs.append(float(m['seconds']))
    return round(sorted(secs)[len(secs) // 2], 1) if secs else None


def wait_info(root, cid):
    """대기 중이면 앞에 몇 개, 예상 시간(걸린 시간 중앙값 x (앞의 개수 + 1)). 실측이 없으면 숫자 없이 안내만."""
    with _LOCK:
        ahead = sum(1 for j in _JOBS.values() if j['state'] in ('queued', 'running') and j.get('queued', 0) < _JOBS.get(cid, {}).get('queued', 0))
    typ = typical_seconds(root)
    return {'ahead': ahead, 'typical_s': typ, 'eta_s': round(typ * (ahead + 1), 0) if typ else None}


def listing(root=None):
    root = Path(root or ROOT)
    d = clips_dir(root)
    world = world_hash(root)
    done = []
    if d.is_dir():
        for p in d.glob('*.json'):
            if ID_RE.match(p.stem) and _video_path(root, p.stem).is_file():
                m = read_meta(root, p.stem)
                if m:
                    done.append(_public(root, p.stem, m, world))
    done.sort(key=lambda c: c.get('made_at') or '', reverse=True)
    with _LOCK:
        active = [dict(j) for j in _JOBS.values() if j['state'] in ('queued', 'running', 'error')]
    return {'clips': done, 'jobs': active, 'queue_max': MAX_QUEUE, 'world': world,
            'bytes': sum(c.get('size') or 0 for c in done), 'limit_bytes': MAX_BYTES}


def prune(root, keep=()):
    """상한을 넘으면 오래 안 쓴 영상(mp4 의 mtime)부터 지운다. 지운 id 목록."""
    d = clips_dir(root)
    vids = [(p.stat().st_mtime, p) for p in d.glob('*.mp4') if p.stem not in keep] if d.is_dir() else []
    total = sum(p.stat().st_size for p in d.glob('*.mp4')) if d.is_dir() else 0
    removed = []
    for _, p in sorted(vids):
        if total <= MAX_BYTES:
            break
        total -= p.stat().st_size
        for q in (p, p.with_suffix('.json')):
            try:
                q.unlink()
            except OSError:
                pass
        removed.append(p.stem)
    return removed


def touch(root, cid):
    """재생한 영상을 '최근 쓴 것'으로(상한 정리가 오래 안 쓴 것부터 지우도록)."""
    try:
        os.utime(_video_path(root, cid), None)
    except OSError:
        pass


def video_file(root, cid):
    if not isinstance(cid, str) or not ID_RE.match(cid):
        return None
    p = _video_path(root, cid)
    return p if p.is_file() and _meta_path(root, cid).is_file() else None


# ------------------------------------------------------------------ 찍기(한 함수 뒤)
def _ffmpeg():
    return shutil.which('ffmpeg')


def shoot_godot_movie(root, scene, audio, way, cid, out_mp4):
    """(ㄱ) 명세 9.3의 명령으로 새 Godot 프로세스를 띄워 avi 를 얻고 ffmpeg 로 mp4(H.264+AAC)로 바꾼다. 반환: 메타에 더할 사전.
    (ㄴ) offline 은 아직 연결되지 않았다. 실제 Godot 로 시험하지 않은 코드다."""
    root = Path(root)
    if way != 'movie':
        raise RuntimeError('이 찍는 길(%s)은 아직 연결되지 않았습니다.' % way)
    if not (root / 'chapter1/tests/skill_lab.gd').is_file():
        raise RuntimeError('시험 창 스크립트(chapter1/tests/skill_lab.gd)가 없습니다.')
    ff = _ffmpeg()
    if not ff:
        raise RuntimeError('ffmpeg 를 찾지 못했습니다.')
    tmp = clips_dir(root) / 'tmp'
    tmp.mkdir(parents=True, exist_ok=True)
    scene_rel = '_local/skill-lab/clips/tmp/%s.scene.json' % cid
    (root / scene_rel).write_text(json.dumps({'scene': scene, 'audio': audio}, ensure_ascii=False), encoding='utf-8')
    avi_rel = '_local/skill-lab/clips/tmp/%s.avi' % cid
    # 영상 찍기는 떠 있는 창의 state.json 과 섞이지 않게 자기 lab 폴더를 쓴다(명세의 명령에 --lab-dir 을 더함: 확인 필요)
    # --position: Movie Maker 는 헤드리스가 안 되고 창이 필요하다(SL-B 실측). 화면 밖에 둬서 사용자 화면에 안 뜨게 한다.
    args = [sys.executable, str(root / 'tools/dev/godot.py'), '--timeout-s=120', '--fixed-fps', '60', '--resolution', '1280x720', '--position', '4000,4000', '--write-movie', avi_rel,
            '--path', '.', '--script', 'res://chapter1/tests/skill_lab.gd', '--', '--chapter1-start', '--chapter1-profile-off', '--chapter1-qa-ignore-focus',
            '--chapter1-trial=descent', '--chapter1-descent-cost=1000', '--chapter1-seed=11', '--chapter1-primary=' + scene['skill'],
            '--lab-clip=' + scene_rel, '--lab-clip-seconds=4', '--lab-dir=_local/skill-lab/clips/tmp/lab-' + cid]
    env = dict(os.environ, PYTHONUTF8='1', PYTHONIOENCODING='utf-8')
    avi = root / avi_rel
    attempts = 0
    while True:
        attempts += 1
        done = subprocess.run(args, cwd=str(root), capture_output=True, timeout=180, env=env)
        if done.returncode == 0 and avi.is_file():
            break
        if attempts >= 2:
            break
        # Godot 가 가끔 시작·종료 때 죽는다(종료 -1 과 C++ 역추적, 같은 장면이 다음에는 됨). 한 번만 더 해 보고, 첫 실패의 출력은 남긴다
        try:
            (clips_dir(root) / 'last-crash.log').write_bytes(done.stdout + b'\n' + done.stderr)
        except OSError:
            pass
        try:
            avi.unlink()
        except OSError:
            pass
        shutil.rmtree(root / ('_local/skill-lab/clips/tmp/lab-' + cid), ignore_errors=True)
    text = (done.stdout + b'\n' + done.stderr).decode('utf-8', 'replace')
    try:      # 실패 때 까닭을 볼 수 있게 마지막 찍기의 전체 출력을 남긴다(다음 찍기가 덮어씀)
        (clips_dir(root) / 'last-shoot.log').write_text(text, encoding='utf-8')
    except OSError:
        pass
    if done.returncode != 0 or not avi.is_file():
        hints = [ln.strip() for ln in text.splitlines() if re.search(r'SCRIPT ERROR|Parse Error|CrashHandler|crashed|Program crashed|Cannot|Failed|refused', ln)][:3]
        raise RuntimeError('Godot 영상 찍기가 실패했습니다(종료 %d). %s (전체 출력: _local/skill-lab/clips/last-shoot.log)' % (done.returncode & 0xffffffff, ' / '.join(hints) or text[-200:].replace('\n', ' ')))
    # 시험 창(skill_lab_node.gd)이 state.json 의 clip 칸에 무대가 선 프레임을 쓴다: {start_frame, start_time_s, frames, seconds, done}
    start_s, clip_info = 0.0, {}
    lab_tmp = root / ('_local/skill-lab/clips/tmp/lab-' + cid)
    try:
        clip_info = json.loads((lab_tmp / 'state.json').read_text(encoding='utf-8')).get('clip') or {}
        start_s = float(clip_info.get('start_time_s', int(clip_info.get('start_frame', 0)) / 60.0))
    except (OSError, ValueError, TypeError):
        pass
    cmd = [ff, '-y', '-v', 'error', '-i', str(avi), '-ss', '%.3f' % start_s, '-t', '4', '-vf', 'fps=30,scale=1280:720', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '27',
           '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart', str(out_mp4)]
    conv = subprocess.run(cmd, capture_output=True, timeout=120)
    for junk in (avi, root / scene_rel):
        try:
            junk.unlink()
        except OSError:
            pass
    shutil.rmtree(lab_tmp, ignore_errors=True)
    if conv.returncode != 0 or not Path(out_mp4).is_file():
        raise RuntimeError('ffmpeg 변환이 실패했습니다: %s' % conv.stderr.decode('utf-8', 'replace')[-300:])
    return {'start_frame': int(clip_info.get('start_frame', 0) or 0), 'start_time_s': start_s, 'attempts': attempts}


SHOOT = {'fn': shoot_godot_movie}       # 검사가 바꿔 끼운다


# ------------------------------------------------------------------ 대기열
def request(root, scene, audio, way='movie', start_worker=True):
    """영상을 부탁한다. 같은 id 가 이미 있으면 그 상태(캐시 적중)를, 아니면 대기열에 넣는다. 가득 차면 LabError(429)."""
    root = Path(root)
    if way not in WAYS:
        raise ValueError('Unknown way')
    chars = skill_lab.characters_table(root)
    scene = skill_lab.clean_scene(scene, chars)
    audio = skill_lab.clean_audio(audio, root)
    world = world_hash(root)
    shas = _audio_shas(root, audio)
    cid = clip_id(scene, shas, way, world)
    hit = status(root, cid)
    if hit and hit['state'] in ('done', 'queued', 'running'):
        hit = dict(hit, cached=hit['state'] == 'done')
        if hit['state'] == 'done':
            touch(root, cid)
        return hit
    with _LOCK:
        busy = sum(1 for j in _JOBS.values() if j['state'] in ('queued', 'running'))
        if busy >= MAX_QUEUE:
            raise skill_lab.LabError(429, 'The clip queue is full (max %d)' % MAX_QUEUE)
        job = {'id': cid, 'state': 'queued', 'scene': scene, 'audio': audio, 'way': way, 'way_label': WAY_LABEL[way], 'world': world,
               'audio_shas': shas, 'queued': time.time(), 'started': None, 'error': ''}
        _JOBS[cid] = job
        _QUEUE.append((str(root), cid))
    if start_worker:
        _kick()
    return {k: v for k, v in job.items() if k != 'audio_shas'}


_WORKER = {'thread': None}


def _kick():
    with _LOCK:
        t = _WORKER['thread']
        if t is not None and t.is_alive():
            return
        t = threading.Thread(target=run_queue, daemon=True)
        _WORKER['thread'] = t
        t.start()


def run_queue():
    """대기열을 비울 때까지 하나씩."""
    while True:
        with _LOCK:
            if not _QUEUE:
                return
            root, cid = _QUEUE.pop(0)
            job = _JOBS[cid]
            job['state'], job['started'] = 'running', time.time()
        run_job(Path(root), cid)


def run_job(root, cid):
    job = _JOBS[cid]
    d = clips_dir(root)
    d.mkdir(parents=True, exist_ok=True)
    out = d / (cid + '.mp4')
    t0 = time.time()
    try:
        extra = SHOOT['fn'](root, job['scene'], job['audio'], job['way'], cid, out) or {}
        if not out.is_file():
            raise RuntimeError('영상 파일이 만들어지지 않았습니다.')
        meta = dict({'id': cid, 'scene': job['scene'], 'audio_overrides': job['audio'], 'audio_shas': job['audio_shas'], 'way': job['way'], 'world': job['world'],
                     'made_at': time.strftime('%Y-%m-%d %H:%M:%S'), 'seconds': round(time.time() - t0, 1), 'size': out.stat().st_size}, **extra)
        tmp = _meta_path(root, cid).with_suffix('.tmp')
        tmp.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        os.replace(tmp, _meta_path(root, cid))
        prune(root, keep=(cid,))
        with _LOCK:
            _JOBS.pop(cid, None)
    except Exception as e:          # 작업 하나의 실패가 서버를 죽이지 않게 한다. 까닭은 화면에 그대로.
        try:
            out.unlink()
        except OSError:
            pass
        with _LOCK:
            job['state'], job['error'] = 'error', str(e) or e.__class__.__name__


def retry(root, cid, start_worker=True):
    """실패한 작업을 지우고 같은 부탁을 다시 넣는다."""
    with _LOCK:
        job = _JOBS.get(cid)
        if not job or job['state'] != 'error':
            raise skill_lab.LabError(404, 'No failed job to retry')
        _JOBS.pop(cid)
    return request(root, job['scene'], job['audio'], job['way'], start_worker=start_worker)
