#!/usr/bin/env python3
"""채택·취소가 페이지의 길(HTTP -> skill_lab.py -> tools/dev/audio_adopt.py)로 실제로 도는지 보는 도구. 임시 저장소 --root 에서만 돈다.

사용: python tools/manager/skill_lab_adopt_check.py --root D:/.../임시-저장소-작업-트리 [--candidate chain-lightning/round2/C7] [--slot skill.arc.cast]
  --root 에는 이 저장소와 같은 파일 구성(chapter1/, tools/dev/audio_adopt.py, _local/audio/<후보 목록>)을 가진 별도 체크아웃을 준다(git worktree add --detach 로 만든 것).
  이 저장소(도구가 들어 있는 곳)를 --root 로 주면 거절한다. 서버는 이 프로세스 안에서 빈 포트로 띄우고, 고름 기록도 임시 파일에만 쓴다(tools/manager/local-picks.json 을 건드리지 않음).
  단계: 미리보기(--dry-run) -> 틀린 rev 로 채택 = 409(도구를 부르지 않음) -> 채택(--yes, 임포트 포함) -> 소리 표·파일 확인 -> 채택 취소 -> 원래대로인지 확인.
마지막 줄 `ADOPT_CHECK {"pass": ..}`. 실제 저장소의 채택은 사용자가 고르는 일이라 이 도구가 하지 않는다.
"""
import argparse, hashlib, json, sys, tempfile, threading
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import server, skill_lab, picks                       # noqa: E402
from skill_lab_live import Api, log                    # noqa: E402

REPO = HERE.parents[1]


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', required=True)
    ap.add_argument('--candidate', default='chain-lightning/round2/C7')
    ap.add_argument('--slot', default='skill.arc.cast')
    a = ap.parse_args(argv)
    root = Path(a.root).resolve()
    if root == REPO or not (root / 'tools/dev/audio_adopt.py').is_file() or not (root / 'chapter1/data/audio_map.json').is_file():
        print('ADOPT_CHECK ' + json.dumps({'pass': False, 'fails': ['--root 는 이 저장소가 아닌 별도 체크아웃이어야 합니다']}, ensure_ascii=False))
        return 2
    fails = []

    def check(ok, what, **kw):
        log('check', ok=bool(ok), what=what, **kw)
        if not ok:
            fails.append(what)
        return ok

    tmp = Path(tempfile.mkdtemp(prefix='adopt-check-'))
    server.ROOT = root
    picks.STORE = tmp / 'picks.json'
    srv = server.make_server(0)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    api = Api(srv.server_port)
    map_path = root / 'chapter1/data/audio_map.json'
    ledger_path = root / 'chapter1/art/audio/AUDIO-LEDGER.json'
    before = {'map': sha(map_path), 'ledger': sha(ledger_path) if ledger_path.is_file() else None}
    try:
        st, ov = api.call('GET', '/api/skill-lab')
        rev0 = ov['map_rev']
        check(st == 200 and rev0 == before['map'] and ov['adopt']['available'], 'overview: adopt available, map_rev = sha256 of audio_map.json', map_rev=rev0[:12])
        cand = next((c for c in ov['candidates'] if c['id'] == a.candidate), None)
        check(cand is not None and cand['slot'] == a.slot, 'candidate listed for the slot')
        row = next((r for r in ov['slots']['rows'] if r['slot'] == a.slot), {})
        log('slot before', current=row.get('current', {}).get('kind'), note=row.get('current', {}).get('note'))

        st, pv = api.call('POST', '/api/skill-lab/adopt-preview', {'slot': a.slot, 'candidate': a.candidate}, timeout=120)
        check(st == 200 and pv.get('confirm') and pv.get('files'), 'preview from the tool (--dry-run)', files=[f['dest_rel'] for f in pv.get('files', [])],
              parent_silent_today=pv.get('parent_silent_today'), warnings=pv.get('warnings'))
        check(sha(map_path) == rev0, 'the preview wrote nothing')

        st, r = api.call('POST', '/api/skill-lab/adopt', {'slot': a.slot, 'candidate': a.candidate, 'map_rev': '0' * 64}, timeout=60)
        check(st == 409 and r.get('map_rev') == rev0, 'wrong rev -> 409 with the new map_rev', status=st)
        check(sha(map_path) == rev0, 'the 409 wrote nothing')

        st, r = api.call('POST', '/api/skill-lab/adopt', {'slot': a.slot, 'candidate': a.candidate, 'map_rev': rev0}, timeout=600)
        res = r.get('result') or {}
        check(st == 200 and res.get('ok'), 'adopt ran through audio_adopt.py', status=st, error=r.get('error') if isinstance(r, dict) else None, output=(r.get('output') or '')[-400:] if isinstance(r, dict) else None)
        if st == 200:
            check(res.get('rev_before') == rev0 and res.get('rev_after') == sha(map_path) != rev0, 'audio_map.json changed (rev_before/rev_after match)')
            check(all((root / f['dest_rel']).is_file() for f in res.get('files', [])) and res.get('files'), 'adopted files exist', files=[f['dest_rel'] for f in res.get('files', [])])
            log('tool checks', checks=res.get('checks'), import_=res.get('import'), git_diff_stat=r.get('git_diff_stat'), pick_warning=r.get('pick_warning'), reload_sent=r.get('reload_sent'))
            check(not r.get('pick_warning'), 'pick recorded without a warning')
            check(r.get('reload_sent') is False, 'no window in this root -> no reload command')
            recs = json.loads((tmp / 'picks.json').read_text(encoding='utf-8'))['records']
            check(any(v.get('verdict') == 'pick' and a.slot in v.get('subject', '') for v in recs.values()), 'picks has the pick (temp file)')
            st2, ov2 = api.call('GET', '/api/skill-lab')
            row2 = next(r_ for r_ in ov2['slots']['rows'] if r_['slot'] == a.slot)
            check(row2['current']['kind'] == 'adopted' and row2['current']['candidate'] == a.candidate, 'page shows the slot as adopted', current=row2['current']['kind'])
            st, r409 = api.call('POST', '/api/skill-lab/adopt', {'slot': a.slot, 'candidate': a.candidate, 'map_rev': rev0}, timeout=60)
            check(st == 409, 'the old rev after an adopt -> 409', status=st)
            st, rv = api.call('POST', '/api/skill-lab/revert', {'slot': a.slot, 'map_rev': ov2['map_rev']}, timeout=300)
            check(st == 200 and (rv.get('result') or {}).get('ok'), 'revert ran through audio_adopt.py', status=st, error=rv.get('error') if isinstance(rv, dict) else None)
            check(sha(map_path) == before['map'], 'audio_map.json is back to the original bytes')
            check((sha(ledger_path) if ledger_path.is_file() else None) == before['ledger'], 'AUDIO-LEDGER.json is back to the original bytes')
            recs = json.loads((tmp / 'picks.json').read_text(encoding='utf-8'))['records']
            check(any(v.get('verdict') == 'hold' for v in recs.values()), 'picks has the hold of the revert (temp file)')
    finally:
        srv.shutdown()
        srv.server_close()
    print('ADOPT_CHECK ' + json.dumps({'pass': not fails, 'fails': fails}, ensure_ascii=False), flush=True)
    return 0 if not fails else 1


if __name__ == '__main__':
    sys.exit(main())
