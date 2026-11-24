#!/usr/bin/env python3
"""Tripo API client for 3D model generation (image to 3D, rig, retarget). Standard library only, Python 3.10.

  python tools/art/tripo_api.py balance
  python tools/art/tripo_api.py estimate --kind image [--hd-geometry] [--texture standard|hd|ultra|none] [--low-poly] [--quad] [--parts] [--rig] [--retarget N]
  python tools/art/tripo_api.py image-to-model --image X.png --out DIR [same options] --confirm-credits N
  python tools/art/tripo_api.py task --id TASK_ID [--out DIR]
  python tools/art/tripo_api.py rig --task TASK_ID --out DIR --confirm-credits 25
  python tools/art/tripo_api.py retarget --task RIG_TASK_ID --animation preset:idle [--animation ...] --out DIR --confirm-credits N

Rules.
- COSTS CREDITS: image-to-model, rig, retarget. They run only when --confirm-credits equals the estimate this tool computes
  (otherwise it prints the estimate and exits 2), and only when the balance read just before the call covers it. The approval of
  the spend is the director's, taken from the user per call. balance, estimate and task cost nothing.
- Key: TRIPO_API_KEY from the repository-root .env (or the process environment), read inside this process only and sent only in the
  Authorization header of requests to the Tripo API host. It is never printed, logged, written to a file or put in an error text
  (every message is passed through redact()). Downloads from the CDN carry no key. Redirects are not followed.
- Region: TRIPO_REGION (.env or environment) or --region: ov = international (openapi.tripo3d.ai), cn = China (openapi.tripo3d.com).
  Default ov. `balance` tries the other region when the key is refused and tells which one worked (the region name only).
- Output folders are restricted to <repo>/_local/ or <work root>/pipeline/ (work root = MOIRA_WORK_ROOT or D:/Project/witch-moira-work;
  same convention as tools/manager/characters.py: pipeline/<id>/tripo_in, tripo_out).
- Nothing about the user or the project goes into a request. User-Agent is generic.
- New assets that come out of this tool go into the provenance ledger (tools/art/asset_ledger.py) before they ship;
  <out>/tripo_task.json holds model, parameters, date, credits and sha256 for that entry. Generated files are not "shippable" until then.

Sources (read 2026-11-24): https://platform.tripo3d.ai/docs (a script-rendered page; its text is the same corpus as
https://developers.tripo3d.com/llms-full.txt, whose pages are listed in /llms.txt) and https://developers.tripo3d.com/en/pricing.
  Base URL /v3; Authorization: Bearer; envelope {"code":0,"data":{...}}; errors {"code","message","suggestion"}.
  GET /account/balance -> data.balance, data.frozen.            POST /files (multipart "file", PNG/JPEG <= 20 MB) -> data.file_token.
  POST /generation/image-to-model (H series): input, model v3.1-20260211 | v3.0-20250812 | v2.5-20250123, texture, pbr,
     texture_quality fast|standard|detailed|extreme, geometry_quality standard|detailed, face_limit, quad, smart_low_poly,
     generate_parts (only with texture=false, pbr=false, no quad, no smart_low_poly). The last five need model >= v3.0.
  POST /generation/multiview-to-model has the same options (estimate only here; no command calls it).
  GET /tasks/{id} -> status queued|running|success|failed|cancelled, progress, output.model_url, credits_consumed, error_code.
  POST /animations/rig (input task_id; model, rig_type, spec, out_format).  POST /animations/retarget (input = rig task id,
     animation | animations (<= 5), out_format).  Credits are frozen at creation and returned if the task fails or is cancelled.
Prices (the PRICES table below): 2026-11-24 official price table. Adds on top of the base: HD texture (detailed) +10, 8K Ultra
texture (extreme) +20, HD geometry (geometry_quality detailed) +20, quad +5, smart low-poly +10, generate parts +20.
Not confirmed by the documents: whether face_limit changes the price of a generation (the price page lists it only as a trigger
of the Advanced convert price); the price of texture_quality fast (documented as the same as standard; not offered here).
quad forces an FBX output (documented), so the downloaded file may not be .glb.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ENV_FILE = REPO / ".env"
LOCAL_ROOT = REPO / "_local"
USER_AGENT = "asset-pipeline-client/1.0"
TOOL = "tools/art/tripo_api.py"

HOSTS = {"ov": "https://openapi.tripo3d.ai/v3", "cn": "https://openapi.tripo3d.com/v3"}
DEFAULT_MODEL = "v3.1-20260211"
DEFAULT_RIG_MODEL = "v3.0-20260909"
MAX_IMAGE_BYTES = 20 * 1024 * 1024
MAX_DOWNLOAD_BYTES = 300 * 1024 * 1024
POLL_SECONDS = 6.0
TIMEOUT_SECONDS = 900.0

# 2026-11-24 official price table (credits). One table; everything else reads it.
PRICES = {
    "read_on": "2026-11-24",
    "base_no_texture": 20,
    "base_texture": 30,
    "texture_hd": 10,      # texture_quality detailed
    "texture_ultra": 20,   # texture_quality extreme
    "geometry_hd": 20,     # geometry_quality detailed
    "quad": 5,
    "low_poly": 10,        # smart_low_poly
    "parts": 20,           # generate_parts
    "rig": 25,
    "retarget_each": 10,
    "rig_check": 0,
    "convert_basic": 5,
    "convert_advanced": 10,
}
TEXTURE_QUALITY = {"standard": "standard", "hd": "detailed", "ultra": "extreme"}
STATUS_DONE = ("failed", "cancelled", "banned", "expired")

EXIT_OK, EXIT_ERROR, EXIT_REFUSED, EXIT_BALANCE, EXIT_PENDING = 0, 1, 2, 3, 4


class TripoError(Exception):
    pass


class Refused(Exception):
    """Usage or safety refusal (exit 2)."""


# ------------------------------------------------------------------ key and redaction
_KEY_CACHE: dict = {}


def load_key() -> tuple[str, str]:
    """(key, region). The key comes from the process environment, else from ENV_FILE. Never printed."""
    key = os.environ.get("TRIPO_API_KEY", "").strip()
    region = os.environ.get("TRIPO_REGION", "").strip()
    if (not key or not region) and ENV_FILE.is_file():
        for raw in ENV_FILE.read_text(encoding="utf-8", errors="replace").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            name, _, value = line.partition("=")
            name = name.strip()
            if name.lower().startswith("export "):
                name = name[7:].strip()
            value = value.strip().strip("'\"")
            if name == "TRIPO_API_KEY" and not key:
                key = value
            elif name == "TRIPO_REGION" and not region:
                region = value
    if not key:
        raise TripoError("TRIPO_API_KEY가 .env(또는 환경 변수)에 없다")
    _KEY_CACHE["key"] = key
    region = region.lower() or "ov"
    if region not in HOSTS:
        raise TripoError("TRIPO_REGION은 ov 또는 cn")
    return key, region


def redact(text) -> str:
    s = str(text)
    key = _KEY_CACHE.get("key")
    if key:
        s = s.replace(key, "[key]")
    return s


# ------------------------------------------------------------------ http (single choke point; tests replace it)
class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


def http_request(method: str, url: str, headers: dict, body: bytes | None = None, timeout: float = 60.0, max_bytes: int | None = None):
    """-> (status, response headers dict, bytes). HTTP error statuses are returned, not raised."""
    req = urllib.request.Request(url, data=body, method=method, headers=dict(headers))
    opener = urllib.request.build_opener(_NoRedirect)
    try:
        with opener.open(req, timeout=timeout) as resp:
            data = resp.read(max_bytes + 1) if max_bytes else resp.read()
            if max_bytes and len(data) > max_bytes:
                raise TripoError("응답이 너무 크다")
            return resp.status, dict(resp.headers), data
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers or {}), e.read(1 << 20)
    except urllib.error.URLError as e:
        raise TripoError("연결 실패: " + redact(e.reason))


class Client:
    def __init__(self, key: str, region: str):
        self.key = key
        self.region = region
        self.base = HOSTS[region]

    def _headers(self, extra: dict | None = None) -> dict:
        h = {"Authorization": "Bearer " + self.key, "User-Agent": USER_AGENT, "Accept": "application/json"}
        h.update(extra or {})
        return h

    def call(self, method: str, path: str, payload: dict | None = None, multipart: tuple | None = None, retries: int = 3) -> dict:
        """One API call -> the `data` object. Only GET is retried (429/5xx); a create is never repeated."""
        headers, body = self._headers(), None
        if payload is not None:
            headers["Content-Type"] = "application/json"
            body = json.dumps(payload).encode("utf-8")
        elif multipart is not None:
            body, ctype = multipart_body(*multipart)
            headers["Content-Type"] = ctype
        attempt = 0
        while True:
            status, resp_headers, raw = http_request(method, self.base + path, headers, body)
            if method == "GET" and status in (429, 500, 502, 503, 504) and attempt < retries:
                time.sleep(min(2 ** attempt, 8))
                attempt += 1
                continue
            break
        try:
            doc = json.loads(raw.decode("utf-8", errors="replace"))
        except ValueError:
            raise TripoError("HTTP %d, JSON이 아님: %s" % (status, redact(raw[:200].decode("utf-8", errors="replace"))))
        if status != 200 or doc.get("code", 0) != 0:
            raise TripoError("HTTP %d, code %s: %s%s" % (status, doc.get("code"), redact(doc.get("message", "")),
                                                          (" / " + redact(doc["suggestion"])) if doc.get("suggestion") else ""))
        return doc.get("data") or {}

    def balance(self) -> dict:
        return self.call("GET", "/account/balance")

    def upload_image(self, path: Path) -> str:
        data = self.call("POST", "/files", multipart=("file", "image" + path.suffix.lower(), path.read_bytes()))
        token = data.get("file_token")
        if not token:
            raise TripoError("file_token이 응답에 없다")
        return token

    def task(self, task_id: str) -> dict:
        return self.call("GET", "/tasks/" + task_id)


def multipart_body(field: str, filename: str, content: bytes) -> tuple[bytes, str]:
    boundary = "----tripo" + uuid.uuid4().hex
    ctype = "image/png" if filename.endswith(".png") else "image/jpeg"
    head = ('--%s\r\nContent-Disposition: form-data; name="%s"; filename="%s"\r\nContent-Type: %s\r\n\r\n'
            % (boundary, field, filename, ctype)).encode("ascii")
    return head + content + ("\r\n--%s--\r\n" % boundary).encode("ascii"), "multipart/form-data; boundary=" + boundary


# ------------------------------------------------------------------ estimate
def build_params(opt) -> dict:
    """The request fields (without input) for a generation, from the CLI options. Raises Refused on a combination the docs reject."""
    texture = opt.texture != "none"
    if opt.parts and (texture or opt.quad or opt.low_poly):
        raise Refused("--parts는 --texture none 이고 --quad·--low-poly 없이만 가능(문서: generate_parts는 texture·pbr·quad·smart_low_poly와 함께 못 씀)")
    if opt.face_limit is not None:
        lo, hi = (500, 10000 if opt.quad else 20000) if opt.low_poly else (1, 150000 if opt.quad else 2000000)
        if not lo <= opt.face_limit <= hi:
            raise Refused("--face-limit은 %d~%d" % (lo, hi))
    p: dict = {"model": getattr(opt, "model", DEFAULT_MODEL), "texture": texture, "pbr": texture and not getattr(opt, "no_pbr", False)}
    if texture:
        p["texture_quality"] = TEXTURE_QUALITY[opt.texture]
    if opt.hd_geometry:
        p["geometry_quality"] = "detailed"
    if opt.quad:
        p["quad"] = True
    if opt.low_poly:
        p["smart_low_poly"] = True
    if opt.parts:
        p["generate_parts"] = True
    if opt.face_limit is not None:
        p["face_limit"] = opt.face_limit
    return p


def estimate_lines(opt, include_generation: bool = True) -> list[tuple[str, int]]:
    lines: list[tuple[str, int]] = []
    if include_generation:
        build_params(opt)  # validates
        texture = opt.texture != "none"
        lines.append(("%s → 3D, 텍스처 %s" % ("그림" if opt.kind == "image" else "다면", "표준" if texture else "없음"),
                      PRICES["base_texture"] if texture else PRICES["base_no_texture"]))
        if opt.texture == "hd":
            lines.append(("HD 텍스처", PRICES["texture_hd"]))
        if opt.texture == "ultra":
            lines.append(("8K Ultra 텍스처", PRICES["texture_ultra"]))
        if opt.hd_geometry:
            lines.append(("HD 형태", PRICES["geometry_hd"]))
        if opt.quad:
            lines.append(("사각 메시", PRICES["quad"]))
        if opt.low_poly:
            lines.append(("저폴리", PRICES["low_poly"]))
        if opt.parts:
            lines.append(("부품 생성", PRICES["parts"]))
    if getattr(opt, "rig", False):
        lines.append(("자동 리그", PRICES["rig"]))
    n = getattr(opt, "retarget", 0) or 0
    if n:
        lines.append(("동작 옮기기 %d개 × %d" % (n, PRICES["retarget_each"]), n * PRICES["retarget_each"]))
    return lines


def print_estimate(lines: list[tuple[str, int]], title: str = "견적") -> int:
    total = sum(c for _, c in lines)
    print("%s (값표 읽은 날 %s, 1크레딧 = 0.01달러)" % (title, PRICES["read_on"]))
    for name, cost in lines:
        print("  %-28s %5d" % (name, cost))
    print("  %-28s %5d" % ("합계", total))
    return total


# ------------------------------------------------------------------ paths and files
def work_root() -> Path:
    return Path(os.environ.get("MOIRA_WORK_ROOT") or "D:/Project/witch-moira-work")


def checked_out_dir(path: str) -> Path:
    p = Path(path)
    if not p.is_absolute():
        p = Path.cwd() / p
    p = Path(os.path.normpath(p)).resolve()
    for root in (LOCAL_ROOT, work_root() / "pipeline"):
        try:
            p.relative_to(root.resolve())
            return p
        except ValueError:
            continue
    raise Refused("출력 폴더는 %s 또는 %s 아래만 허용한다: %s" % (LOCAL_ROOT.as_posix(), (work_root() / "pipeline").as_posix(), p.as_posix()))


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def now() -> str:
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def write_record(out: Path, name: str, rec: dict) -> None:
    out.mkdir(parents=True, exist_ok=True)
    tmp = out / (name + ".tmp")
    tmp.write_text(json.dumps(rec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, out / name)


def download_outputs(task: dict, out: Path, task_id: str) -> list[dict]:
    """Download output.model_url (+ rendered_image_url) with no key. Never overwrites a file with another content."""
    from urllib.parse import urlparse
    files = []
    output = task.get("output") or {}
    for field in ("model_url", "rendered_image_url"):
        url = output.get(field)
        if not url:
            continue
        ext = Path(urlparse(url).path).suffix.lower() or (".glb" if field == "model_url" else ".png")
        name = ("model_%s%s" if field == "model_url" else "preview_%s%s") % (task_id[:8], ext)
        status, _, data = http_request("GET", url, {"User-Agent": USER_AGENT}, None, 300.0, MAX_DOWNLOAD_BYTES)
        if status != 200 or not data:
            raise TripoError("%s 내려받기 실패(HTTP %s)" % (field, status))
        out.mkdir(parents=True, exist_ok=True)
        target = out / name
        tmp = out / (name + ".part")
        tmp.write_bytes(data)
        os.replace(tmp, target)
        files.append({"name": name, "field": field, "bytes": len(data), "sha256": sha256_of(target), "host": urlparse(url).hostname})
    return files


def wait_for_task(client: Client, task_id: str, interval: float, timeout: float) -> dict:
    """Poll until a terminal status. Returns the task; raises TimeoutError when the limit passes (the task stays on the server)."""
    start = time.monotonic()
    while True:
        task = client.task(task_id)
        status = task.get("status")
        print("  [%s] %s %s%%" % (task_id[:8], status, task.get("progress", 0)), flush=True)
        if status == "success" or status in STATUS_DONE:
            return task
        if time.monotonic() - start > timeout:
            raise TimeoutError(task_id)
        time.sleep(interval)


# ------------------------------------------------------------------ commands
def make_client(opt) -> Client:
    key, region = load_key()
    return Client(key, opt.region or region)


def cmd_balance(opt) -> int:
    key, region = load_key()
    want = opt.region or region
    for r in [want] + [x for x in HOSTS if x != want]:
        try:
            b = Client(key, r).balance()
        except TripoError as e:
            msg = str(e)
            print("balance 실패(지역 %s): %s" % (r, msg), file=sys.stderr)
            if "HTTP 401" not in msg and "HTTP 403" not in msg:
                return EXIT_ERROR
            continue
        print("balance=%s frozen=%s region=%s%s" % (b.get("balance"), b.get("frozen"), r, "" if r == want else " (설정값 %s와 다름: .env에 TRIPO_REGION=%s를 적을 것)" % (want, r)))
        return EXIT_OK
    return EXIT_ERROR


def cmd_estimate(opt) -> int:
    print_estimate(estimate_lines(opt))
    return EXIT_OK


def guard_spend(client: Client, lines: list[tuple[str, int]], confirm) -> tuple[int, dict | None]:
    """Prints the estimate; returns (exit code, balance before). Exit code != 0 means: do not call."""
    total = print_estimate(lines)
    if confirm is None or abs(float(confirm) - total) > 1e-9:
        print("--confirm-credits %s가 견적 %d와 다르다(또는 없다). 호출하지 않는다." % (confirm if confirm is not None else "없음", total), file=sys.stderr)
        return EXIT_REFUSED, None
    b = client.balance()
    avail = float(b.get("balance", 0))
    print("호출 전 잔액 %.2f (동결 %.2f)" % (avail, float(b.get("frozen", 0))))
    if avail < total:
        print("잔액이 모자라 멈춘다(필요 %d)." % total, file=sys.stderr)
        return EXIT_BALANCE, b
    return EXIT_OK, b


def finish_task(client: Client, opt, out: Path, record_name: str, rec: dict, task_id: str, bal_before: dict) -> int:
    write_record(out, record_name, rec)  # the id is on disk before the wait
    try:
        task = wait_for_task(client, task_id, opt.poll, opt.timeout)
    except TimeoutError:
        rec["status"] = "timeout"
        rec["note"] = "시간 제한 안에 끝나지 않았다. python tools/art/tripo_api.py task --id %s --out <폴더> 로 이어서 본다" % task_id
        write_record(out, record_name, rec)
        print("시간 제한(%ds). 작업 id %s는 기록해 두었다." % (opt.timeout, task_id), file=sys.stderr)
        return EXIT_PENDING
    rec["status"] = task.get("status")
    rec["credits_consumed"] = task.get("credits_consumed")
    rec["completed_at"] = task.get("completed_at")
    if task.get("status") != "success":
        rec["error"] = {"code": task.get("error_code"), "message": redact(task.get("error_message", ""))}
        write_record(out, record_name, rec)
        print("작업 실패: %s %s (동결 크레딧은 돌아온다)" % (task.get("status"), rec["error"]), file=sys.stderr)
        return EXIT_ERROR
    rec["files"] = download_outputs(task, out, task_id)
    try:
        rec["balance_after"] = client.balance()
    except TripoError as e:
        rec["balance_after"] = {"error": str(e)}
    write_record(out, record_name, rec)
    for f in rec["files"]:
        print("받음 %s  %d bytes  sha256 %s" % (out / f["name"], f["bytes"], f["sha256"]))
    print("잔액 %s -> %s, 소비 %s" % (bal_before.get("balance"), (rec["balance_after"] or {}).get("balance"), rec["credits_consumed"]))
    print("다음: 쓰기 전에 tools/art/asset_ledger.py 로 원장에 올린다(출처·모델·날짜·후처리는 %s에 있다)." % (out / record_name))
    return EXIT_OK


def base_record(kind: str, client: Client, params: dict, lines, bal_before: dict, task_id: str) -> dict:
    return {"schema": 1, "tool": TOOL, "kind": kind, "created_at": now(), "region": client.region, "task_id": task_id,
            "params": params, "estimate": {"lines": [[n, c] for n, c in lines], "total": sum(c for _, c in lines), "price_table_read_on": PRICES["read_on"]},
            "balance_before": bal_before, "status": "created"}


def cmd_image_to_model(opt) -> int:
    opt.kind = "image"
    img = Path(opt.image)
    if not img.is_file() or img.suffix.lower() not in (".png", ".jpg", ".jpeg"):
        raise Refused("--image는 있는 PNG/JPEG 파일이어야 한다")
    if img.stat().st_size > MAX_IMAGE_BYTES:
        raise Refused("그림이 20 MB를 넘는다")
    out = checked_out_dir(opt.out)
    params = build_params(opt)
    lines = estimate_lines(opt)
    client = make_client(opt)
    code, bal = guard_spend(client, lines, opt.confirm_credits)
    if code:
        return code
    token = client.upload_image(img)
    payload = dict(params, input=token)
    created = client.call("POST", "/generation/image-to-model", payload=payload)
    task_id = created.get("task_id")
    if not task_id:
        raise TripoError("task_id가 응답에 없다")
    print("작업 id", task_id)
    rec = base_record("image_to_model", client, params, lines, bal, task_id)
    rec["image"] = {"name": img.name, "bytes": img.stat().st_size, "sha256": sha256_of(img)}
    rec["prompt_note"] = "그림 입력(텍스트 프롬프트 없음). 원화의 출처·라이선스는 원화 쪽 원장 항목을 따른다."
    return finish_task(client, opt, out, "tripo_task.json", rec, task_id, bal)


def cmd_task(opt) -> int:
    out = checked_out_dir(opt.out) if opt.out else None
    client = make_client(opt)
    task = client.task(opt.id)
    print("status=%s progress=%s credits_consumed=%s" % (task.get("status"), task.get("progress"), task.get("credits_consumed")))
    if task.get("status") in STATUS_DONE:
        print("error_code=%s message=%s" % (task.get("error_code"), redact(task.get("error_message", ""))))
    if out is not None and task.get("status") == "success":
        files = download_outputs(task, out, opt.id)
        rec = {"schema": 1, "tool": TOOL, "kind": "recheck", "created_at": now(), "region": client.region, "task_id": opt.id,
               "type": task.get("type"), "status": "success", "credits_consumed": task.get("credits_consumed"), "files": files}
        write_record(out, "tripo_task_%s_recheck.json" % opt.id[:8], rec)
        for f in files:
            print("받음 %s  %d bytes  sha256 %s" % (out / f["name"], f["bytes"], f["sha256"]))
    return EXIT_OK


def cmd_rig(opt) -> int:
    out = checked_out_dir(opt.out)
    opt.rig, opt.retarget = True, 0
    lines = estimate_lines(opt, include_generation=False)
    client = make_client(opt)
    code, bal = guard_spend(client, lines, opt.confirm_credits)
    if code:
        return code
    params = {"model": opt.model, "rig_type": opt.rig_type, "out_format": "glb"}
    if opt.rig_type == "biped" and opt.spec:
        params["spec"] = opt.spec
    created = client.call("POST", "/animations/rig", payload=dict(params, input=opt.task))
    task_id = created.get("task_id")
    if not task_id:
        raise TripoError("task_id가 응답에 없다")
    print("작업 id", task_id)
    rec = base_record("rig", client, params, lines, bal, task_id)
    rec["source_task"] = opt.task
    return finish_task(client, opt, out, "tripo_rig.json", rec, task_id, bal)


def cmd_retarget(opt) -> int:
    out = checked_out_dir(opt.out)
    anims = list(opt.animation or [])
    if not 1 <= len(anims) <= 5:
        raise Refused("--animation은 1~5개")
    opt.rig, opt.retarget = False, len(anims)
    lines = estimate_lines(opt, include_generation=False)
    client = make_client(opt)
    code, bal = guard_spend(client, lines, opt.confirm_credits)
    if code:
        return code
    params = {"out_format": "glb"}
    params["animation" if len(anims) == 1 else "animations"] = anims[0] if len(anims) == 1 else anims
    created = client.call("POST", "/animations/retarget", payload=dict(params, input=opt.task))
    task_id = created.get("task_id")
    if not task_id:
        raise TripoError("task_id가 응답에 없다")
    print("작업 id", task_id)
    rec = base_record("retarget", client, params, lines, bal, task_id)
    rec["source_task"] = opt.task
    return finish_task(client, opt, out, "tripo_retarget.json", rec, task_id, bal)


# ------------------------------------------------------------------ cli
def add_generation_options(p, with_kind: bool = False) -> None:
    if with_kind:
        p.add_argument("--kind", choices=("image", "multiview"), required=True)
    p.add_argument("--hd-geometry", action="store_true", help="geometry_quality detailed (+20)")
    p.add_argument("--texture", choices=("standard", "hd", "ultra", "none"), default="standard")
    p.add_argument("--low-poly", action="store_true", help="smart_low_poly (+10)")
    p.add_argument("--quad", action="store_true", help="quad mesh (+5; output becomes FBX)")
    p.add_argument("--parts", action="store_true", help="generate_parts (+20; needs --texture none)")
    p.add_argument("--face-limit", type=int, default=None)


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="tripo_api.py", description="Tripo API client (credit-spending commands need --confirm-credits = estimate)")
    ap.add_argument("--region", choices=tuple(HOSTS), default=None)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("balance", help="read the balance (free)")
    e = sub.add_parser("estimate", help="compute credits, no call")
    add_generation_options(e, with_kind=True)
    e.add_argument("--rig", action="store_true")
    e.add_argument("--retarget", type=int, default=0, metavar="N")
    g = sub.add_parser("image-to-model", help="image to 3D (spends credits)")
    g.add_argument("--image", required=True)
    g.add_argument("--out", required=True)
    g.add_argument("--model", default=DEFAULT_MODEL)
    g.add_argument("--no-pbr", action="store_true")
    add_generation_options(g)
    g.add_argument("--confirm-credits", type=float, default=None)
    g.add_argument("--poll", type=float, default=POLL_SECONDS)
    g.add_argument("--timeout", type=float, default=TIMEOUT_SECONDS)
    t = sub.add_parser("task", help="task status and re-download (free)")
    t.add_argument("--id", required=True)
    t.add_argument("--out", default=None)
    r = sub.add_parser("rig", help="auto rig (spends credits)")
    r.add_argument("--task", required=True, help="task id of the generated model")
    r.add_argument("--out", required=True)
    r.add_argument("--model", default=DEFAULT_RIG_MODEL)
    r.add_argument("--rig-type", default="biped", choices=("biped", "quadruped", "hexapod", "octopod", "avian", "serpentine", "aquatic", "others"))
    r.add_argument("--spec", default=None, choices=("tripo", "mixamo", "actorcore", "unity", "unreal", "vrm"))
    r.add_argument("--confirm-credits", type=float, default=None)
    r.add_argument("--poll", type=float, default=POLL_SECONDS)
    r.add_argument("--timeout", type=float, default=TIMEOUT_SECONDS)
    m = sub.add_parser("retarget", help="apply preset animations to a rigged model (spends credits)")
    m.add_argument("--task", required=True, help="task id of the rig task")
    m.add_argument("--animation", action="append", help="e.g. preset:idle (repeat, up to 5)")
    m.add_argument("--out", required=True)
    m.add_argument("--confirm-credits", type=float, default=None)
    m.add_argument("--poll", type=float, default=POLL_SECONDS)
    m.add_argument("--timeout", type=float, default=TIMEOUT_SECONDS)
    return ap


COMMANDS = {"balance": cmd_balance, "estimate": cmd_estimate, "image-to-model": cmd_image_to_model, "task": cmd_task,
            "rig": cmd_rig, "retarget": cmd_retarget}


def main(argv=None) -> int:
    opt = build_parser().parse_args(argv)
    try:
        return COMMANDS[opt.cmd](opt)
    except Refused as e:
        print("거절: " + redact(e), file=sys.stderr)
        return EXIT_REFUSED
    except TripoError as e:
        print("오류: " + redact(e), file=sys.stderr)
        return EXIT_ERROR
    except Exception as e:  # never let a traceback carry request details
        print("오류(%s): %s" % (type(e).__name__, redact(e)), file=sys.stderr)
        return EXIT_ERROR


if __name__ == "__main__":
    sys.exit(main())
