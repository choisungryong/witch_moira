"""원격 접속 검사. Cloudflare 에 접속하지 않는다: 검사 안에서 만든 RSA 키로 서명한 가짜 Access JWT 와 가짜 공개 키 받기로만 돈다.
실제 local-remote.json·local-state.json·local-picks.json·_local/ 은 건드리지 않는다(임시 경로)."""
import base64, hashlib, json, random, shutil, subprocess, sys, tempfile, threading, time, unittest, urllib.error, urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import picks, remote_auth as ra, server, skill_lab

TEAM = 'moira-test.cloudflareaccess.com'
AUD = 'a' * 64
HOST = 'moira.example.com'
EMAIL = 'owner@example.com'
SHA256_INFO = bytes.fromhex('3031300d060960864801650304020105000420')


# ---------------------------------------------------------------- 검사용 RSA (표준 라이브러리만; 검사 전용, 약한 난수)
def _is_prime(n, rnd, rounds=20):
    if n < 4:
        return n in (2, 3)
    for p in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37):
        if n % p == 0:
            return n == p
    d, r = n - 1, 0
    while d % 2 == 0:
        d //= 2
        r += 1
    for _ in range(rounds):
        x = pow(rnd.randrange(2, n - 1), d, n)
        if x in (1, n - 1):
            continue
        for _ in range(r - 1):
            x = pow(x, 2, n)
            if x == n - 1:
                break
        else:
            return False
    return True


def _prime(bits, rnd):
    while True:
        c = rnd.getrandbits(bits) | (1 << (bits - 1)) | 1
        if _is_prime(c, rnd):
            return c


class Rsa:
    def __init__(self, seed, bits=1024, kid=None):
        rnd = random.Random(seed)
        e = 65537
        while True:
            p, q = _prime(bits // 2, rnd), _prime(bits // 2, rnd)
            n, phi = p * q, (p - 1) * (q - 1)
            if p != q and n.bit_length() == bits and phi % e:
                break
        self.n, self.e, self.d = n, e, pow(e, -1, phi)
        self.kid = kid or hashlib.sha256(str(seed).encode()).hexdigest()

    def jwk(self):
        return {'kid': self.kid, 'kty': 'RSA', 'alg': 'RS256', 'use': 'sig', 'e': b64(self.e.to_bytes(3, 'big')),
                'n': b64(self.n.to_bytes((self.n.bit_length() + 7) // 8, 'big'))}

    def sign(self, message):
        k = (self.n.bit_length() + 7) // 8
        t = SHA256_INFO + hashlib.sha256(message).digest()
        em = b'\x00\x01' + b'\xff' * (k - len(t) - 3) + b'\x00' + t
        return pow(int.from_bytes(em, 'big'), self.d, self.n).to_bytes(k, 'big')


def b64(b):
    return base64.urlsafe_b64encode(b).rstrip(b'=').decode('ascii')


KEY_A = Rsa(1)                  # 팀의 서명 키(공개 키가 certs 에 있음)
KEY_B = Rsa(2)                  # 남의 키


def make_token(key=KEY_A, kid=None, claims=None, header=None, now=None, sign_with=None, alg='RS256'):
    now = int(time.time() if now is None else now)
    payload = {'iss': 'https://' + TEAM, 'aud': [AUD], 'email': EMAIL, 'exp': now + 3600, 'iat': now, 'nbf': now - 5, 'type': 'app'}
    payload.update(claims or {})
    h = {'alg': alg, 'kid': kid or key.kid, 'typ': 'JWT'}
    h.update(header or {})
    signing = (b64(json.dumps(h).encode()) + '.' + b64(json.dumps(payload).encode()))
    return signing + '.' + b64((sign_with or key).sign(signing.encode('ascii')))


def certs_doc(*keys):
    return {'keys': [k.jwk() for k in keys], 'public_certs': []}


def config(**kw):
    d = {'enabled': True, 'hosts': [HOST], 'access': {'team_domain': TEAM, 'aud': AUD, 'emails': [EMAIL]}}
    d.update(kw)
    return ra.parse_config(json.dumps(d))


def keyset(*keys, calls=None, clock=time.time):
    def fetch(team):
        if calls is not None:
            calls.append(team)
        return certs_doc(*keys)
    return ra.KeySet(fetch, clock)


class Headers(dict):
    """http.client.HTTPMessage 처럼 이름을 대소문자 가리지 않고 get."""

    def __init__(self, **kw):
        super().__init__({k.replace('_', '-').lower(): v for k, v in kw.items()})

    def get(self, name, default=None):
        return super().get(name.lower(), default)


# ---------------------------------------------------------------- JWT: 허용 1 + 거절 여럿
class JwtTests(unittest.TestCase):
    def setUp(self):
        self.cfg = config()
        self.keys = keyset(KEY_A)

    def reason(self, token, keys=None, now=None):
        with self.assertRaises(ra.AuthError) as cm:
            ra.verify_jwt(token, self.cfg, keys or self.keys, now)
        return cm.exception.reason

    def test_1_valid_token_is_allowed(self):
        p = ra.verify_jwt(make_token(), self.cfg, self.keys)
        self.assertEqual(p['email'], EMAIL)
        self.assertEqual(ra.verify_jwt(make_token(claims={'aud': AUD, 'email': EMAIL.upper()}), self.cfg, self.keys)['aud'], AUD)   # aud 가 글자이거나 이메일 대소문자

    def test_2_tampered_payload_is_refused(self):
        h, p, s = make_token().split('.')
        forged = json.loads(base64.urlsafe_b64decode(p + '=' * (-len(p) % 4)))
        forged['email'] = 'owner@example.com'
        forged['exp'] += 99999
        self.assertEqual(self.reason(h + '.' + b64(json.dumps(forged).encode()) + '.' + s), 'signature')

    def test_3_signed_by_someone_elses_key_is_refused(self):
        self.assertEqual(self.reason(make_token(kid=KEY_A.kid, sign_with=KEY_B)), 'signature')

    def test_4_expired_is_refused(self):
        self.assertEqual(self.reason(make_token(now=time.time() - 7200)), 'expired')

    def test_5_wrong_audience_is_refused(self):
        self.assertEqual(self.reason(make_token(claims={'aud': ['b' * 64]})), 'aud')
        self.assertEqual(self.reason(make_token(claims={'aud': []})), 'aud')

    def test_6_wrong_issuer_is_refused(self):
        self.assertEqual(self.reason(make_token(claims={'iss': 'https://evil.cloudflareaccess.com'})), 'iss')

    def test_7_email_not_on_the_list_is_refused(self):
        self.assertEqual(self.reason(make_token(claims={'email': 'stranger@example.com'})), 'email')
        self.assertEqual(self.reason(make_token(claims={'email': None})), 'email')
        t = make_token()
        h, p, s = t.split('.')
        no_email = json.loads(base64.urlsafe_b64decode(p + '=' * (-len(p) % 4)))
        del no_email['email']                                    # 서비스 토큰에는 이메일이 없다
        signing = h + '.' + b64(json.dumps(no_email).encode())
        self.assertEqual(self.reason(signing + '.' + b64(KEY_A.sign(signing.encode()))), 'email')

    def test_8_forged_alg_is_refused(self):
        self.assertEqual(self.reason(make_token(alg='none')), 'alg')
        # 공개 키를 비밀로 써서 HS256 으로 꾸민 토큰
        signing = b64(json.dumps({'alg': 'HS256', 'kid': KEY_A.kid}).encode()) + '.' + b64(json.dumps({'iss': 'https://' + TEAM, 'aud': [AUD], 'email': EMAIL, 'exp': int(time.time()) + 99}).encode())
        import hmac as _hmac
        mac = _hmac.new(KEY_A.n.to_bytes(128, 'big'), signing.encode(), hashlib.sha256).digest()
        self.assertEqual(self.reason(signing + '.' + b64(mac)), 'alg')

    def test_9_unknown_kid_and_missing_keys_fail_closed(self):
        self.assertEqual(self.reason(make_token(key=KEY_B)), 'unknown_kid')

        def boom(team):
            raise OSError('network down')
        self.assertEqual(self.reason(make_token(), ra.KeySet(boom)), 'keys_unavailable')
        self.assertEqual(self.reason(make_token(), ra.KeySet(lambda t: {'keys': []})), 'keys_unavailable')
        self.assertEqual(self.reason(make_token(), ra.KeySet(lambda t: 'not json shaped')), 'keys_unavailable')

    def test_10_key_cache_one_hour_and_stale_keys_are_not_used_after_failure(self):
        now = [1000.0]
        calls, state = [], {'down': False}

        def fetch(team):
            calls.append(team)
            if state['down']:
                raise OSError('down')
            return certs_doc(KEY_A)
        ks = ra.KeySet(fetch, lambda: now[0])
        tok = make_token(now=1000)
        ra.verify_jwt(tok, self.cfg, ks, 1001)
        ra.verify_jwt(tok, self.cfg, ks, 1002)
        self.assertEqual(len(calls), 1)                                   # 캐시
        state['down'] = True
        now[0] += 1800
        self.assertEqual(ra.verify_jwt(make_token(now=2800), self.cfg, ks, 2801)['email'], EMAIL)   # 캐시가 살아 있는 동안은 받기 실패와 무관
        now[0] += 3600
        with self.assertRaises(ra.AuthError) as cm:
            ra.verify_jwt(make_token(now=now[0]), self.cfg, ks, now[0] + 1)
        self.assertEqual(cm.exception.reason, 'keys_unavailable')         # 만료된 키는 쓰지 않는다

    def test_11_rotated_key_is_picked_up_but_not_hammered(self):
        now = [5000.0]
        have = {'keys': [KEY_A]}
        calls = []

        def fetch(team):
            calls.append(1)
            return certs_doc(*have['keys'])
        ks = ra.KeySet(fetch, lambda: now[0])
        ra.verify_jwt(make_token(now=5000), self.cfg, ks, 5001)
        have['keys'] = [KEY_B, KEY_A]
        now[0] += 120
        self.assertEqual(ra.verify_jwt(make_token(key=KEY_B, now=5120), self.cfg, ks, 5121)['email'], EMAIL)     # 모르는 kid -> 다시 받음
        n = len(calls)
        for _ in range(5):
            with self.assertRaises(ra.AuthError):
                ra.verify_jwt(make_token(key=Rsa(3, kid='zz')), self.cfg, ks, 5122)
        self.assertEqual(len(calls), n)                                   # 같은 1분 안에 되풀이 받지 않는다

    def test_12_not_before_and_malformed(self):
        self.assertEqual(self.reason(make_token(claims={'nbf': int(time.time()) + 3600})), 'not_yet_valid')
        for bad in (None, '', 'a.b', 'a.b.c.d', '..', 'x' * 9000, 'e30.e30.e30', make_token()[:-4] + '!!!!'):
            self.assertIn(self.reason(bad), ('no_token', 'malformed', 'alg', 'bad_base64', 'no_kid', 'signature'), bad)

    def test_rsa_primitive_rejects_odd_signatures(self):
        msg = b'hello'
        sig = KEY_A.sign(msg)
        self.assertTrue(ra.rsa_verify_pkcs1_sha256(KEY_A.n, KEY_A.e, msg, sig))
        self.assertFalse(ra.rsa_verify_pkcs1_sha256(KEY_A.n, KEY_A.e, b'hellp', sig))
        self.assertFalse(ra.rsa_verify_pkcs1_sha256(KEY_A.n, KEY_A.e, msg, sig[:-1]))
        self.assertFalse(ra.rsa_verify_pkcs1_sha256(KEY_A.n, KEY_A.e, msg, b'\x00' * len(sig)))
        self.assertFalse(ra.rsa_verify_pkcs1_sha256(KEY_A.n, 1, msg, sig))

    @unittest.skipUnless(shutil.which('openssl'), 'openssl 이 없어 독립 구현과의 대조는 건너뜀')
    def test_agrees_with_openssl_signatures(self):
        """독립 구현(openssl)이 서명한 것을 이 검증이 받아들이는지: 같은 PKCS#1 v1.5 SHA-256 을 서로 다른 코드가 해석한다."""
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            try:
                subprocess.run(['openssl', 'genrsa', '-out', str(d / 'k.pem'), '2048'], check=True, capture_output=True, timeout=60)
                mod = subprocess.run(['openssl', 'rsa', '-in', str(d / 'k.pem'), '-noout', '-modulus'], check=True, capture_output=True, timeout=30).stdout.decode().strip()
            except (subprocess.SubprocessError, OSError):
                self.skipTest('openssl 이 키를 만들지 못함')
            n = int(mod.split('=')[1], 16)
            (d / 'm.txt').write_bytes(b'header.payload')
            subprocess.run(['openssl', 'dgst', '-sha256', '-sign', str(d / 'k.pem'), '-out', str(d / 's.bin'), str(d / 'm.txt')], check=True, capture_output=True, timeout=30)
            sig = (d / 's.bin').read_bytes()
            self.assertTrue(ra.rsa_verify_pkcs1_sha256(n, 65537, b'header.payload', sig))
            self.assertFalse(ra.rsa_verify_pkcs1_sha256(n, 65537, b'header.payloae', sig))


# ---------------------------------------------------------------- 설정
class ConfigTests(unittest.TestCase):
    def test_missing_or_disabled_means_off(self):
        with tempfile.TemporaryDirectory() as d:
            cf = ra.ConfigFile(Path(d) / 'local-remote.json')
            self.assertFalse(cf.get().enabled)                              # 파일 없음 = 지금과 같다
            (Path(d) / 'local-remote.json').write_text('{"enabled": false, "hosts": ["x.example.com"]}', encoding='utf-8')
            self.assertFalse(cf.get().enabled)
            self.assertEqual(cf.get().problem, '')

    def test_bad_files_are_off_with_a_reason(self):
        for text in ('not json', '[]', '{"enabled": true}', json.dumps({'enabled': True, 'hosts': ['bad host'], 'access': {}}),
                     json.dumps({'enabled': True, 'hosts': [HOST], 'access': {'team_domain': 'evil.example.com', 'aud': AUD, 'emails': [EMAIL]}}),
                     json.dumps({'enabled': True, 'hosts': [HOST], 'access': {'team_domain': TEAM, 'aud': 'zz', 'emails': [EMAIL]}}),
                     json.dumps({'enabled': True, 'hosts': [HOST], 'access': {'team_domain': TEAM, 'aud': AUD, 'emails': ['nope']}})):
            c = ra.parse_config(text)
            self.assertFalse(c.enabled, text)
            self.assertTrue(c.problem, text)

    def test_good_file_and_reload_without_restart(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'local-remote.json'
            p.write_text(json.dumps({'enabled': True, 'hosts': [HOST.upper()], 'access': {'team_domain': TEAM, 'aud': AUD, 'emails': [EMAIL.upper()]},
                                     'remote_allows': ['view', 'local_only']}), encoding='utf-8')
            cf = ra.ConfigFile(p)
            c = cf.get()
            self.assertEqual((c.enabled, c.hosts, c.emails, c.allows, c.issuer), (True, (HOST,), (EMAIL,), ('view',), 'https://' + TEAM))   # local_only 는 허용 목록에 못 넣는다
            p.write_text(json.dumps({'enabled': False}), encoding='utf-8')
            self.assertFalse(cf.get().enabled)
            self.assertEqual(ra.parse_config(json.dumps({'enabled': True, 'hosts': [HOST], 'access': {'team_domain': TEAM, 'aud': AUD, 'emails': [EMAIL]}})).allows, ra.DEFAULT_ALLOWS)


# ---------------------------------------------------------------- 요청 판정
class JudgeTests(unittest.TestCase):
    def setUp(self):
        self.cfg, self.keys = config(), keyset(KEY_A)

    def j(self, cfg=None, method='GET', **h):
        return ra.judge(cfg or self.cfg, self.keys, Headers(**h), method, 8781)

    def test_local_is_what_it_was(self):
        for cfg in (self.cfg, ra.DISABLED):
            self.assertEqual(self.j(cfg, Host='127.0.0.1:8781').kind, 'local')
            self.assertEqual(self.j(cfg, Host='localhost:8781', method='POST', Origin='http://localhost:8781').kind, 'local')
            self.assertEqual(self.j(cfg, Host='127.0.0.1:9999').kind, 'deny')
            self.assertEqual(self.j(cfg, Host='127.0.0.1:8781', method='POST', Origin='http://evil.example').reason, 'origin')
            self.assertEqual(self.j(cfg, Host='127.0.0.1:8781', method='GET', Origin='http://evil.example').kind, 'local')   # GET 은 지금까지 Origin 을 안 봤다(같은 동작)
            self.assertEqual(self.j(cfg, Host='evil.example').kind, 'deny')

    def test_a_request_that_came_through_the_tunnel_is_never_local(self):
        for h in ('Cf-Ray', 'Cf-Connecting-Ip', 'X-Forwarded-For', 'Cf-Visitor'):
            d = ra.judge(self.cfg, self.keys, Headers(**{'Host': '127.0.0.1:8781', h: 'x'}), 'GET', 8781)
            self.assertEqual(d.kind, 'deny', h)

    def test_remote_needs_host_jwt_and_origin(self):
        tok = make_token()
        d = self.j(Host=HOST, Cf_Access_Jwt_Assertion=tok)
        self.assertEqual((d.kind, d.email), ('remote', EMAIL))
        self.assertEqual(self.j(Host=HOST).reason, 'no_token')
        self.assertEqual(self.j(Host='other.example.com', Cf_Access_Jwt_Assertion=tok).reason, 'host')
        self.assertEqual(self.j(ra.DISABLED, Host=HOST, Cf_Access_Jwt_Assertion=tok).kind, 'deny')       # 터널이 떠 있어도 enabled false 면 거절
        self.assertEqual(self.j(method='POST', Host=HOST, Cf_Access_Jwt_Assertion=tok).reason, 'origin')   # POST 는 Origin 이 꼭 있어야
        self.assertEqual(self.j(method='POST', Host=HOST, Origin='https://evil.example', Cf_Access_Jwt_Assertion=tok).reason, 'origin')
        self.assertEqual(self.j(method='POST', Host=HOST, Origin='http://' + HOST, Cf_Access_Jwt_Assertion=tok).reason, 'origin')
        self.assertEqual(self.j(method='POST', Host=HOST, Origin='https://' + HOST, Cf_Access_Jwt_Assertion=tok).kind, 'remote')
        self.assertEqual(self.j(Host=HOST, Cf_Access_Jwt_Assertion=make_token(now=time.time() - 9999)).reason, 'expired')
        self.assertEqual(self.j(Host=HOST.upper(), Cf_Access_Jwt_Assertion=tok).kind, 'remote')           # Host 는 대소문자 무시


class RouteTests(unittest.TestCase):
    def setUp(self):
        self.cfg = config()

    def test_default_table(self):
        C = lambda m, p: ra.route_class(m, p, skill_lab.route_policy)
        self.assertEqual(C('GET', '/api/catalog'), 'view')
        self.assertEqual(C('GET', '/index.html'), 'view')
        self.assertEqual(C('GET', '/files/chapter1/art/x.png'), 'view')
        self.assertEqual(C('GET', '/files/chapter1/core/combat_core.gd'), ra.LOCAL_ONLY)      # 코드 원문
        self.assertEqual(C('GET', '/files/docs/a.md'), ra.LOCAL_ONLY)
        self.assertEqual(C('POST', '/api/characters/frost/open'), ra.LOCAL_ONLY)
        self.assertEqual(C('POST', '/api/characters/frost/tripo_out?name=a.glb'), ra.LOCAL_ONLY)
        self.assertEqual(C('POST', '/api/balance/run'), ra.LOCAL_ONLY)
        self.assertEqual(C('POST', '/api/audit/run'), ra.LOCAL_ONLY)
        self.assertEqual(C('POST', '/api/skill-lab/open'), ra.LOCAL_ONLY)
        self.assertEqual(C('POST', '/api/skill-lab/shot'), ra.LOCAL_ONLY)
        self.assertEqual(C('GET', '/api/skill-lab/shot?name=a'), ra.LOCAL_ONLY)
        self.assertEqual(C('GET', '/api/remote'), ra.LOCAL_ONLY)
        self.assertEqual(C('POST', '/api/skill-lab/clip'), 'skill_lab.clip')
        self.assertEqual(C('POST', '/api/skill-lab/adopt-preview'), 'skill_lab.adopt')
        self.assertEqual(C('POST', '/api/picks'), 'picks')
        self.assertEqual(C('POST', '/api/management'), 'notes')
        self.assertIsNone(C('POST', '/api/nothing'))
        self.assertIsNone(C('DELETE', '/api/catalog'))
        self.assertIsNone(C('GET', '/api/nothing/else'))

    def test_allowed_only_when_listed_and_never_local_only(self):
        A = lambda cls: ra.remote_allowed(self.cfg, cls)
        self.assertTrue(A('view') and A('skill_lab.scene') and A('skill_lab.clip') and A('skill_lab.adopt') and A('picks') and A('notes'))
        self.assertFalse(A('balance.save') or A(ra.LOCAL_ONLY) or A(None))
        narrow = config(remote_allows=['view'])
        self.assertFalse(ra.remote_allowed(narrow, 'skill_lab.adopt'))

    def test_every_skill_lab_route_has_a_class(self):
        for key in skill_lab.ROUTE_POLICY:
            self.assertIsNotNone(ra.route_class(key[0], key[1], skill_lab.route_policy), key)


# ---------------------------------------------------------------- 서버에 붙였을 때
class ServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        t = Path(cls.tmp.name)
        cls.saved = (server.REMOTE, server.KEYS, server.REMOTE_LOG, picks.STORE)
        cls.cfg_path = t / 'local-remote.json'
        server.REMOTE = ra.ConfigFile(cls.cfg_path)
        server.KEYS = keyset(KEY_A)
        server.REMOTE_LOG = t / 'remote-access.log'
        picks.STORE = t / 'picks.json'
        cls.server = server.make_server(0)
        cls.port = cls.server.server_port
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        server.REMOTE, server.KEYS, server.REMOTE_LOG, picks.STORE = cls.saved
        cls.tmp.cleanup()

    def setUp(self):
        self.write_cfg()
        server.REMOTE_LOG.unlink(missing_ok=True)

    def write_cfg(self, **kw):
        d = {'enabled': True, 'hosts': [HOST], 'access': {'team_domain': TEAM, 'aud': AUD, 'emails': [EMAIL]}}
        d.update(kw)
        self.cfg_path.write_text(json.dumps(d), encoding='utf-8')

    def req(self, path, body=None, host=None, token='default', origin='default', extra=None, method=None):
        h = {'Host': host or HOST}
        if token == 'default':
            token = make_token() if host in (None, HOST) else None
        if token:
            h['Cf-Access-Jwt-Assertion'] = token
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            h['Content-Type'] = 'application/json'
            h['Origin'] = ('https://' + (host or HOST)) if origin == 'default' else origin
        h.update(extra or {})
        h = {k: v for k, v in h.items() if v is not None}
        r = urllib.request.Request('http://127.0.0.1:%d%s' % (self.port, path), data=data, headers=h, method=method)
        try:
            with urllib.request.urlopen(r) as resp:
                return resp.status, resp.read()
        except urllib.error.HTTPError as e:
            return e.code, e.read()

    def local(self, path, body=None):
        return self.req(path, body, host='127.0.0.1:%d' % self.port, token=None, origin='http://127.0.0.1:%d' % self.port)

    def log(self):
        return server.REMOTE_LOG.read_text(encoding='utf-8') if server.REMOTE_LOG.exists() else ''

    def test_without_a_config_file_nothing_changes(self):
        self.cfg_path.unlink()
        self.assertEqual(self.req('/api/catalog')[0], 403)
        self.assertEqual(self.req('/api/catalog', host='127.0.0.1:%d' % self.port, token=None)[0], 200)
        st, body = self.req('/api/catalog')
        self.assertEqual(json.loads(body), {'error': 'Untrusted Host'})                 # 지금과 같은 거절 문구
        self.write_cfg()

    def test_disabled_config_is_the_same_as_none(self):
        self.write_cfg(enabled=False)
        self.assertEqual(self.req('/api/catalog')[0], 403)
        self.assertEqual(self.local('/api/catalog')[0], 200)

    def test_remote_view_works_with_a_good_token(self):
        for path in ('/api/catalog', '/api/skill-lab', '/api/picks', '/api/tools'):
            self.assertEqual(self.req(path)[0], 200, path)
        st, body = self.req('/index.html')
        self.assertEqual(st, 200)
        self.assertIn(b'<body data-remote="1"', body)                                   # 화면이 원격임을 안다
        st, body = self.local('/index.html')
        self.assertNotIn(b'data-remote', body)

    def test_remote_without_or_with_bad_token_is_403(self):
        self.assertEqual(self.req('/api/catalog', token=None)[0], 403)
        self.assertEqual(self.req('/api/catalog', token=make_token(now=time.time() - 9999))[0], 403)
        self.assertEqual(self.req('/api/catalog', token=make_token(claims={'email': 'x@example.com'}))[0], 403)
        self.assertEqual(self.req('/api/catalog', host='evil.example.com')[0], 403)
        text = self.log()
        self.assertIn('denied:expired', text)
        self.assertIn('denied:email', text)
        self.assertIn('denied:no_token', text)

    def test_post_needs_the_https_origin_of_the_host(self):
        self.assertEqual(self.req('/api/picks', {'revision': 0}, origin='https://evil.example.com')[0], 403)
        self.assertEqual(self.req('/api/picks', {'revision': 0}, origin=None)[0], 403)

    def test_blocked_routes_are_blocked_for_real(self):
        blocked = [('/api/characters/frost/open', {'folder': 'tripo_in'}), ('/api/characters/frost/tripo_out?name=a.glb', {}),
                   ('/api/balance/run', {}), ('/api/audit/run', {}), ('/api/skill-lab/open', {}), ('/api/skill-lab/shot', {'name': 'x'})]
        for path, body in blocked:
            self.assertEqual(self.req(path, body)[0], 403, path)
        self.assertEqual(self.req('/api/skill-lab/shot?name=x')[0], 403)
        self.assertEqual(self.req('/files/chapter1/core/combat_core.gd')[0], 403)
        self.assertEqual(self.req('/files/docs/DIRECTOR-PLAN.ko.md')[0], 403)
        self.assertEqual(self.req('/api/remote')[0], 403)
        self.assertEqual(self.req('/api/unknown-thing')[0], 403)                          # 모르는 경로는 원격에서 닫힌 쪽
        text = self.log()
        self.assertEqual(text.count('denied:route'), 11, text)

    def test_the_same_routes_are_not_blocked_locally(self):
        st, body = self.local('/api/characters/nope/open', {'folder': 'tripo_in'})
        self.assertEqual(st, 404)                                                         # 로컬은 지금까지처럼 길이 열려 있다(없는 줄이라 404)
        self.assertEqual(self.local('/api/skill-lab/open', {})[0] in (400, 404), True)
        self.assertEqual(self.local('/files/chapter1/core/combat_core.gd')[0] in (200, 404), True)

    def test_allows_list_is_enforced(self):
        self.write_cfg(remote_allows=['view'])
        self.assertEqual(self.req('/api/picks', {'revision': 0, 'action': 'add', 'record': {}})[0], 403)
        self.assertEqual(self.req('/api/skill-lab/adopt', {})[0], 403)
        self.assertEqual(self.req('/api/skill-lab/clip', {})[0], 403)
        self.assertEqual(self.req('/api/catalog')[0], 200)
        self.assertIn('denied:route', self.log())

    def test_allowed_write_is_logged_with_the_email_and_no_token(self):
        rec = {'screen': 'skill', 'subject': 'skill/x/sound/y', 'verdict': 'note', 'note': '원격에서 남긴 말'}
        st, body = self.req('/api/picks', {'revision': 0, 'action': 'add', 'record': rec})
        self.assertEqual(st, 200)
        text = self.log()
        self.assertIn('\t%s\tPOST\t/api/picks\tok' % EMAIL, text)
        tok = make_token()
        self.req('/api/catalog?x=' + tok[:40], token=tok)
        self.assertNotIn(tok[:30], self.log())                                           # 토큰·쿼리는 기록에 없다
        recs = json.loads(picks.STORE.read_text(encoding='utf-8'))['records']
        self.assertEqual(list(recs.values())[0]['by'], 'user(remote:%s)' % EMAIL)       # 고름의 by 에 원격 이메일

    def test_edge_headers_make_a_loopback_host_remote_not_local(self):
        st, _ = self.req('/api/catalog', host='127.0.0.1:%d' % self.port, token=None, extra={'Cf-Ray': 'abc'})
        self.assertEqual(st, 403)

    def test_remote_status_endpoint_is_local_only_and_has_no_secrets(self):
        self.req('/api/catalog')
        st, body = self.local('/api/remote')
        d = json.loads(body)
        self.assertEqual(st, 200)
        self.assertEqual((d['enabled'], d['hosts']), (True, [HOST]))
        self.assertEqual(d['last']['email'], EMAIL)
        self.assertNotIn(AUD, body.decode())
        self.write_cfg(enabled=False)
        self.assertFalse(json.loads(self.local('/api/remote')[1])['enabled'])
        self.cfg_path.write_text('{broken', encoding='utf-8')
        d = json.loads(self.local('/api/remote')[1])
        self.assertFalse(d['enabled'])
        self.assertTrue(d['problem'])

    def test_server_still_binds_loopback_only(self):
        self.assertEqual(self.server.server_address[0], '127.0.0.1')


class ScriptTests(unittest.TestCase):
    PS1 = Path(__file__).resolve().parent / 'remote.ps1'

    def test_script_never_downloads_installs_or_logs_in(self):
        text = self.PS1.read_text(encoding='utf-8-sig')
        self.assertTrue(self.PS1.read_bytes().startswith(b'\xef\xbb\xbf'))           # Windows PowerShell 5.1 이 한글을 바로 읽게 BOM
        code = '\n'.join(l for l in text.splitlines() if not l.lstrip().startswith('#'))          # 주석의 설명은 빼고 실제 줄만
        for forbidden in ('Invoke-WebRequest', 'Invoke-RestMethod', 'Start-BitsTransfer', 'iwr ', 'curl ', 'tunnel login', 'tunnel create', 'service install'):
            self.assertFalse(forbidden in code, forbidden)
        for line in code.splitlines():
            if 'winget install' in line:
                self.assertIn('사용자가 직접', line)                                     # 설치는 안내 글로만 있다

    @unittest.skipUnless(shutil.which('powershell'), 'powershell 이 없음')
    def test_status_changes_nothing_and_exits_zero(self):
        done = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(self.PS1), 'status', '-Port', '1'],
                              capture_output=True, timeout=60)
        self.assertEqual(done.returncode, 0, done.stderr.decode('utf-8', 'replace')[:300])


if __name__ == '__main__':
    unittest.main()
