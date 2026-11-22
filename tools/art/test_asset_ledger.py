#!/usr/bin/env python3
"""asset_ledger.py 자체 검사. 실행: python tools/art/test_asset_ledger.py
표준 라이브러리만. 임시 폴더에서만 쓴다(실제 원장·그림은 건드리지 않음). 외부 호출 없음."""
import json
import shutil
import struct
import sys
import tempfile
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asset_ledger as L  # noqa: E402

REAL_ROOT = Path(__file__).resolve().parent.parent.parent
FAILS = []
N = 0


def check(name, cond, detail=""):
    global N
    N += 1
    if cond:
        print("ok  ", name)
    else:
        FAILS.append(name)
        print("FAIL", name, detail)


def tiny_png(path, w=3, h=2):
    raw = b"".join(b"\x00" + b"\x00\x00\x00\xff" * w for _ in range(h))

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_bytes(data)


def run(root, *args):
    return L.main(["--root", str(root)] + list(args))


def main():
    tmp = Path(tempfile.mkdtemp(prefix="ledger-test-"))
    try:
        art = tmp / "chapter1" / "art"
        tiny_png(art / "a" / "one.png")
        (art / "a" / "notes.md").write_text("doc", encoding="utf-8")
        (art / "a" / "one.png.import").write_text("x", encoding="utf-8")

        check("원장 없음은 오류 1", run(tmp, "check") == 1)
        (art / "a" / "prompt.txt").write_text("P-전문\n둘째 줄", encoding="utf-8")
        rc = run(tmp, "add", str(art / "a" / "one.png"), "--source-type", "ai_generated", "--origin", "시험",
                 "--license", "프로젝트 자체", "--model", "M", "--prompt-file", str(art / "a" / "prompt.txt"),
                 "--date", "2026-11-19", "--postprocess", "없음", "--terms-checked")
        check("add 성공", rc == 0)
        led = json.loads((art / "ASSET-LEDGER.json").read_text(encoding="utf-8"))
        e = led["assets"][0]
        check("해시·크기·해상도 자동", e["sha256"] == L.sha256_of(art / "a" / "one.png") and e["size"] > 0
              and (e["width"], e["height"]) == (3, 2))
        check("프롬프트 전문 보존", e["prompt"] == "P-전문\n둘째 줄")
        check("문서·.import 는 대상 아님 -> check 통과", run(tmp, "check") == 0)
        check("add 중복은 거부", run(tmp, "add", str(art / "a" / "one.png"), "--source-type", "project_original") == 1)
        res = L.run_check(tmp, art / "ASSET-LEDGER.json")
        check("release_cleared 전에는 배포 불가", res["release"] and res["counts"]["provenance_complete"] == 1
              and res["counts"]["release_ready"] == 0)
        check("--strict 는 배포 불가가 있으면 2", run(tmp, "check", "--strict") == 2)
        led["assets"][0]["release_cleared"] = True
        L.write_json(art / "ASSET-LEDGER.json", led)
        check("사람 확인 뒤에는 배포 가능 1", L.run_check(tmp, art / "ASSET-LEDGER.json")["counts"]["release_ready"] == 1
              and run(tmp, "check", "--strict") == 0)

        # 원장에 없는 파일
        tiny_png(art / "b" / "two.png")
        check("원장에 없는 파일은 오류", any("원장에 없다" in m for m in L.run_check(tmp, art / "ASSET-LEDGER.json")["errors"])
              and run(tmp, "check") == 1)
        # 미확인은 구멍(오류 아님)
        rc = run(tmp, "add", str(art / "b" / "two.png"), "--source-type", "ai_generated")
        res = L.run_check(tmp, art / "ASSET-LEDGER.json")
        check("입력 없는 칸은 '미확인' 구멍, 오류 아님", rc == 0 and not res["errors"] and res["holes"]
              and run(tmp, "check") == 0 and run(tmp, "check", "--strict") == 2)
        # 해시 어긋남
        tiny_png(art / "b" / "two.png", 5, 5)
        check("해시가 어긋나면 오류", any("해시가 다르다" in m for m in L.run_check(tmp, art / "ASSET-LEDGER.json")["errors"]))
        # 파일 없음
        (art / "b" / "two.png").unlink()
        check("파일이 없으면 오류", any("파일이 없다" in m for m in L.run_check(tmp, art / "ASSET-LEDGER.json")["errors"]))
        # 필수 칸이 빈 항목
        led = json.loads((art / "ASSET-LEDGER.json").read_text(encoding="utf-8"))
        led["assets"] = [x for x in led["assets"] if x["path"] != "b/two.png"]
        led["assets"][0]["license"] = ""
        L.write_json(art / "ASSET-LEDGER.json", led)
        check("필수 칸이 비면 오류", any("'license'" in m for m in L.run_check(tmp, art / "ASSET-LEDGER.json")["errors"]))
        (art / "b" / "two.png").unlink(missing_ok=True)

        # migrate: 실제 저장소를 읽기만 하고 임시 원장에 쓴다
        out = tmp / "migrated.json"
        check("migrate 성공", L.main(["--root", str(REAL_ROOT), "--ledger", str(out), "migrate", "--date", "2026-11-19"]) == 0)
        check("migrate 는 덮어쓰기 거부", L.main(["--root", str(REAL_ROOT), "--ledger", str(out), "migrate"]) == 1)
        m = json.loads(out.read_text(encoding="utf-8"))
        files = L.list_asset_files(REAL_ROOT)
        check("실제 에셋 파일 전부가 항목에 있다", sorted(x["path"] for x in m["assets"]) == sorted(files),
              (len(m["assets"]), len(files)))
        v04 = json.loads((REAL_ROOT / "chapter1/art/quality03/ASSET-LEDGER-v04.json").read_text(encoding="utf-8"))
        by = {x["path"]: x for x in m["assets"]}
        ok = True
        for grp in ("accepted_for_runtime_trial", "rejected_attempts"):
            for a in v04[grp]:
                e = by["quality03/" + a["path"]]
                ok = ok and e["prompt"] == L.norm_path(a["prompt"]) and e["sha256"] == a["sha256"] \
                    and e["original_sha256"] == a["original_sha256"] and e["reference_inputs"] == L.norm_deep(a["reference_inputs"])
        check("v04 의 프롬프트 전문·해시·참조 입력이 그대로", ok)
        check("계정 식별이 되는 홈 경로가 원장에 없다", "twins" not in out.read_text(encoding="utf-8"))
        check("거절한 시도작은 rejected", by["quality03/attempts/hero_run_attempt01.png"]["status"].startswith("rejected"))
        check("옛 기록 파일이 records 로 가리켜지고 실제로 있다",
              all((REAL_ROOT / "chapter1/art" / r["path"]).is_file() for r in m["records"]) and len(m["records"]) >= 10)
        check("옛 기록 파일을 지우지 않았다", (REAL_ROOT / "chapter1/art/quality03/ASSET-LEDGER-v04.json").is_file())
        check("migrate 결과가 점검을 통과(오류 0)", not L.run_check(REAL_ROOT, out)["errors"])
        # 새 소리 폴더 audio/ 의 항목이 소리 원장(audio/AUDIO-LEDGER.json)의 사실 그대로 허용 값으로 변환됨
        nal = json.loads((REAL_ROOT / "chapter1/art/audio/AUDIO-LEDGER.json").read_text(encoding="utf-8"))
        okn = len(nal["products"]) > 0
        for p in nal["products"]:
            e = by.get("audio/" + p["file"])
            okn = okn and e is not None and e["source_type"] in L.SOURCE_TYPES and e["sha256"] == p["sha256"]                 and e["origin"] == p["source"] and e["license"] == p["license"] and e["postprocess"] == p["method"]
        check("migrate: 새 소리 폴더 audio/ 항목이 원장의 출처·가공·라이선스·해시 그대로 허용 source_type 으로 들어온다", okn)
        check("migrate 직후 배포 가능으로 표기된 것은 0(release_cleared 없음)",
              L.run_check(REAL_ROOT, out)["counts"]["release_ready"] == 0)
        check("출처를 모르는 생성물은 '미확인'으로 적힘(지어내지 않음)",
              L.is_unknown(by["actors/hero.png"]["prompt"]) and L.is_unknown(by["actors/hero.png"]["model"]))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("\n%d 검사, 실패 %d" % (N, len(FAILS)))
    for f in FAILS:
        print("  FAIL:", f)
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
