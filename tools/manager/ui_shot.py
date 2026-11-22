#!/usr/bin/env python3
"""관리 툴 화면을 헤드리스 Edge로 열어 PNG 캡처와 화면이 내놓은 수치(data-*)를 얻는다. 표준 라이브러리만.

사용(서버를 먼저 띄운다: python tools/manager/server.py --port 8791):
  python tools/manager/ui_shot.py --port 8791 --hash "#character/frost?a=run&b=walk@1.3&v=5.8&cam=19.5" --size 1440x900 \
      --out _local/shots/t9/char-1440.png --dump-dom
  --dump-dom   화면이 data-ready="1" 이 된 뒤의 DOM 에서 id=character 요소의 data-* 속성을 읽어 JSON 으로 찍는다.
  --offline    바깥 연결을 막는다(--host-resolver-rules). --net-log 와 함께 쓰면 요청한 주소의 호스트 목록도 찍는다.
  --out 은 _local/ 아래만 허용한다. 임시 프로필도 _local/ 아래에 두고 끝나면 지운다(사용자의 Edge 프로필은 건드리지 않는다).
WebGL 이 안 뜨면(data-webgl="0") --use-angle=swiftshader 깃발로 한 번 더 시도하고, 끝내 안 되면 그렇다고 찍는다.
이 도구가 띄운 Edge 프로세스만 정리한다.
기본은 DevTools 로 화면이 data-ready 가 될 때까지 실제 시간으로 기다린 뒤 수치(--dump-dom)와 PNG(--out)를 같은 창에서 얻는다(--eval 로 클릭·올리기 같은 조작도 가능).
--virtual 은 옛 방식(가상 시간 예산)이며, 이 Edge 에서 모델을 읽는 화면이 예산 안에 끝나지 않는 일이 있어 기본에서 뺐다(2026-11-23 확인).
"""
import argparse, html.parser, json, os, re, shutil, subprocess, sys, tempfile, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EDGE = Path('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe')
SWIFTSHADER = ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist']
OFFLINE_RULE = '--host-resolver-rules=MAP * ~NOTFOUND , EXCLUDE 127.0.0.1'


class ShotError(Exception):
    pass


def check_out(path):
    p = Path(path)
    p = (p if p.is_absolute() else Path.cwd() / p).resolve()
    base = (ROOT / '_local').resolve()
    if not p.is_relative_to(base):
        raise ShotError('--out 은 _local/ 아래만 허용합니다: %s' % p)
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


class Attrs(html.parser.HTMLParser):
    def __init__(self, element_id):
        super().__init__()
        self.element_id, self.attrs = element_id, None

    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        if self.attrs is None and d.get('id') == self.element_id:
            self.attrs = {k[5:]: (v or '') for k, v in attrs if k.startswith('data-')}


def parse_dom(text, element_id='character'):
    p = Attrs(element_id)
    p.feed(text)
    return p.attrs


def run_edge(args, timeout):
    """Edge 를 띄우고 끝나길 기다린다. 시간이 넘으면 그 프로세스 트리만 내린다. (종료 코드, 표준 출력)"""
    proc = subprocess.Popen([str(EDGE)] + args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    try:
        out, _ = proc.communicate(timeout=timeout)
        return proc.returncode, out.decode('utf-8', 'replace')
    except subprocess.TimeoutExpired:
        subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'], capture_output=True)
        proc.communicate()
        raise ShotError('Edge 가 %d초 안에 끝나지 않아 내렸습니다.' % timeout)


def base_args(a, profile, extra):
    w, h = a.size.split('x')
    args = ['--headless=new', '--no-first-run', '--disable-extensions', '--disable-background-networking', '--hide-scrollbars', '--mute-audio',
            '--user-data-dir=' + str(profile), '--window-size=%s,%s' % (w, h), '--virtual-time-budget=%d' % a.budget,
            '--run-all-compositor-stages-before-draw'] + extra
    if a.offline:
        args.append(OFFLINE_RULE)
    return args


class MiniWS:
    """DevTools 에 말을 거는 아주 작은 WebSocket 클라이언트(표준 라이브러리만, 글자 프레임만)."""
    def __init__(self, url):
        import base64, socket
        m = re.fullmatch(r'ws://([^/:]+):(\d+)(/.*)', url)
        if not m:
            raise ShotError('DevTools 주소를 읽지 못함: %s' % url)
        host, port, path = m.group(1), int(m.group(2)), m.group(3)
        self.sock = socket.create_connection((host, port), timeout=60)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall(('GET %s HTTP/1.1\r\nHost: %s:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n'
                           % (path, host, port, key)).encode())
        head = b''
        while b'\r\n\r\n' not in head:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ShotError('DevTools 연결이 닫힘')
            head += chunk
        if b' 101 ' not in head.split(b'\r\n', 1)[0]:
            raise ShotError('DevTools 연결 거절: %s' % head[:80])
        self.buf = head.split(b'\r\n\r\n', 1)[1]
        self.next_id = 0

    def _read(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ShotError('DevTools 연결이 닫힘')
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def send(self, obj):
        import struct
        data = json.dumps(obj).encode('utf-8')
        mask = os.urandom(4)
        n = len(data)
        head = bytes([0x81]) + (bytes([0x80 | n]) if n < 126 else bytes([0x80 | 126]) + struct.pack('>H', n) if n < 65536 else bytes([0x80 | 127]) + struct.pack('>Q', n))
        self.sock.sendall(head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

    def recv(self):
        import struct
        payload = b''
        while True:
            b0, b1 = self._read(2)
            n = b1 & 0x7F
            if n == 126:
                n = struct.unpack('>H', self._read(2))[0]
            elif n == 127:
                n = struct.unpack('>Q', self._read(8))[0]
            data = self._read(n)
            op = b0 & 0x0F
            if op == 8:
                raise ShotError('DevTools 연결이 닫힘')
            if op in (9, 10):
                continue
            payload += data
            if b0 & 0x80:
                return json.loads(payload.decode('utf-8'))

    def call(self, method, params=None):
        self.next_id += 1
        self.send({'id': self.next_id, 'method': method, 'params': params or {}})
        while True:
            msg = self.recv()
            if msg.get('id') == self.next_id:
                if 'error' in msg:
                    raise ShotError('DevTools 오류: %s' % msg['error'])
                return msg.get('result', {})


def free_port():
    import socket
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def eval_in_page(a, profile, url, script, extra, shot=None, want_attrs=False, netlog=None):
    """화면을 열고 data-ready 를 기다린 뒤(실제 시간) script 를 실행하고, 요청이 있으면 data-* 속성과 PNG 를 같은 창에서 얻는다.
    DevTools 로 조작하므로 가상 시간 예산에 기대지 않는다. 결과 {'eval', 'attrs', 'png_bytes'}."""
    import base64, urllib.request
    port = free_port()
    w, h = a.size.split('x')
    args = [str(EDGE), '--headless=new', '--no-first-run', '--disable-extensions', '--disable-background-networking', '--mute-audio', '--hide-scrollbars',
            '--user-data-dir=' + str(profile), '--window-size=%s,%s' % (w, h), '--remote-debugging-port=%d' % port] + extra
    if a.offline:
        args.append(OFFLINE_RULE)
    if netlog:
        args.append('--log-net-log=' + str(netlog))
    args.append(url)
    proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        ws, deadline = None, time.time() + 40
        while ws is None and time.time() < deadline:
            try:
                targets = json.loads(urllib.request.urlopen('http://127.0.0.1:%d/json' % port, timeout=3).read())
                page = next(t for t in targets if t.get('type') == 'page' and t.get('url', '').startswith('http://127.0.0.1:%d/' % a.port))
                ws = MiniWS(page['webSocketDebuggerUrl'])
            except (OSError, StopIteration, ValueError):
                time.sleep(0.5)
        if ws is None:
            raise ShotError('DevTools 에 연결하지 못했습니다.')
        probe = "document.querySelector('#%s') && document.querySelector('#%s').getAttribute('data-ready')" % (a.element, a.element)
        deadline = time.time() + 90
        while time.time() < deadline:
            if ws.call('Runtime.evaluate', {'expression': probe, 'returnByValue': True}).get('result', {}).get('value') == '1':
                break
            time.sleep(0.5)
        else:
            raise ShotError('화면이 data-ready 가 되지 않았습니다.')
        out = {}
        if script:
            res = ws.call('Runtime.evaluate', {'expression': script, 'awaitPromise': True, 'returnByValue': True})
            if 'exceptionDetails' in res:
                raise ShotError('스크립트 예외: %s' % json.dumps(res['exceptionDetails'], ensure_ascii=False)[:300])
            out['eval'] = res.get('result', {}).get('value')
        time.sleep(a.settle)            # 비동기로 채워지는 칸(받은 모델 목록 등)과 몇 프레임을 기다린다
        if want_attrs:
            expr = "(() => { const e = document.querySelector('#%s'); if (!e) return null; const o = {}; for (const x of e.attributes) if (x.name.startsWith('data-')) o[x.name.slice(5)] = x.value; return o; })()" % a.element
            out['attrs'] = ws.call('Runtime.evaluate', {'expression': expr, 'returnByValue': True}).get('result', {}).get('value')
        if shot:
            data = ws.call('Page.captureScreenshot', {'format': 'png'}).get('data')
            if not data:
                raise ShotError('PNG 가 만들어지지 않았습니다.')
            Path(shot).write_bytes(base64.b64decode(data))
            out['png_bytes'] = Path(shot).stat().st_size
        return out
    finally:
        subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'], capture_output=True)


def hosts_from_netlog(path):
    try:
        text = Path(path).read_text(encoding='utf-8', errors='replace')
    except OSError:
        return None
    return sorted(set(re.findall(r'"url":"https?://([^/"\\:]+(?::\d+)?)', text)))


def main(argv=None):
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')     # 화면이 내놓은 글(한국어, 줄표)을 콘솔 코드페이지와 상관없이 그대로 찍는다
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--port', type=int, default=8781)
    ap.add_argument('--hash', default='')
    ap.add_argument('--size', default='1440x900')
    ap.add_argument('--out', default=None)
    ap.add_argument('--dump-dom', action='store_true')
    ap.add_argument('--offline', action='store_true')
    ap.add_argument('--net-log', default=None, help='요청한 호스트를 보려고 netlog 를 _local/ 아래에 쓴다')
    ap.add_argument('--budget', type=int, default=30000, help='가상 시간 예산(ms)')
    ap.add_argument('--timeout', type=int, default=150)
    ap.add_argument('--element', default='character')
    ap.add_argument('--virtual', action='store_true', help='옛 방식(가상 시간 예산, --dump-dom/--screenshot 깃발). 기본은 DevTools 로 실제 시간 동안 기다린다')
    ap.add_argument('--settle', type=float, default=1.5, help='data-ready 뒤 더 기다릴 초')
    ap.add_argument('--eval', default=None, help='화면이 준비된 뒤 실행할 자바스크립트 식(클릭·저장 시험용). 결과를 result.eval 로 찍는다')
    a = ap.parse_args(argv)
    if not re.fullmatch(r'\d+x\d+', a.size):
        print('--size 는 1440x900 꼴', file=sys.stderr)
        return 2
    if not EDGE.is_file():
        print('Edge 를 찾지 못했습니다: %s' % EDGE, file=sys.stderr)
        return 2
    try:
        out = check_out(a.out) if a.out else None
        netlog = check_out(a.net_log) if a.net_log else None
    except ShotError as e:
        print(e, file=sys.stderr)
        return 2
    url = 'http://127.0.0.1:%d/%s' % (a.port, a.hash if a.hash.startswith('#') or not a.hash else '#' + a.hash)
    base = ROOT / '_local' / 'ui-shot-profile'
    base.mkdir(parents=True, exist_ok=True)
    profile = Path(tempfile.mkdtemp(prefix='p-', dir=str(base)))
    result = {'url': url, 'size': a.size, 'offline': a.offline}
    try:
        if not a.virtual:
            if out and out.exists():
                out.unlink()
            r = eval_in_page(a, profile, url, a.eval, [], shot=out, want_attrs=a.dump_dom, netlog=netlog)
            if a.eval:
                result['eval'] = r.get('eval')
            if a.dump_dom:
                result['dom_found'] = r.get('attrs') is not None
                result['attrs'] = r.get('attrs') or {}
            if out:
                result['png'] = str(out)
                result['png_bytes'] = r.get('png_bytes')
            if netlog:
                time.sleep(1)
                result['net_hosts'] = hosts_from_netlog(netlog)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0
        flavors = [('default', []), ('swiftshader', SWIFTSHADER)]
        attrs, used = None, None
        for name, extra in flavors:
            if a.dump_dom:
                args = base_args(a, profile, extra) + (['--log-net-log=' + str(netlog)] if netlog else []) + ['--dump-dom', url]
                _, text = run_edge(args, a.timeout)
                attrs = parse_dom(text, a.element)
                used = name
                if attrs is not None and attrs.get('webgl') == '1':
                    break
                if attrs is not None and attrs.get('webgl') is None:
                    break      # 3D 와 상관없는 화면
            else:
                break
        if a.dump_dom:
            result['edge_flags'] = used
            result['dom_found'] = attrs is not None
            result['attrs'] = attrs or {}
            if attrs is not None and attrs.get('webgl') == '0':
                result['webgl_note'] = 'WebGL 이 헤드리스 Edge 에서 뜨지 않았습니다(기본과 swiftshader 모두 시도).'
        if a.eval:
            result['eval'] = eval_in_page(a, profile, url, a.eval, SWIFTSHADER if used == 'swiftshader' else [])
        if out:
            extra = SWIFTSHADER if (used == 'swiftshader' or not a.dump_dom) else []
            if not a.dump_dom:
                extra = SWIFTSHADER   # 캡처만 할 때는 처음부터 swiftshader(기본에서 WebGL 이 안 뜬 환경이 흔하다)
            args = base_args(a, profile, extra) + ['--screenshot=' + str(out), url]
            if out.exists():
                out.unlink()
            run_edge(args, a.timeout)
            if not out.is_file() or out.stat().st_size == 0:
                raise ShotError('PNG 가 만들어지지 않았습니다.')
            result['png'] = str(out)
            result['png_bytes'] = out.stat().st_size
        if netlog:
            result['net_hosts'] = hosts_from_netlog(netlog)
    except ShotError as e:
        print(json.dumps(dict(result, error=str(e)), ensure_ascii=False, indent=2))
        return 1
    finally:
        shutil.rmtree(profile, ignore_errors=True)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
