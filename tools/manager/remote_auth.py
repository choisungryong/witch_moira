"""원격 접속(Cloudflare Tunnel + Access)의 서버 쪽 판정: 설정 읽기, Access JWT(RS256) 검증, 요청 판정, 원격에서 허용할 경로, 접속 기록. 표준 라이브러리만.

명세: docs/specs/T12-skill-lab-20261123.ko.md 9.2·9.5절. 설정 파일 tools/manager/local-remote.json(git 밖)이 없거나 enabled 가 false 면 이 모듈은 아무 것도 허용하지 않고,
서버는 지금까지와 똑같이(루프백 Host 만) 동작한다. 서버는 계속 127.0.0.1 에만 열린다: cloudflared 가 같은 PC 에서 루프백으로 붙는다.
검증이 어느 한 곳이라도 틀리면 거절한다(닫힌 쪽으로 실패): 서명, alg, kid, iss, aud, exp, nbf, 이메일, 공개 키를 받지 못함, 설정이 깨짐.

Cloudflare 문서(2026-11-23 확인): 요청에 `Cf-Access-Jwt-Assertion` 헤더로 토큰이 온다. 공개 키는 https://<팀>.cloudflareaccess.com/cdn-cgi/access/certs 의
`keys`(JWK, RSA, RS256)에 있고 토큰의 `kid` 로 고른다(서명 키는 6주마다 돌고 이전 키는 7일 더 유효). `iss` 는 https://<팀>.cloudflareaccess.com, `aud` 는 응용의 AUD 태그.
"""
import base64, hashlib, hmac, json, os, re, threading, time, urllib.request
from pathlib import Path

JWT_HEADER = 'Cf-Access-Jwt-Assertion'
# cloudflared 를 거쳐 온 요청에는 Cloudflare 가 붙이는 머리글이 있다. 이것이 있는 요청은 Host 가 루프백이어도 '로컬'로 보지 않는다(Host 위조 방지).
EDGE_HEADERS = ('Cf-Ray', 'Cf-Connecting-Ip', 'Cf-Visitor', 'Cf-Access-Jwt-Assertion', 'X-Forwarded-For', 'X-Forwarded-Host', 'Forwarded')
KEY_TTL_S = 3600
KEY_RETRY_S = 60          # 모르는 kid 를 만나면 키를 다시 받아 보되, 이 간격보다 자주는 아니다(돌린 키 따라잡기 + 남용 방지)
DEFAULT_ALLOWS = ('view', 'skill_lab.scene', 'skill_lab.clip', 'skill_lab.adopt', 'picks', 'notes')
HOST_RE = re.compile(r'^[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$')
TEAM_RE = re.compile(r'^[a-z0-9]([a-z0-9\-]*[a-z0-9])?\.cloudflareaccess\.com$')
EMAIL_RE = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
LOCAL_ONLY = 'local_only'


class AuthError(Exception):
    """검증 실패. reason 은 접속 기록에 남는 짧은 영문 낱말(이메일·토큰 내용은 넣지 않는다)."""

    def __init__(self, reason):
        super().__init__(reason)
        self.reason = reason


# ------------------------------------------------------------------ 설정
class Config:
    def __init__(self, enabled, hosts, team_domain, aud, emails, allows, problem=''):
        self.enabled, self.hosts, self.team_domain, self.aud, self.emails, self.allows, self.problem = enabled, hosts, team_domain, aud, emails, allows, problem

    @property
    def issuer(self):
        return 'https://' + self.team_domain


DISABLED = Config(False, (), '', '', (), (), '')


def parse_config(text):
    """local-remote.json 의 글 -> Config. 꼴이 틀리면 enabled=False 로 하고 problem 에 까닭(화면 머리에 보임, 로컬에서만). 예외를 내지 않는다."""
    try:
        d = json.loads(text)
    except ValueError:
        return Config(False, (), '', '', (), (), 'local-remote.json 을 읽지 못했습니다(JSON 이 아님). 원격은 꺼진 채입니다.')
    if not isinstance(d, dict):
        return Config(False, (), '', '', (), (), 'local-remote.json 의 꼴이 틀립니다. 원격은 꺼진 채입니다.')
    if d.get('enabled') is not True:
        return DISABLED
    acc = d.get('access') if isinstance(d.get('access'), dict) else {}
    hosts = d.get('hosts')
    emails = acc.get('emails')
    team, aud = acc.get('team_domain'), acc.get('aud')
    allows = d.get('remote_allows', list(DEFAULT_ALLOWS))
    bad = []
    if not isinstance(hosts, list) or not hosts or not all(isinstance(h, str) and HOST_RE.match(h.lower()) for h in hosts):
        bad.append('hosts')
    if not isinstance(team, str) or not TEAM_RE.match(team.lower()):
        bad.append('access.team_domain')
    if not isinstance(aud, str) or not re.fullmatch(r'[0-9a-fA-F]{16,128}', aud):
        bad.append('access.aud')
    if not isinstance(emails, list) or not emails or not all(isinstance(e, str) and EMAIL_RE.match(e) for e in emails):
        bad.append('access.emails')
    if not isinstance(allows, list) or not all(isinstance(a, str) for a in allows):
        bad.append('remote_allows')
    if bad:
        return Config(False, (), '', '', (), (), 'local-remote.json 에서 고칠 칸: %s. 원격은 꺼진 채입니다.' % ', '.join(bad))
    return Config(True, tuple(h.lower() for h in hosts), team.lower(), aud, tuple(e.lower() for e in emails),
                  tuple(a for a in allows if a != LOCAL_ONLY), '')


class ConfigFile:
    """파일을 요청마다 mtime 으로 살펴 바뀌면 다시 읽는다(서버를 다시 켜지 않고 enabled 를 넘길 수 있게)."""

    def __init__(self, path):
        self.path, self._sig, self._cfg, self._lock = Path(path), None, DISABLED, threading.Lock()

    def get(self):
        try:
            st = self.path.stat()
            sig = (st.st_mtime_ns, st.st_size)
        except OSError:
            self._sig, self._cfg = None, DISABLED          # 파일이 없다 = 지금까지와 똑같이
            return DISABLED
        with self._lock:
            if sig != self._sig:
                try:
                    self._cfg = parse_config(self.path.read_text(encoding='utf-8'))
                except (OSError, UnicodeError):
                    self._cfg = Config(False, (), '', '', (), (), 'local-remote.json 을 읽지 못했습니다. 원격은 꺼진 채입니다.')
                self._sig = sig
            return self._cfg


# ------------------------------------------------------------------ RS256
_SHA256_INFO = bytes.fromhex('3031300d060960864801650304020105000420')      # DigestInfo 머리(SHA-256)


def b64url_decode(s):
    if not isinstance(s, str) or not re.fullmatch(r'[A-Za-z0-9_\-]*', s):
        raise AuthError('bad_base64')
    return base64.urlsafe_b64decode(s + '=' * (-len(s) % 4))


def rsa_verify_pkcs1_sha256(n, e, message, signature):
    """RSASSA-PKCS1-v1_5 / SHA-256 검증(RFC 8017 8.2). 기대하는 인코딩을 직접 만들어 통째로 견준다(느슨한 파싱 없음)."""
    k = (n.bit_length() + 7) // 8
    if len(signature) != k or k < 64 or e < 3 or e % 2 == 0:
        return False
    s = int.from_bytes(signature, 'big')
    if s >= n:
        return False
    em = pow(s, e, n).to_bytes(k, 'big')
    t = _SHA256_INFO + hashlib.sha256(message).digest()
    expected = b'\x00\x01' + b'\xff' * (k - len(t) - 3) + b'\x00' + t
    return hmac.compare_digest(em, expected)


class KeySet:
    """팀의 공개 키(JWK). 1시간 캐시. 받기에 실패하면 캐시가 만료된 뒤에는 키가 없는 것으로 보아 모두 거절한다."""

    def __init__(self, fetch=None, clock=time.time):
        self.fetch, self.clock = fetch or self._http_fetch, clock
        self.keys, self.fetched_at, self.tried_at, self.team = {}, 0.0, 0.0, None
        self._lock = threading.Lock()

    @staticmethod
    def _http_fetch(team_domain):
        req = urllib.request.Request('https://%s/cdn-cgi/access/certs' % team_domain, headers={'User-Agent': 'moira-manager/1'})
        with urllib.request.urlopen(req, timeout=5) as r:
            if r.status != 200:
                raise OSError('certs status %s' % r.status)
            return json.loads(r.read(1 << 20).decode('utf-8'))

    def _load(self, team_domain):
        doc = self.fetch(team_domain)
        keys = {}
        for k in (doc.get('keys') or []) if isinstance(doc, dict) else []:
            if isinstance(k, dict) and k.get('kty') == 'RSA' and k.get('alg', 'RS256') == 'RS256' and isinstance(k.get('kid'), str):
                try:
                    keys[k['kid']] = (int.from_bytes(b64url_decode(k['n']), 'big'), int.from_bytes(b64url_decode(k['e']), 'big'))
                except (AuthError, KeyError, TypeError):
                    continue
        if not keys:
            raise ValueError('no keys')
        self.keys, self.fetched_at, self.team = keys, self.clock(), team_domain

    def get(self, team_domain, kid):
        with self._lock:
            now = self.clock()
            if self.team != team_domain:
                self.keys, self.fetched_at, self.tried_at, self.team = {}, 0.0, 0.0, team_domain
            fresh = self.keys and now - self.fetched_at < KEY_TTL_S
            if not fresh or (kid not in self.keys and now - self.tried_at >= KEY_RETRY_S):
                self.tried_at = now
                try:
                    self._load(team_domain)
                except Exception:       # 네트워크·JSON·꼴 무엇이든: 만료된 키는 쓰지 않는다
                    if not fresh:
                        self.keys = {}
                        raise AuthError('keys_unavailable')
            if kid not in self.keys:
                raise AuthError('unknown_kid')
            return self.keys[kid]


def verify_jwt(token, cfg, keyset, now=None):
    """Access 가 붙인 토큰을 검증하고 payload 를 돌려준다. 어긋나면 AuthError."""
    now = time.time() if now is None else now
    if not isinstance(token, str) or len(token) > 8192:
        raise AuthError('no_token')
    parts = token.split('.')
    if len(parts) != 3 or not all(parts):
        raise AuthError('malformed')
    try:
        header = json.loads(b64url_decode(parts[0]))
        payload = json.loads(b64url_decode(parts[1]))
    except (ValueError, UnicodeError):
        raise AuthError('malformed')
    if not isinstance(header, dict) or not isinstance(payload, dict):
        raise AuthError('malformed')
    if header.get('alg') != 'RS256':          # none·HS256 으로 꾸민 토큰을 막는다
        raise AuthError('alg')
    kid = header.get('kid')
    if not isinstance(kid, str) or not kid:
        raise AuthError('no_kid')
    n, e = keyset.get(cfg.team_domain, kid)
    if not rsa_verify_pkcs1_sha256(n, e, (parts[0] + '.' + parts[1]).encode('ascii'), b64url_decode(parts[2])):
        raise AuthError('signature')
    if payload.get('iss') != cfg.issuer:
        raise AuthError('iss')
    aud = payload.get('aud')
    if not (aud == cfg.aud or (isinstance(aud, list) and cfg.aud in aud)):
        raise AuthError('aud')
    exp = payload.get('exp')
    if type(exp) not in (int, float) or exp <= now:
        raise AuthError('expired')
    nbf = payload.get('nbf')
    if nbf is not None and (type(nbf) not in (int, float) or nbf > now + 30):
        raise AuthError('not_yet_valid')
    email = payload.get('email')
    if not isinstance(email, str) or email.lower() not in cfg.emails:
        raise AuthError('email')
    return payload


# ------------------------------------------------------------------ 요청 판정
class Decision:
    def __init__(self, kind, email='', reason='', attempt=False):
        self.kind, self.email, self.reason = kind, email, reason       # kind: 'local' | 'remote' | 'deny'
        self.attempt = attempt                                          # 원격으로 들어온 시도인가(거절도 기록에 남길지 정하는 데 씀)

    @property
    def allowed(self):
        return self.kind in ('local', 'remote')


def _loopback_hosts(port):
    return {'127.0.0.1:%d' % port, 'localhost:%d' % port}


def judge(cfg, keyset, headers, method, port, now=None):
    """요청의 Host·Origin·머리글 -> Decision. headers 는 이름을 대소문자 가리지 않고 get 하는 것(http.client.HTTPMessage 등).
    로컬: Host 가 루프백이고 Cloudflare 머리글이 없고, POST 는 Origin 도 루프백(지금까지와 같다). 원격: Host 가 hosts 에 있고 JWT 가 맞고 POST 는 Origin 이 https://<그 호스트>."""
    host = (headers.get('Host') or '').lower()
    origin = headers.get('Origin')
    via_edge = any(headers.get(h) for h in EDGE_HEADERS)
    local_hosts = _loopback_hosts(port)
    if host in local_hosts and not via_edge:
        ok_origins = {'http://' + h for h in local_hosts}
        if method == 'GET' or origin is None or origin in ok_origins:       # GET 은 지금까지 Origin 을 보지 않았다(trusted_request(host, None, port)). 그대로 둔다
            return Decision('local')
        return Decision('deny', reason='origin')
    if not cfg.enabled:
        return Decision('deny', reason='host')            # 지금까지와 같은 거절(403). 꺼져 있으면 기록도 남기지 않는다
    if host not in cfg.hosts:
        return Decision('deny', reason='host', attempt=True)
    if origin is not None and origin != 'https://' + host:
        return Decision('deny', reason='origin', attempt=True)
    if method == 'POST' and origin is None:
        return Decision('deny', reason='origin', attempt=True)
    try:
        payload = verify_jwt(headers.get(JWT_HEADER), cfg, keyset, now)
    except AuthError as e:
        return Decision('deny', reason=e.reason, attempt=True)
    return Decision('remote', email=payload['email'].lower(), attempt=True)


# ------------------------------------------------------------------ 원격에서 허용할 경로
FILE_VIEW_SUFFIXES = {'.png', '.svg', '.jpg', '.jpeg', '.webp', '.mp4', '.wav', '.glb'}        # 그림·소리·영상·모델만. 코드·문서 원문은 원격에서 안 보인다
GET_VIEW_PREFIXES = ('/media/', '/drafts/')
GET_VIEW_EXACT = {'/api/catalog', '/api/server', '/api/management', '/api/drafts', '/api/drafts/state', '/api/drafts/selection', '/api/playtests',
                  '/api/balance/meta', '/api/balance/experiments', '/api/tools', '/api/audit', '/api/picks', '/api/characters'}
POST_CLASS = {
    '/api/management': 'notes', '/api/playtests': 'notes', '/api/picks': 'picks', '/api/drafts/state': 'picks', '/api/drafts/selection': 'picks',
    '/api/balance/run': LOCAL_ONLY, '/api/audit/run': LOCAL_ONLY,                  # 긴 하위 프로세스: 원격에서 열지 않는다
    '/api/balance/experiments': 'balance.save', '/api/balance/export': 'balance.save',
}


def route_class(method, path, skill_lab_policy=None):
    """(방법, 경로) -> 정책 이름. 'view' 같은 낱말이거나 LOCAL_ONLY. 모르는 경로는 None(원격에서는 거절). 서버가 원격 요청마다 이것을 먼저 묻는다."""
    path = path.split('?', 1)[0]
    if path == '/api/remote' or path.startswith('/api/remote/'):
        return LOCAL_ONLY                                   # 원격 설정·접속 기록은 PC 앞에서만
    if path == '/api/skill-lab' or path.startswith('/api/skill-lab/'):
        return skill_lab_policy(method, path) if skill_lab_policy else None
    if method == 'GET':
        if path in GET_VIEW_EXACT or path.startswith(GET_VIEW_PREFIXES):
            return 'view'
        if re.fullmatch(r'/api/characters/[^/]+(/tripo)?', path):
            return 'view'
        if path.startswith('/files/'):
            return 'view' if Path(path).suffix.lower() in FILE_VIEW_SUFFIXES else LOCAL_ONLY
        if '/' not in path.lstrip('/') and Path(path).suffix.lower() in ('.html', '.js', '.css', ''):
            return 'view'                                    # 화면 파일(index.html, app.js ...)
        if path.startswith('/vendor/'):
            return 'view'
        return None
    if method == 'POST':
        if re.fullmatch(r'/api/characters/[^/]+/(open|tripo_out)', path):
            return LOCAL_ONLY                                # 탐색기 열기, 파일 올려받기
        return POST_CLASS.get(path)
    return None


def remote_allowed(cfg, cls):
    return cls is not None and cls != LOCAL_ONLY and cls in cfg.allows


# ------------------------------------------------------------------ 접속 기록
_LOG_LOCK = threading.Lock()


def log_line(path, email, method, req_path, result, now=None):
    """_local/manager/remote-access.log 에 한 줄: 시각 \t 이메일 \t 방법 \t 경로 \t 결과. 쿼리 문자열·토큰은 남기지 않는다."""
    now = time.time() if now is None else now
    safe = re.sub(r'[\t\r\n]', '_', req_path.split('?', 1)[0])[:200]
    line = '%s\t%s\t%s\t%s\t%s\n' % (time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(now)), email or '-', method, safe, result)
    try:
        p = Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        with _LOG_LOCK, p.open('a', encoding='utf-8', newline='\n') as f:
            f.write(line)
    except OSError:
        pass          # 기록을 못 써도 요청 판정은 그대로(이미 내려진 결정)


def last_access(path):
    """마지막으로 허용된 원격 접속 한 줄 -> {'time','email','method','path'} 또는 None(로컬 화면 머리의 「마지막 원격 접속」)."""
    try:
        lines = Path(path).read_text(encoding='utf-8').splitlines()
    except OSError:
        return None
    for ln in reversed(lines[-500:]):
        f = ln.split('\t')
        if len(f) == 5 and f[4].startswith('ok'):
            return {'time': f[0], 'email': f[1], 'method': f[2], 'path': f[3]}
    return None
