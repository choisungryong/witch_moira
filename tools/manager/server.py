"""Loopback-only manager server: read-only catalog plus atomic management notes (stdlib only)."""
import argparse, json, mimetypes, os, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit, parse_qs
try:
    from .catalog import ROOT, generate
    from . import drafts, playlog, balance_lab, tools_index, audit_view
except ImportError:
    from catalog import ROOT, generate
    import drafts, playlog, balance_lab, tools_index, audit_view

APP = Path(__file__).resolve().parent
STATE = APP / 'local-state.json'
LOCK = threading.Lock()
STATUSES = {'todo', 'in_progress', 'review', 'done', 'deferred'}
PRIORITIES = {'low', 'normal', 'high', 'urgent'}
STATIC_SUFFIXES = {'.html', '.js', '.css'}
STATIC_EXTRA = {'vendor/model-viewer.min.js'}
FILE_TYPES = {'.png': 'image/png', '.svg': 'image/svg+xml', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp',
              '.wav': 'audio/wav', '.glb': 'model/gltf-binary', '.json': 'text/plain; charset=utf-8',
              '.md': 'text/plain; charset=utf-8', '.po': 'text/plain; charset=utf-8', '.py': 'text/plain; charset=utf-8', '.txt': 'text/plain; charset=utf-8', '.gd': 'text/plain; charset=utf-8',
              '.gdshader': 'text/plain; charset=utf-8'}


def static_names(app=None):
    """Screen files served right now: top-level .html/.js/.css next to server.py, read from disk on every
    request (so a screen file added after the server started is still served), plus the vendored viewer."""
    app = app or APP
    names = {p.name for p in app.iterdir() if p.is_file() and p.suffix in STATIC_SUFFIXES}
    return names | {x for x in STATIC_EXTRA if (app / x).is_file()}


def code_snapshot(app=None):
    """{file name: (mtime_ns, size)} of the Python modules this process imported at startup."""
    app = app or APP
    return {p.name: (p.stat().st_mtime_ns, p.stat().st_size) for p in app.glob('*.py') if not p.name.startswith('test_')}


def stale_report(started, app=None):
    """Python code is loaded once at startup; report modules that changed, appeared or vanished since then."""
    now = code_snapshot(app)
    changed = sorted(n for n in now if started.get(n) != now[n] and n in started)
    added = sorted(set(now) - set(started))
    removed = sorted(set(started) - set(now))
    return {'stale': bool(changed or added or removed), 'changed': changed, 'added': added, 'removed': removed}


def load_state(path=None):
    path = path or STATE
    if not path.exists():
        return {'revision': 0, 'records': {}}
    value = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(value, dict) or not isinstance(value.get('revision'), int) or not isinstance(value.get('records'), dict):
        raise ValueError('Invalid management store')
    return value


def update_state(payload, valid_ids, path=None):
    path = path or STATE
    if not isinstance(payload, dict) or set(payload) != {'revision', 'id', 'changes'}:
        raise ValueError('Expected revision, id, changes')
    if type(payload['revision']) is not int or payload['revision'] < 0 or not isinstance(payload['id'], str) or payload['id'] not in valid_ids:
        raise ValueError('Invalid revision or ID')
    changes = payload['changes']
    if not isinstance(changes, dict) or not changes or set(changes) - {'status', 'priority', 'notes'}:
        raise ValueError('Invalid fields')
    for key, value in changes.items():
        if not isinstance(value, str):
            raise ValueError('Fields must be strings')
        if key == 'status' and value not in STATUSES:
            raise ValueError('Invalid status')
        if key == 'priority' and value not in PRIORITIES:
            raise ValueError('Invalid priority')
        if key == 'notes' and len(value) > 12000:
            raise ValueError('Notes limit is 12000 characters')
    with LOCK:
        current = load_state(path)
        if payload['revision'] != current['revision']:
            return 409, current
        current['records'].setdefault(payload['id'], {}).update(changes)
        current['revision'] += 1
        path.parent.mkdir(parents=True, exist_ok=True)
        temp = path.with_suffix('.tmp')
        with temp.open('w', encoding='utf-8', newline='\n') as f:
            json.dump(current, f, ensure_ascii=False, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp, path)
        return 200, current


def permitted_file(raw, allowed, root=ROOT):
    """Repo-relative path from a /files/ URL, only if the catalog registered it."""
    value = unquote(raw)
    if '\\' in value or ':' in value or '\x00' in value or value.startswith('/') or any(x in ('', '..', '.', '.git', '.env') for x in value.split('/')):
        return None
    if value not in allowed:
        return None
    root = root.resolve()
    p = (root / value).resolve()
    if not p.is_relative_to(root) or not p.is_file() or p.suffix.lower() not in FILE_TYPES:
        return None
    return p


def trusted_request(host, origin, port):
    hosts = {'127.0.0.1:' + str(port), 'localhost:' + str(port)}
    return host in hosts and (origin is None or origin in {'http://' + h for h in hosts})


def refresh(server):
    catalog = generate()
    with LOCK:
        server.catalog = catalog
        server.valid_ids = {r['id'] for r in catalog['entities']}
        server.allowed = set(catalog['allowed'])
    return catalog


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_json(self, status, value):
        data = json.dumps(value, ensure_ascii=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        self.wfile.write(data)

    def send_bytes(self, mime, p, cache=None):
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(p.stat().st_size))
        self.send_header('X-Content-Type-Options', 'nosniff')
        if cache:
            self.send_header('Cache-Control', cache)
        self.end_headers()
        self.wfile.write(p.read_bytes())

    def send_draft(self, rest):
        # /drafts/<thumb|full|prompt>/<id> ; only ids present in the current index are served
        kind, _, raw_id = unquote(rest).partition('/')
        if kind not in ('thumb', 'full', 'prompt') or not raw_id:
            return self.send_json(404, {'error': 'Unknown draft route'})
        entry = drafts.find(raw_id)
        if entry is None:
            return self.send_json(404, {'error': 'Not a registered draft'})
        if kind == 'prompt':
            if not entry['prompt_path']:
                return self.send_json(404, {'error': 'No prompt'})
            return self.send_bytes('text/plain; charset=utf-8', entry['prompt_path'], 'no-store')
        if kind == 'thumb':
            t = drafts.thumb_path(entry)
            if t:
                return self.send_bytes('image/jpeg', t, 'private, max-age=3600')
        p = entry['path']
        return self.send_bytes(drafts.IMAGE_TYPES[p.suffix.lower()], p, 'private, max-age=60')

    def do_GET(self):
        if not trusted_request(self.headers.get('Host'), None, self.server.server_port):
            return self.send_json(403, {'error': 'Untrusted Host'})
        parts = urlsplit(self.path)
        route = parts.path
        if route == '/api/catalog':
            if 'refresh' in parse_qs(parts.query):
                return self.send_json(200, refresh(self.server))
            return self.send_json(200, self.server.catalog)
        if route == '/api/server':
            return self.send_json(200, stale_report(self.server.code_started))
        if route == '/api/management':
            return self.send_json(200, load_state())
        if route == '/api/drafts':
            return self.send_json(200, drafts.gallery())
        if route == '/api/drafts/state':
            return self.send_json(200, drafts.load_store())
        if route == '/api/drafts/selection':
            return self.send_json(200, drafts.load_selection())
        if route == '/api/playtests':
            return self.send_json(200, playlog.overview())
        if route == '/api/balance/meta':
            q = parse_qs(parts.query)
            return self.send_json(200, balance_lab.meta(spells_id=(q.get('spells') or [None])[0], preset=(q.get('preset') or [None])[0]))
        if route == '/api/balance/experiments':
            return self.send_json(200, balance_lab.list_experiments())
        if route == '/api/tools':
            return self.send_json(200, tools_index.build())
        if route == '/api/audit':
            return self.send_json(200, audit_view.latest())
        if route.startswith('/drafts/'):
            return self.send_draft(route[len('/drafts/'):])
        if route.startswith('/files/'):
            p = permitted_file(route[len('/files/'):], self.server.allowed)
            mime = FILE_TYPES.get(p.suffix.lower()) if p else None
        else:
            name = unquote(route.lstrip('/') or 'index.html')
            p = (APP / name) if name in static_names() else None
            mime = mimetypes.guess_type(name)[0] or 'application/octet-stream'
            if name.endswith('.js'):
                mime = 'text/javascript; charset=utf-8'
        if p is None or not p.is_file():
            return self.send_json(404, {'error': 'Not an allowed file'})
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(p.stat().st_size))
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        with p.open('rb') as f:
            while True:
                chunk = f.read(256 * 1024)
                if not chunk:
                    break
                self.wfile.write(chunk)

    def do_POST(self):
        if not trusted_request(self.headers.get('Host'), self.headers.get('Origin'), self.server.server_port):
            return self.send_json(403, {'error': 'Untrusted Host or Origin'})
        if self.path not in ('/api/management', '/api/drafts/state', '/api/drafts/selection', '/api/playtests',
                         '/api/balance/run', '/api/balance/experiments', '/api/balance/export', '/api/audit/run'):
            return self.send_json(404, {'error': 'Unknown route'})
        if self.headers.get('Content-Type', '').split(';')[0] != 'application/json':
            return self.send_json(415, {'error': 'application/json required'})
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 65536:
                raise ValueError('Invalid payload length')
            payload = json.loads(self.rfile.read(length))
            if self.path == '/api/drafts/state':
                entries, canonical, _ = drafts.read_index()
                status, value = drafts.update_store(payload, {e['id'] for e in entries + canonical})
            elif self.path == '/api/drafts/selection':
                entries, _, _ = drafts.read_index()
                status, value = drafts.update_selection(payload, {e['id'] for e in entries})
            elif self.path == '/api/playtests':
                status, value = 200, playlog.save(payload, playlog.questions()[0])
            elif self.path == '/api/balance/run':
                status, value = 200, balance_lab.run(payload)
            elif self.path == '/api/balance/experiments':
                status, value = 200, balance_lab.save_experiment(payload)
            elif self.path == '/api/balance/export':
                status, value = 200, balance_lab.export_sets(payload)
            elif self.path == '/api/audit/run':
                status, value = 200, audit_view.run()
            else:
                status, value = update_state(payload, self.server.valid_ids)
            self.send_json(status, value)
        except (balance_lab.BusyError, audit_view.BusyError) as e:
            self.send_json(429, {'error': str(e)})
        except (balance_lab.RunError, audit_view.RunError) as e:
            self.send_json(502, {'error': str(e)})
        except (ValueError, UnicodeError) as e:
            self.send_json(400, {'error': str(e)})
        except OSError as e:
            self.send_json(500, {'error': 'Could not write the file: %s' % e.__class__.__name__})


def make_server(port=8781):
    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    server.code_started = code_snapshot()
    refresh(server)
    return server


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8781)
    args = parser.parse_args()
    with make_server(args.port) as server:
        print('Manager: http://127.0.0.1:' + str(server.server_port), flush=True)
        server.serve_forever()
