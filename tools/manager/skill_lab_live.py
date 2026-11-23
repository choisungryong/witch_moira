#!/usr/bin/env python3
"""스킬 시험실을 실제로 끝까지 돌려 보는 도구: 떠 있는 관리 서버(HTTP)를 통해 실제 Godot 시험 창을 열고, 장면을 바꾸고, 소리 후보를 끼우고,
화면을 저장하고, 영상을 찍는다. 가짜 서버·가짜 창이 아니다(검사 묶음에 넣지 않는다: GPU 창이 뜨고 몇 분 걸린다).

사용(서버를 먼저 띄운다: python tools/manager/server.py --port 8793):
  python tools/manager/skill_lab_live.py --port 8793 [--shots _local/shots/skill-lab-live] [--clip] [--no-close]
단계마다 한 줄 `LAB_LIVE {...}` 를 찍고, 마지막에 `LAB_LIVE_DONE {"pass": ..}`. 창은 끝나면 닫는다(--no-close 가 없으면).
채택·취소는 이 도구가 하지 않는다(저장소 파일을 고치므로). 임시 저장소를 --root 로 쓰는 서버에서 skill_lab_adopt_check 를 쓴다(--adopt 단계).
"""
import argparse, json, sys, time, urllib.error, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class Api:
    def __init__(self, port):
        self.base = 'http://127.0.0.1:%d' % port
        self.origin = self.base

    def call(self, method, path, body=None, timeout=60):
        data = json.dumps(body or {}).encode('utf-8') if method == 'POST' else None
        req = urllib.request.Request(self.base + path, data=data, method=method)
        if data is not None:
            req.add_header('Content-Type', 'application/json')
            req.add_header('Origin', self.origin)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                raw = r.read()
                status = r.status
        except urllib.error.HTTPError as e:
            raw, status = e.read(), e.code
        try:
            return status, json.loads(raw)
        except ValueError:
            return status, raw


def log(step, **kw):
    print('LAB_LIVE ' + json.dumps(dict(step=step, **kw), ensure_ascii=False), flush=True)


def wait_for(fn, seconds, what, every=0.5):
    t0 = time.time()
    while time.time() - t0 < seconds:
        v = fn()
        if v:
            return v
        time.sleep(every)
    raise TimeoutError('%s (%.0f초 안에 안 됨)' % (what, seconds))


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', type=int, required=True)
    ap.add_argument('--shots', default='_local/shots/skill-lab-live')
    ap.add_argument('--clip', action='store_true', help='영상도 한 편 찍는다(20~40초)')
    ap.add_argument('--no-close', action='store_true')
    ap.add_argument('--candidate', default='chain-lightning/round2/C7', help='끼울 후보 id(번개 시전 자리의 것)')
    a = ap.parse_args(argv)
    api = Api(a.port)
    fails = []

    def check(ok, what, **kw):
        log('check', ok=bool(ok), what=what, **kw)
        if not ok:
            fails.append(what)
        return ok

    st, ov = api.call('GET', '/api/skill-lab')
    check(st == 200 and ov['characters'], 'overview', characters=len(ov.get('characters', [])), candidates=len(ov.get('candidates', [])),
          slots=len(ov.get('slots', {}).get('rows', [])), warnings=ov.get('warnings'))
    if fails:
        return finish(fails)
    arc = next(c for c in ov['characters'] if c['elem'] == 'arc')
    scene = {'character': arc['id'], 'skill': arc['primary'], 'form': 'base', 'layout': 'pack', 'count': 6, 'motion': 'hold', 'durable': True, 'repeat': True, 'interval_s': 3.0, 'speed': 1.0, 'juice': True}
    cand = next((c for c in ov['candidates'] if c['id'] == a.candidate), None)
    check(cand is not None, 'candidate listed: ' + a.candidate)
    audio = {cand['slot']: cand['id']} if cand else {}

    st, r = api.call('POST', '/api/skill-lab/open', {'scene': scene, 'audio': {}})
    log('open', status=st, launched=r.get('launched') if isinstance(r, dict) else None)
    check(st == 200, 'open accepted')

    def window():
        s, o = api.call('GET', '/api/skill-lab')
        w = o['window']
        return o if w['status'] == 'connected' and (w['state'] or {}).get('ready') else None
    t0 = time.time()
    try:
        o = wait_for(window, 90, 'window connected and ready')
    except TimeoutError as e:
        check(False, str(e))
        return finish(fails)
    log('connected', seconds=round(time.time() - t0, 1))

    def applied(seq, secs=20):
        def f():
            s, o = api.call('GET', '/api/skill-lab')
            stt = o['window']['state'] or {}
            return stt if stt.get('applied_seq', 0) >= seq else None
        return wait_for(f, secs, 'applied_seq >= %d' % seq)

    # 장면 바꾸기: 창이 따라 바뀌는지는 창이 쓴 state.json 의 scene 으로 본다(페이지가 보낸 값이 아니라 창이 적용한 값)
    steps = [
        ('layout line', dict(layout='line', count=5)),
        ('speed 0.5', dict(speed=0.5)),
        ('repeat off', dict(repeat=False)),
        ('motion approach, juice off', dict(motion='approach', juice=False)),
        ('back to normal', dict(layout='pack', count=6, speed=1.0, repeat=True, juice=True, motion='hold')),
    ]
    for name, change in steps:
        sc = dict(scene, **change)
        st, r = api.call('POST', '/api/skill-lab/scene', {'scene': sc, 'audio': {}})
        seq = r.get('seq', 0) if st == 200 else 0
        try:
            stt = applied(seq)
            got = stt.get('scene', {})
            ok = all(got.get(k) == v for k, v in change.items())
            check(ok, 'scene follows: ' + name, applied_seq=stt.get('applied_seq'), wanted=change, got={k: got.get(k) for k in change}, errors=stt.get('errors'))
        except TimeoutError as e:
            check(False, 'scene follows: %s (%s)' % (name, e))
    # 소리 후보 끼우기
    if cand:
        st, r = api.call('POST', '/api/skill-lab/scene', {'scene': scene, 'audio': audio})
        check(st == 200, 'fit accepted', status=st)
        stt = applied(r.get('seq', 0))
        want = ((stt.get('audio') or {}).get('overrides') or {}).get(cand['slot'])
        check(want == cand['paths'], 'state.audio.overrides has the slot with the candidate files', overrides=want, load_errors=(stt.get('audio') or {}).get('load_errors'))
        st, r = api.call('POST', '/api/skill-lab/cast')
        try:
            rows = wait_for(lambda: [x for x in ((api.call('GET', '/api/skill-lab')[1]['window']['state'] or {}).get('audio') or {}).get('recent', []) if x.get('slot') == cand['slot']], 30, 'audio.recent for the slot')
            paths = sorted({x['path'].replace('\\', '/').split('/')[-1] for x in rows})
            check(all(any(p.endswith(n) for n in [Path(q).name for q in cand['paths']]) for p in paths), 'the window played the candidate files', played=paths)
        except TimeoutError as e:
            check(False, 'the window played the candidate files (%s)' % e)
        s2, o2 = api.call('GET', '/api/skill-lab')
        check(o2['window']['override_ids'].get(cand['slot']) == cand['id'], 'page sees the candidate in the window', override_ids=o2['window']['override_ids'])
    # 화면 저장
    Path(ROOT / a.shots).mkdir(parents=True, exist_ok=True)
    st, r = api.call('POST', '/api/skill-lab/shot', {'name': 'live-window'})
    check(st == 200, 'shot accepted', status=st, path=r.get('path') if isinstance(r, dict) else None)
    try:
        wait_for(lambda: (api.call('GET', '/api/skill-lab')[1]['window']['state'] or {}).get('last_shot'), 20, 'last_shot')
        s3, img = api.call('GET', '/api/skill-lab/shot?name=live-window')
        ok = s3 == 200 and isinstance(img, bytes) and img[:4] == b'\x89PNG'
        if ok:
            (ROOT / a.shots / 'window-live.png').write_bytes(img)
        check(ok, 'shot served as png', bytes=len(img) if isinstance(img, bytes) else None)
    except TimeoutError as e:
        check(False, str(e))
    # 영상
    if a.clip:
        t1 = time.time()
        st, job = api.call('POST', '/api/skill-lab/clip', {'scene': dict(scene, layout='pack', count=8, motion='approach', durable=False), 'audio': audio, 'way': 'movie'})
        check(st == 200, 'clip accepted', status=st, state=job.get('state') if isinstance(job, dict) else None)
        if st == 200:
            def done():
                s, j = api.call('GET', '/api/skill-lab/clip/' + job['id'])
                return j if s == 200 and j.get('state') in ('done', 'error') else None
            try:
                j = wait_for(done, 240, 'clip finished', every=2)
                check(j['state'] == 'done', 'clip done', seconds_total=round(time.time() - t1, 1), job_seconds=j.get('seconds'), size=j.get('size'), error=j.get('error'))
                if j['state'] == 'done':
                    req = urllib.request.Request(api.base + j['video'], headers={'Range': 'bytes=0-99'})
                    with urllib.request.urlopen(req, timeout=20) as rr:
                        check(rr.status == 206 and rr.headers.get('Content-Range', '').startswith('bytes 0-99/'), 'clip Range 206', content_range=rr.headers.get('Content-Range'))
                    log('clip', id=job['id'], path='_local/skill-lab/clips/%s.mp4' % job['id'])
            except TimeoutError as e:
                check(False, str(e))
    if not a.no_close:
        api.call('POST', '/api/skill-lab/close')
        try:
            wait_for(lambda: api.call('GET', '/api/skill-lab')[1]['window']['status'] != 'connected', 20, 'window closed')
            log('closed')
        except TimeoutError as e:
            check(False, str(e))
    return finish(fails)


def finish(fails):
    print('LAB_LIVE_DONE ' + json.dumps({'pass': not fails, 'fails': fails}, ensure_ascii=False), flush=True)
    return 0 if not fails else 1


if __name__ == '__main__':
    sys.exit(main())
