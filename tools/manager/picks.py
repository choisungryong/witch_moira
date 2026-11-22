#!/usr/bin/env python3
"""사용자의 고름(이걸로/아님/보류/말만)을 tools/manager/local-picks.json 에 모으고, 디렉터가 읽을 수 있게 한다.

기록은 화면에서만 더해진다(POST /api/picks, by 는 서버가 "user"로 채움). 명령줄에는 읽기와 닫기만 있다:
  python tools/manager/picks.py list [--open] [--subject frost/] [--json]
  python tools/manager/picks.py close <id> --ref "<커밋이나 지시서>"
같은 subject 에 기록이 여럿 쌓이고, 마지막 pick 이 그 주제의 답이다. 이 파일은 사용자 기록이라 _local/ 에 두지 않는다(git 밖, move_bundle 이 옮김).
게임 파일은 쓰지 않는다. 고른 값을 자리표로 옮기는 일은 tools/art/motion_apply.py 가 한다.
"""
import argparse, json, os, re, sys, threading, time
from pathlib import Path

STORE = Path(__file__).resolve().parent / 'local-picks.json'
LOCK = threading.Lock()
VERDICTS = {'pick', 'reject', 'hold', 'note'}
SCREENS = {'character', 'skill', 'gear', 'currency', 'enemy'}
VERDICT_LABELS = {'pick': '이걸로', 'reject': '아님', 'hold': '보류', 'note': '말만'}
SUBJECT_RE = re.compile(r'^[A-Za-z0-9_.\-]+(/[A-Za-z0-9_.\-]+)*$')
NOTE_LIMIT = 2000


def load(path=None):
    path = Path(path or STORE)
    if not path.exists():
        return {'revision': 0, 'records': {}}
    value = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(value, dict) or type(value.get('revision')) is not int or not isinstance(value.get('records'), dict):
        raise ValueError('Invalid picks store')
    return value


def write(store, path=None):
    path = Path(path or STORE)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix('.tmp')
    with temp.open('w', encoding='utf-8', newline='\n') as f:
        json.dump(store, f, ensure_ascii=False, indent=2)
        f.write('\n')
        f.flush()
        os.fsync(f.fileno())
    os.replace(temp, path)


def clean_record(rec):
    if not isinstance(rec, dict):
        raise ValueError('record must be an object')
    if rec.get('screen') not in SCREENS:
        raise ValueError('Invalid screen')
    subject = rec.get('subject')
    if (not isinstance(subject, str) or not 0 < len(subject) <= 120 or not SUBJECT_RE.match(subject)
            or any(set(seg) == {'.'} for seg in subject.split('/'))):
        raise ValueError('Invalid subject')
    if rec.get('verdict') not in VERDICTS:
        raise ValueError('Invalid verdict')
    note = rec.get('note', '')
    if not isinstance(note, str) or len(note) > NOTE_LIMIT:
        raise ValueError('Note limit is %d characters' % NOTE_LIMIT)
    values = rec.get('values', {})
    proposals = rec.get('proposals', [])
    if not isinstance(values, dict) or not isinstance(proposals, list) or not all(isinstance(p, dict) for p in proposals):
        raise ValueError('values must be an object and proposals a list of objects')
    if len(proposals) > 10:
        raise ValueError('Too many proposals')
    return {'screen': rec['screen'], 'subject': subject, 'verdict': rec['verdict'], 'note': note, 'values': values, 'proposals': proposals}


def new_id(store, subject):
    slug = re.sub(r'[^A-Za-z0-9]+', '-', subject).strip('-').lower()[:40] or 'x'
    base = 'pk-' + time.strftime('%Y%m%d-%H%M%S') + '-' + slug
    n, pid = 1, base
    while pid in store['records']:
        n += 1
        pid = '%s-%d' % (base, n)
    return pid


def update(payload, path=None):
    """POST /api/picks 의 본체. (상태 코드, 값). revision 이 어긋나면 409 와 최신 값."""
    if not isinstance(payload, dict) or not {'revision', 'action', 'record'} <= set(payload) or set(payload) - {'revision', 'action', 'record', 'id'}:
        raise ValueError('Expected revision, action, record')
    if type(payload['revision']) is not int or payload['revision'] < 0 or payload['action'] not in ('add', 'update'):
        raise ValueError('Invalid revision or action')
    rec = clean_record(payload['record'])
    with LOCK:
        store = load(path)
        if payload['revision'] != store['revision']:
            return 409, store
        if payload['action'] == 'add':
            pid = new_id(store, rec['subject'])
            store['records'][pid] = dict(rec, by='user', created=time.strftime('%Y-%m-%d %H:%M:%S'), status='open', closed_ref='')
        else:
            pid = payload.get('id')
            old = store['records'].get(pid) if isinstance(pid, str) else None
            if old is None:
                raise ValueError('Unknown id')
            if old.get('status') == 'closed':
                raise ValueError('Closed record cannot be changed')
            old.update(rec)
        store['revision'] += 1
        write(store, path)
        out = dict(store)
        out['id'] = pid
        return 200, out


def close(pick_id, ref, path=None):
    ref = (ref or '').strip()
    if not ref:
        raise ValueError('--ref is required')
    with LOCK:
        store = load(path)
        rec = store['records'].get(pick_id)
        if rec is None:
            raise ValueError('Unknown id: %s' % pick_id)
        rec['status'] = 'closed'
        rec['closed_ref'] = ref
        store['revision'] += 1
        write(store, path)
        return store


def listing(store, only_open=False, subject=None):
    rows = []
    for pid, rec in store['records'].items():
        if only_open and rec.get('status') != 'open':
            continue
        if subject and not rec.get('subject', '').startswith(subject):
            continue
        rows.append(dict(rec, id=pid))
    rows.sort(key=lambda r: (r.get('created', ''), r['id']))
    return rows


def answers(store):
    """주제마다 마지막 pick 하나(닫힌 것 포함)."""
    out = {}
    for r in listing(store):
        if r.get('verdict') == 'pick':
            out[r['subject']] = r
    return out


def main(argv=None):
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(errors='replace')     # 콘솔 코드페이지가 못 쓰는 글자가 있어도 목록이 끊기지 않게
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--file', default=None, help='다른 고름 파일(시험용)')
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('list')
    p.add_argument('--open', action='store_true')
    p.add_argument('--subject', default=None)
    p.add_argument('--json', action='store_true')
    c = sub.add_parser('close')
    c.add_argument('id')
    c.add_argument('--ref', required=True)
    a = ap.parse_args(argv)
    try:
        if a.cmd == 'list':
            rows = listing(load(a.file), a.open, a.subject)
            if a.json:
                print(json.dumps(rows, ensure_ascii=False, indent=2))
                return 0
            if not rows:
                print('기록 없음')
                return 0
            for r in rows:
                v = r.get('values') or {}
                bits = [k + '=' + str(v[k]) for k in ('clip', 'rate', 'speed_seen') if k in v]
                print('%s  [%s] %s  %s  %s%s' % (r['id'], r.get('status'), r.get('subject'), VERDICT_LABELS.get(r.get('verdict'), r.get('verdict')),
                                                  ' '.join(bits), ('  "%s"' % r['note']) if r.get('note') else ''))
                for pr in r.get('proposals') or []:
                    print('    제안 -> %s: %s = %s  (%s)' % (pr.get('to'), pr.get('what'), pr.get('value'), pr.get('why')))
            return 0
        close(a.id, a.ref, a.file)
        print('닫음: %s' % a.id)
        return 0
    except (ValueError, OSError) as e:
        print('멈춤: %s' % e, file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
