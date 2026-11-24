#!/usr/bin/env python3
"""tripo_api.py 자체 검사. 실행: python tools/art/test_tripo_api.py
네트워크 없음: http_request를 가짜로 바꿔 끼운다. 가짜 키만 쓰고 실제 .env·크레딧·저장은 건드리지 않는다."""
import contextlib
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tripo_api as T  # noqa: E402

FAKE_KEY = "tsk_FAKEKEY_0123456789abcdef"
PNG = b"\x89PNG\r\n\x1a\n" + b"\0" * 32


class FakeNet:
    """Records every call; answers like the API. `leak` makes error bodies echo the Authorization header (to test redaction)."""

    def __init__(self, balance=1000.0, leak=False):
        self.calls = []
        self.balance = balance
        self.leak = leak

    def __call__(self, method, url, headers, body=None, timeout=60.0, max_bytes=None):
        self.calls.append((method, url, dict(headers)))
        path = url.split("/v3", 1)[-1] if "/v3" in url else url
        if self.leak:
            return 403, {}, json.dumps({"code": 2, "message": "bad " + headers.get("Authorization", "")}).encode()
        ok = lambda data: (200, {}, json.dumps({"code": 0, "data": data}).encode())  # noqa: E731
        if path == "/account/balance":
            return ok({"balance": self.balance, "frozen": 0})
        if path == "/files":
            return ok({"file_token": "file_x"})
        if path == "/generation/image-to-model":
            return ok({"task_id": "abcdef12-0000"})
        if path.startswith("/tasks/"):
            return ok({"status": "success", "progress": 100, "credits_consumed": 50, "output": {"model_url": "https://cdn.example/out/m.glb"}})
        if url.startswith("https://cdn.example/"):
            return 200, {}, b"glTF-fake"
        return 404, {}, b"{}"

    def spent(self):
        return [c for c in self.calls if c[0] == "POST" and "/generation/" in c[1]]


def run(argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = T.main(argv)
    return code, out.getvalue(), err.getvalue()


class TripoTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="tripo_test_"))
        self.env = self.tmp / ".env"
        self.env.write_text("OTHER=1\nTRIPO_API_KEY=%s\n" % FAKE_KEY, encoding="utf-8")
        self._saved = (T.ENV_FILE, T.LOCAL_ROOT, T.http_request, dict(os.environ))
        T.ENV_FILE = self.env
        T.LOCAL_ROOT = self.tmp / "_local"
        T.LOCAL_ROOT.mkdir()
        for k in ("TRIPO_API_KEY", "TRIPO_REGION"):
            os.environ.pop(k, None)
        os.environ["MOIRA_WORK_ROOT"] = str(self.tmp / "work")
        T._KEY_CACHE.clear()
        self.img = self.tmp / "a.png"
        self.img.write_bytes(PNG)

    def tearDown(self):
        T.ENV_FILE, T.LOCAL_ROOT, T.http_request = self._saved[:3]
        os.environ.clear()
        os.environ.update(self._saved[3])
        shutil.rmtree(self.tmp, ignore_errors=True)

    def net(self, **kw):
        n = FakeNet(**kw)
        T.http_request = n
        return n

    # --- estimate
    def test_estimate_table(self):
        def total(*a):
            code, out, _ = run(["estimate", "--kind", "image", *a])
            self.assertEqual(code, 0)
            return int(out.strip().splitlines()[-1].split()[-1])
        self.assertEqual(total("--texture", "none"), 20)
        self.assertEqual(total(), 30)
        self.assertEqual(total("--texture", "hd"), 40)
        self.assertEqual(total("--texture", "ultra"), 50)
        self.assertEqual(total("--hd-geometry", "--texture", "hd"), 60)
        self.assertEqual(total("--hd-geometry", "--texture", "hd", "--low-poly"), 70)
        self.assertEqual(total("--texture", "none", "--parts"), 40)
        self.assertEqual(total("--quad"), 35)
        self.assertEqual(total("--rig", "--retarget", "3"), 30 + 25 + 30)

    def test_parts_rules(self):
        code, _, err = run(["estimate", "--kind", "image", "--parts"])
        self.assertEqual(code, 2)
        code, _, _ = run(["estimate", "--kind", "multiview", "--parts", "--texture", "none", "--quad"])
        self.assertEqual(code, 2)

    # --- confirm-credits gate
    def test_confirm_mismatch_never_calls(self):
        n = self.net()
        out = self.tmp / "_local" / "o"
        base = ["image-to-model", "--image", str(self.img), "--out", str(out), "--texture", "hd", "--hd-geometry"]
        for extra in ([], ["--confirm-credits", "59"], ["--confirm-credits", "61"]):
            code, stdout, _ = run(base + extra)
            self.assertEqual(code, 2)
            self.assertIn("60", stdout)
        self.assertEqual(n.calls, [])
        self.assertFalse(out.exists())

    def test_insufficient_balance_stops(self):
        n = self.net(balance=10)
        code, _, err = run(["image-to-model", "--image", str(self.img), "--out", str(self.tmp / "_local" / "o"), "--confirm-credits", "30"])
        self.assertEqual(code, 3)
        self.assertEqual(n.spent(), [])
        self.assertFalse([c for c in n.calls if c[1].endswith("/files")])

    def test_full_flow_fake(self):
        n = self.net()
        out = self.tmp / "_local" / "o"
        code, stdout, err = run(["image-to-model", "--image", str(self.img), "--out", str(out), "--confirm-credits", "30", "--poll", "0"])
        self.assertEqual(code, 0, err)
        self.assertEqual(len(n.spent()), 1)
        rec = json.loads((out / "tripo_task.json").read_text(encoding="utf-8"))
        self.assertEqual(rec["task_id"], "abcdef12-0000")
        self.assertEqual(rec["estimate"]["total"], 30)
        self.assertEqual(rec["files"][0]["bytes"], len(b"glTF-fake"))
        self.assertEqual(len(rec["files"][0]["sha256"]), 64)
        self.assertEqual(rec["params"]["model"], T.DEFAULT_MODEL)
        # the CDN download carries no key
        cdn = [c for c in n.calls if c[1].startswith("https://cdn.example/")]
        self.assertTrue(cdn)
        self.assertNotIn("Authorization", cdn[0][2])

    # --- key never appears
    def test_key_not_in_outputs(self):
        self.net(leak=True)
        out = self.tmp / "_local" / "o"
        for argv in (["balance"], ["task", "--id", "x"], ["image-to-model", "--image", str(self.img), "--out", str(out), "--confirm-credits", "30"]):
            code, stdout, err = run(argv)
            self.assertNotEqual(code, 0)
            self.assertNotIn(FAKE_KEY, stdout + err)
        self.assertFalse(out.exists() and any(FAKE_KEY in p.read_text(encoding="utf-8", errors="replace") for p in out.rglob("*") if p.is_file()))
        self.assertNotIn(FAKE_KEY, T.redact("x %s y" % FAKE_KEY))

    def test_key_not_in_record(self):
        self.net()
        out = self.tmp / "_local" / "o"
        run(["image-to-model", "--image", str(self.img), "--out", str(out), "--confirm-credits", "30", "--poll", "0"])
        for p in out.rglob("*"):
            if p.is_file():
                self.assertNotIn(FAKE_KEY.encode(), p.read_bytes())

    def test_balance_prints_numbers_and_header_only_on_request(self):
        n = self.net(balance=123.5)
        code, out, _ = run(["balance"])
        self.assertEqual(code, 0)
        self.assertIn("balance=123.5", out)
        self.assertEqual(n.calls[0][2]["Authorization"], "Bearer " + FAKE_KEY)
        self.assertEqual(n.calls[0][2]["User-Agent"], T.USER_AGENT)

    # --- paths
    def test_output_path_restricted(self):
        n = self.net()
        for bad in (str(self.tmp / "elsewhere"), str(self.tmp / "_local" / ".." / "x"), "C:/Windows/Temp/x"):
            code, _, err = run(["image-to-model", "--image", str(self.img), "--out", bad, "--confirm-credits", "30"])
            self.assertEqual(code, 2, bad)
        self.assertEqual(n.calls, [])
        ok = T.checked_out_dir(str(self.tmp / "work" / "pipeline" / "x" / "tripo_out"))
        self.assertTrue(str(ok).endswith("tripo_out"))
        self.assertTrue(T.checked_out_dir(str(self.tmp / "_local" / "a")).name == "a")

    def test_no_user_info_in_request_headers(self):
        n = self.net()
        run(["balance"])
        text = json.dumps(n.calls[0][2]).lower()
        for word in ("twins", "moira", "choi", "@"):
            self.assertNotIn(word, text)


if __name__ == "__main__":
    unittest.main(verbosity=1)
