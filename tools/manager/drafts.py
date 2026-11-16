"""Character art draft gallery: reads _local/art/drafts/index.json on every request (read-only),
makes cached thumbnails, and keeps the user's verdicts in a separate local store."""
import hashlib, json, os, threading, time
from pathlib import Path

try:
    from .catalog import ROOT
except ImportError:
    from catalog import ROOT

DRAFTS = ROOT / '_local' / 'art' / 'drafts'
CANON = ROOT / 'chapter1' / 'art' / 'characters'
CACHE = ROOT / '_local' / 'manager-cache' / 'drafts'
STORE = Path(__file__).resolve().parent / 'local-drafts.json'
LOCK = threading.Lock()
IMAGE_TYPES = {'.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp'}
VERDICTS = {'', 'like', 'hold', 'drop'}
THUMB_WIDTH = 420
CANON_FILES = [('frost', '냉기 마녀'), ('ember', '불꽃 마녀'), ('storm', '번개 마녀')]
CHARACTER_NAMES = {
    'frost_witch': '냉기 마녀', 'ember_witch': '불꽃 마녀', 'storm_witch': '번개 마녀',
    'frost_demon': '냉기 악마', 'ember_demon': '불꽃 악마', 'storm_demon': '번개 악마',
    'frost_mother': '냉기 어머니', 'ember_mother': '불꽃 어머니', 'storm_mother': '번개 어머니',
    'demon_god': '악마신',
}


def safe_join(base, rel, suffixes):
    """Resolve rel strictly inside base; None when it escapes, is absolute, or has a wrong suffix."""
    if not isinstance(rel, str) or not rel or '\\' in rel or ':' in rel or '\x00' in rel or rel.startswith('/'):
        return None
    if any(x in ('', '.', '..') for x in rel.split('/')):
        return None
    try:
        base = base.resolve()
        p = (base / rel).resolve()
    except OSError:
        return None
    if not p.is_relative_to(base) or p.suffix.lower() not in suffixes or not p.is_file():
        return None
    return p


def read_index(drafts=None, canon=None):
    """Return (entries, canonical, warnings). entries: validated dicts with internal 'path'/'prompt_path'."""
    drafts = drafts or DRAFTS
    canon = canon or CANON
    warnings, entries, seen = [], [], set()
    index = drafts / 'index.json'
    raw = []
    if not index.is_file():
        warnings.append('원화 시안 색인(_local/art/drafts/index.json)이 아직 없습니다.')
    else:
        try:
            raw = json.loads(index.read_text(encoding='utf-8-sig'))
            if not isinstance(raw, list):
                warnings.append('원화 시안 색인이 목록 형식이 아닙니다.')
                raw = []
        except (OSError, ValueError) as e:
            warnings.append('원화 시안 색인을 읽지 못했습니다: %s' % e)
            raw = []
    for i, item in enumerate(raw):
        if not isinstance(item, dict) or not isinstance(item.get('id'), str) or not item['id'] or item['id'] in seen:
            warnings.append('색인 %d번째 항목을 건너뜁니다(id가 없거나 겹침).' % (i + 1))
            continue
        path = safe_join(drafts, item.get('file'), IMAGE_TYPES)
        if path is None:
            warnings.append('시안 %s의 그림 파일을 찾지 못해 건너뜁니다.' % item['id'])
            continue
        seen.add(item['id'])
        pp = safe_join(drafts, item.get('prompt_file'), {'.txt'}) if item.get('prompt_file') else None
        text = lambda k: item.get(k) if isinstance(item.get(k), str) else ''
        entries.append({'id': item['id'], 'character': text('character') or 'unknown', 'group': text('group') or '기타',
                        'title': text('title') or item['id'], 'tool': text('tool'), 'model': text('model'),
                        'created': text('created'), 'status': text('status') or '검토 대기', 'note': text('note'),
                        'has_prompt': pp is not None, 'path': path, 'prompt_path': pp})
    canonical = []
    for key, name in CANON_FILES:
        p = safe_join(canon, key + '_witch_v02.png', IMAGE_TYPES)
        if p:
            canonical.append({'id': 'canon-' + key, 'character': key + '_witch', 'group': '확정 원화', 'title': name + ' 확정 원화',
                              'tool': '', 'model': '', 'created': '', 'status': '확정', 'note': '게임에 들어 있는 확정 원화',
                              'has_prompt': False, 'path': p, 'prompt_path': None})
    return entries, canonical, warnings


def public(e):
    return {k: v for k, v in e.items() if k not in ('path', 'prompt_path')}


def gallery(drafts=None, canon=None, store=None):
    entries, canonical, warnings = read_index(drafts, canon)
    # newest first within a character (index is chronological; sort by created string, stable)
    entries.sort(key=lambda e: e['created'], reverse=True)
    order, seen = [], set()
    for e in entries:
        if e['character'] not in seen:
            seen.add(e['character'])
            order.append({'character': e['character'], 'group': e['group'],
                          'name': CHARACTER_NAMES.get(e['character'], e['character'])})
    for c in order:
        c['count'] = sum(1 for e in entries if e['character'] == c['character'])
    return {'generated_at': time.strftime('%Y-%m-%d %H:%M:%S'), 'canonical': [public(e) for e in canonical],
            'characters': order, 'items': [public(e) for e in entries], 'warnings': warnings,
            'thumbnails': thumbs_available(), 'decisions': load_store(store)}


def thumbs_available():
    try:
        import PIL  # noqa: F401
        return True
    except ImportError:
        return False


def find(item_id, drafts=None, canon=None):
    entries, canonical, _ = read_index(drafts, canon)
    for e in canonical + entries:
        if e['id'] == item_id:
            return e
    return None


def thumb_path(entry, cache=None):
    """Cached JPEG thumbnail path, or None when Pillow is missing or conversion fails (caller sends the original)."""
    cache = cache or CACHE
    src = entry['path']
    try:
        st = src.stat()
        key = hashlib.sha1(('%s|%d|%d' % (src, st.st_mtime_ns, st.st_size)).encode('utf-8')).hexdigest()[:24]
        out = cache / (key + '.jpg')
        if out.is_file():
            return out
        from PIL import Image
        cache.mkdir(parents=True, exist_ok=True)
        with Image.open(src) as im:
            im = im.convert('RGB')
            im.thumbnail((THUMB_WIDTH, THUMB_WIDTH * 3))
            tmp = cache / (key + '.%d.tmp' % threading.get_ident())
            im.save(tmp, 'JPEG', quality=84, optimize=True)
        os.replace(tmp, out)
        return out
    except Exception:
        return None


def load_store(path=None):
    path = path or STORE
    try:
        value = json.loads(path.read_text(encoding='utf-8'))
        if isinstance(value, dict) and isinstance(value.get('revision'), int) and isinstance(value.get('records'), dict):
            return value
    except (OSError, ValueError):
        pass
    return {'revision': 0, 'records': {}}


def update_store(payload, valid_ids, path=None):
    path = path or STORE
    if not isinstance(payload, dict) or set(payload) != {'revision', 'id', 'changes'}:
        raise ValueError('Expected revision, id, changes')
    if type(payload['revision']) is not int or payload['revision'] < 0 or not isinstance(payload['id'], str) or payload['id'] not in valid_ids:
        raise ValueError('Invalid revision or ID')
    changes = payload['changes']
    if not isinstance(changes, dict) or not changes or set(changes) - {'verdict', 'notes'}:
        raise ValueError('Invalid fields')
    for key, value in changes.items():
        if not isinstance(value, str):
            raise ValueError('Fields must be strings')
        if key == 'verdict' and value not in VERDICTS:
            raise ValueError('Invalid verdict')
        if key == 'notes' and len(value) > 12000:
            raise ValueError('Notes limit is 12000 characters')
    with LOCK:
        if path.exists():
            current = json.loads(path.read_text(encoding='utf-8'))
            if not isinstance(current, dict) or not isinstance(current.get('revision'), int) or not isinstance(current.get('records'), dict):
                raise ValueError('Invalid draft store')
        else:
            current = {'revision': 0, 'records': {}}
        if payload['revision'] != current['revision']:
            return 409, current
        rec = current['records'].setdefault(payload['id'], {})
        rec.update(changes)
        rec['updated'] = time.strftime('%Y-%m-%d %H:%M:%S')
        current['revision'] += 1
        path.parent.mkdir(parents=True, exist_ok=True)
        temp = path.with_suffix('.tmp')
        with temp.open('w', encoding='utf-8', newline='\n') as f:
            json.dump(current, f, ensure_ascii=False, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp, path)
        return 200, current
