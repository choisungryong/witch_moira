#!/usr/bin/env python3
"""기본 몸 메시에 우리 면별 그림을 입힌다(numpy/scipy/PIL, Blender 필요 없음). 입력은 base_dump.py의 npz, 설정 json, 실루엣 방식 모델(목표 형상)이다.

  python tools/art/base_bake.py --config tools/art/base_configs/frost.json --dump dump.npz --out-dir DIR
하는 일
  1) 맞춤(fit): 기본 몸을 원화 모델에 맞춘다. 높이 표지(발목·무릎·엉덩이·가슴·목·정수리)로 z를 조각선형으로 늘이고, 몸통·두 다리는 높이 칸마다 가로·앞뒤 폭과 중심을
     실루엣 방식 모델의 같은 부위에 맞춘다(머리·팔은 z만). 같은 함수를 뼈 위치에도 적용해 뼈대와 메시가 같이 맞는다(body_fit.npz).
  2) 굽기: A자세로 맞춘 메시를 uv 삼각형으로 래스터해 텍셀마다 위치·법선을 얻고, 기존 char_from_sheets의 시점 투영·가림·섞기(bake_texture)로 한 장(albedo.png)을 굽는다.
모든 값은 모델의 계산이다. 원화가 그린 옷은 몸 표면의 색으로 들어가고(코르셋·장화·장갑), 몸에서 뜨는 것(치마·목도리)은 별도 부품으로 다시 붙인다.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import char_from_sheets as C  # noqa: E402
import char_geom as G  # noqa: E402

ARM_BONES = ("clavicle", "upperarm", "lowerarm")
HAND_BONES = ("hand", "index", "middle", "ring", "pinky", "thumb")


def group_of(bone):
    b = bone or ""
    if b == "Head":
        return "head"
    if b.startswith(HAND_BONES):
        return "hand"
    if b.startswith(ARM_BONES):
        return "arm"
    if b.startswith(("thigh", "calf", "foot", "ball")):
        return "leg_l" if b.endswith("_l") else "leg_r"
    return "body"        # pelvis, spine, neck


def region_of(bone):
    g = group_of(bone)
    return g


# ------------------------------------------------------------------ 맞춤

def smooth1(a, k):
    out = np.array(a, float)
    for _ in range(k):
        p = np.pad(out, 1, mode="edge")
        out = (p[:-2] + 2 * p[1:-1] + p[2:]) / 4.0
    return out


def build_zmap(base_lm, old_lm):
    """높이 표지 쌍(오름차순)으로 조각선형 z 사상. 양 끝 밖은 기울기 1로 이어 간다."""
    bx, ox = np.array(base_lm, float), np.array(old_lm, float)

    def f(z):
        z = np.asarray(z, float)
        out = np.interp(z, bx, ox)
        lo, hi = z < bx[0], z > bx[-1]
        out = np.where(lo, ox[0] + (z - bx[0]), out)
        out = np.where(hi, ox[-1] + (z - bx[-1]), out)
        return out
    return f


def row_extents(P, mask, zbins):
    """칸마다 (x 중심, x 반폭, y 중심, y 반폭). 칸에 정점이 3개 미만이면 nan."""
    out = np.full((len(zbins) - 1, 4), np.nan)
    for i in range(len(zbins) - 1):
        m = mask & (P[:, 2] >= zbins[i]) & (P[:, 2] < zbins[i + 1])
        if m.sum() >= 3:
            xs, ys = P[m, 0], P[m, 1]
            out[i] = ((xs.max() + xs.min()) / 2, (xs.max() - xs.min()) / 2, (ys.max() + ys.min()) / 2, (ys.max() - ys.min()) / 2)
    return out


def fill_nan(col, zc):
    ok = ~np.isnan(col)
    if not ok.any():
        return col
    return np.interp(zc, zc[ok], col[ok])


def fit_regions(Pz, groups, old_parts, zbins, clamp=(0.6, 1.7)):
    """z를 이미 맞춘 기본 몸 좌표(Pz)에서 부위(body, leg_l, leg_r)마다 칸별 (가로 배율, 가로 중심 이동, 앞뒤 배율, 앞뒤 중심 이동)을 구한다.
    목표 = 실루엣 모델의 같은 이름 부위 정점."""
    zc = (zbins[:-1] + zbins[1:]) / 2
    targets = {}
    for name in ("torso", "neck"):
        if name in old_parts:
            targets.setdefault("body", []).append(old_parts[name])
    for side in "lr":
        if "leg_" + side in old_parts:
            targets["leg_" + side] = [old_parts["leg_" + side]]
    fit = {}
    for reg, plist in targets.items():
        T = np.concatenate(plist)
        e_t = row_extents(T, np.ones(len(T), bool), zbins)
        e_b = row_extents(Pz, groups == reg, zbins)
        e_t = np.stack([fill_nan(e_t[:, k], zc) for k in range(4)], axis=1)
        e_b = np.stack([fill_nan(e_b[:, k], zc) for k in range(4)], axis=1)
        sx = np.clip(e_t[:, 1] / np.maximum(e_b[:, 1], 1e-3), *clamp)
        sy = np.clip(e_t[:, 3] / np.maximum(e_b[:, 3], 1e-3), *clamp)
        sx, sy = smooth1(sx, 3), smooth1(sy, 3)
        fit[reg] = dict(sx=sx, sy=sy, cx_b=smooth1(e_b[:, 0], 2), cy_b=smooth1(e_b[:, 2], 2), cx_t=smooth1(e_t[:, 0], 2), cy_t=smooth1(e_t[:, 2], 2))
    return zc, fit


def apply_fit(P, groups, fz, zc, fit, arm_sx):
    """P(N,3) 좌표, groups(N) 부위 이름 -> 맞춘 좌표."""
    Q = P.copy()
    Q[:, 2] = fz(P[:, 2])
    for reg, f in fit.items():
        m = groups == reg
        if not m.any():
            continue
        z = Q[m, 2]
        cxb = np.interp(z, zc, f["cx_b"]); cxt = np.interp(z, zc, f["cx_t"])
        cyb = np.interp(z, zc, f["cy_b"]); cyt = np.interp(z, zc, f["cy_t"])
        sx = np.interp(z, zc, f["sx"]); sy = np.interp(z, zc, f["sy"])
        Q[m, 0] = cxt + (P[m, 0] - cxb) * sx
        Q[m, 1] = cyt + (P[m, 1] - cyb) * sy
    arm = np.isin(groups, ("arm", "hand"))
    Q[arm, 0] = P[arm, 0] * arm_sx
    if "body" in fit:   # 머리·팔은 앞뒤 중심만 몸통 중심을 따른다
        cyb = np.interp(Q[:, 2], zc, fit["body"]["cy_b"]); cyt = np.interp(Q[:, 2], zc, fit["body"]["cy_t"])
        other = np.isin(groups, ("head", "arm", "hand"))
        Q[other, 1] = P[other, 1] + (cyt[other] - cyb[other])
    return Q


def thin_arms(P, groups, factor):
    """팔·손 정점을 팔 축(왼·오른쪽마다 주성분 축을 지나는 선)에 수직으로 factor배 줄인다(원화 팔이 가늘어 기본 몸 팔이 그림 마스크 밖으로 나가는 것을 막는다)."""
    Q = P.copy()
    for sg in (1.0, -1.0):
        m = np.isin(groups, ("arm", "hand")) & (np.sign(P[:, 0]) == sg) & (np.abs(P[:, 0]) > 0.12)
        if m.sum() < 10:
            continue
        pts = P[m]
        c = pts.mean(0)
        u, s_, vt = np.linalg.svd(pts - c, full_matrices=False)
        ax = vt[0]
        rel = pts - c
        along = (rel @ ax)[:, None] * ax[None, :]
        Q[m] = c + along + (rel - along) * factor
    return Q


# ------------------------------------------------------------------ 래스터

def rasterize_uv(verts, normals, tris, uv, groups_v, TS, group_index):
    """uv 삼각형을 텍셀로 래스터해 텍셀 위치 P, 법선 N, 부위 번호를 얻는다(tex 사전: ix, iy, P, N, part)."""
    owner = np.full((TS, TS), -1, np.int64)
    bary = np.zeros((TS, TS, 3), np.float32)
    for t in range(len(tris)):
        c = uv[t] * np.array([TS, TS]) * np.array([1.0, 1.0])
        px = c[:, 0]
        py = (1.0 - uv[t][:, 1]) * TS
        x0, x1 = int(np.floor(px.min())), int(np.ceil(px.max()))
        y0, y1 = int(np.floor(py.min())), int(np.ceil(py.max()))
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, TS - 1), min(y1, TS - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        d = (py[1] - py[2]) * (px[0] - px[2]) + (px[2] - px[1]) * (py[0] - py[2])
        if abs(d) < 1e-9:
            continue
        w0 = ((py[1] - py[2]) * (gx - px[2]) + (px[2] - px[1]) * (gy - py[2])) / d
        w1 = ((py[2] - py[0]) * (gx - px[2]) + (px[0] - px[2]) * (gy - py[2])) / d
        w2 = 1 - w0 - w1
        eps = -0.02
        inside = (w0 >= eps) & (w1 >= eps) & (w2 >= eps)
        if not inside.any():
            continue
        yy, xx = np.nonzero(inside)
        owner[y0 + yy, x0 + xx] = t
        bary[y0 + yy, x0 + xx, 0] = w0[yy, xx]
        bary[y0 + yy, x0 + xx, 1] = w1[yy, xx]
        bary[y0 + yy, x0 + xx, 2] = w2[yy, xx]
    iy, ix = np.nonzero(owner >= 0)
    tt = owner[iy, ix]
    b = bary[iy, ix]
    vi = tris[tt]
    P = (verts[vi] * b[:, :, None]).sum(1)
    N = (normals[vi] * b[:, :, None]).sum(1)
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-9
    gi = vi[np.arange(len(tt)), np.argmax(b, axis=1)]
    part = np.array([group_index[g] for g in groups_v[gi]], np.int32)
    return dict(ix=ix.astype(np.int32), iy=iy.astype(np.int32), P=P, N=N, part=part)


def ice_arm(atlas, tex, names, spec, out):
    """왼팔(원소 팔)을 반투명 하늘색 대신 불투명한 얼음빛 피부로 바꾸고, 그림의 푸른 선(채도 높은 텍셀)은 살려 발광 가면(emission.png)으로 낸다.
    spec: {"color": [r,g,b], "vein_hue_sat": 0.22, "vein_color": [r,g,b]}."""
    from PIL import Image
    ix, iy, P, part = tex["ix"], tex["iy"], tex["P"], tex["part"]
    side = np.isin(part, [names.index("arm"), names.index("hand")]) & (P[:, 0] > 0.05)
    col = atlas[iy[side], ix[side]]
    mx, mn = col.max(1), col.min(1)
    sat = (mx - mn) / np.maximum(mx, 1e-4)
    w = np.clip((sat - spec.get("vein_hue_sat", 0.22)) / 0.25, 0, 1)
    lum = col.mean(1)
    shade = np.clip(lum / max(float(lum.mean()), 1e-4), 0.75, 1.15)
    base = np.array(spec.get("color", [0.62, 0.78, 0.92]), np.float32)[None, :] * shade[:, None]
    new = base * (1 - w[:, None]) + np.clip(col * 1.05, 0, 1) * w[:, None]
    atlas = atlas.copy()
    atlas[iy[side], ix[side]] = new
    em = np.zeros(atlas.shape, np.float32)
    em[iy[side], ix[side]] = np.array(spec.get("vein_color", [0.35, 0.75, 1.0]), np.float32)[None, :] * w[:, None]
    Image.fromarray((np.clip(em, 0, 1) * 255 + 0.5).astype(np.uint8)).save(out / "emission.png")
    return atlas


# ------------------------------------------------------------------ 한 번에

def run(cfg_path, dump_path, out_dir, log=print):
    from PIL import Image
    cfgb = json.loads(Path(cfg_path).read_text(encoding="utf-8"))
    cfg = C.load_config(HERE.parents[1] / cfgb["char_config"])
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    d = np.load(dump_path, allow_pickle=False)
    rest, apose, tris, uv = d["rest"], d["apose"], d["tris"], d["uv"]
    dom = d["group"]
    heads = json.loads(str(d["bones_head"]))
    tails = json.loads(str(d["bones_tail"]))
    groups = np.array([group_of(b) for b in dom])
    # 실루엣 모델(목표 형상): stage_geom이 만든 부위
    g = C.stage_geom(cfg, out / "geom", log=lambda *a: None)
    old_parts = {p["name"]: p["verts"] for p in g["parts"]}
    old_bones = json.loads(Path(cfgb["old_bones"]).read_text(encoding="utf-8"))["bones"]
    ob = lambda n: np.array(old_bones[n]["head"])
    # 표지: 기본 몸 (발바닥, 발목, 무릎, 엉덩이, 가슴, 목, 정수리) -> 원화 모델
    z0 = float(rest[:, 2].min())
    bh = lambda n: heads[n][2]
    base_lm = [z0, bh("foot_l"), bh("calf_l"), bh("thigh_l"), bh("spine_03"), bh("neck_01"), float(rest[:, 2].max())]
    old_top = float(max(v[:, 2].max() for v in old_parts.values()))
    old_lm = [0.0, float(ob("tarsal_cr_l")[2]), float(ob("shin_cr_l")[2]), float(ob("thigh_cr_l")[2]), float(ob("spine_cr_03")[2]), float(ob("neck_cr")[2]), old_top]
    ez = float(d["eyes_z"]) if "eyes_z" in d.files else float("nan")
    if not np.isnan(ez):   # 눈 높이 표지: 기본 몸의 눈알 높이 -> 원화 앞면 그림의 눈 높이(얼굴 그림의 눈이 눈구멍에 오도록)
        eyes = C.detect_eyes(g["imgs"]["front"], 0.14, cfgb.get("front_eye_rule"))
        if eyes:
            art_ez = float(g["R"].Z(float(np.mean([e[1] for e in eyes]))))
            base_lm.insert(-1, ez)
            old_lm.insert(-1, art_ez)
            log("eye landmark base %.3f -> art %.3f" % (ez, art_ez))
    fz = build_zmap(base_lm, old_lm)
    zbins = np.arange(0.0, old_top + 0.02, 0.03)
    Pz = rest.copy()
    Pz[:, 2] = fz(rest[:, 2])
    zc, fit = fit_regions(Pz, groups, old_parts, zbins)
    arm_sx = float(cfgb.get("arm_x_scale", 1.0))
    rest_f = apply_fit(rest, groups, fz, zc, fit, arm_sx)
    apose_f = apply_fit(apose, groups, fz, zc, fit, arm_sx)
    af = float(cfgb.get("arm_thin", 1.0))
    if af != 1.0:
        rest_f, apose_f = thin_arms(rest_f, groups, af), thin_arms(apose_f, groups, af)
    # 뼈 위치: 같은 함수(뼈의 부위는 이름으로)
    bnames = list(heads)
    bg = np.array([group_of(n) for n in bnames])
    bh_p = apply_fit(np.array([heads[n] for n in bnames]), bg, fz, zc, fit, arm_sx)
    bt_p = apply_fit(np.array([tails[n] for n in bnames]), bg, fz, zc, fit, arm_sx)
    np.savez_compressed(out / "body_fit.npz", rest_fit=rest_f, apose_fit=apose_f, bones=np.array(bnames), bones_head=bh_p, bones_tail=bt_p,
                        landmarks_base=np.array(base_lm), landmarks_old=np.array(old_lm))
    # 굽기
    TS = int(cfgb.get("texture", 2048))
    nrm = G.vertex_normals(apose_f, tris)
    names = ["body", "head", "arm", "hand", "leg_l", "leg_r"]
    gi = {n: i for i, n in enumerate(names)}
    tex = rasterize_uv(apose_f, nrm, tris, uv, groups, TS, gi)
    log("texels %d (%.1f%% of atlas)" % (len(tex["ix"]), 100 * len(tex["ix"]) / TS / TS))
    bake_groups = {"body": "body", "head": "head", "arm": "arm", "hand": "hand", "leg_l": "leg", "leg_r": "leg"}
    parts = [dict(group=bake_groups[n]) for n in names]
    views, meta = C.build_views(cfg, g, cfg.get("flatten"), log)
    b = cfg.get("bake", {})
    atlas, st = C.bake_texture(parts, tex, views, TS, b.get("power", 4.0), b.get("arm_occlusion_px", 9), b.get("depth_tol", 0.012), log,
                               clamp_z=None, margin=b.get("margin", 0.12), resample=b.get("resample", "bilinear"), tol_head=b.get("depth_tol_head"),
                               outside_w=float(cfgb.get("outside_w", 0.15)))
    if cfgb.get("ice_arm"):
        atlas = ice_arm(atlas, tex, names, cfgb["ice_arm"], out)
    if b.get("sharpen", 0) > 0:
        from scipy import ndimage as ndi
        sig = float(b.get("sharpen_sigma", 1.2)) * TS / 2048.0
        blurred = np.stack([ndi.gaussian_filter(atlas[..., k], sig) for k in range(3)], axis=2)
        atlas = np.clip(atlas + float(b["sharpen"]) * (atlas - blurred), 0, 1)
    Image.fromarray((np.clip(atlas, 0, 1) * 255 + 0.5).astype(np.uint8)).save(out / "albedo.png")
    Image.fromarray(tex["_dbg"]).save(out / "weights_debug.png")
    rep = dict(st, texels=int(len(tex["ix"])), landmarks_base=base_lm, landmarks_old=old_lm, scale_x_torso=[float(np.nanmin(fit["body"]["sx"])), float(np.nanmax(fit["body"]["sx"]))])
    (out / "bake.json").write_text(json.dumps(rep, indent=1, ensure_ascii=False, default=float), encoding="utf-8")
    if "hair_rest" in d.files and cfgb.get("hair_texture"):
        hr, ht, hu = d["hair_rest"], d["hair_tris"], d["hair_uv"]
        from scipy.spatial import cKDTree
        kt = cKDTree(rest)
        dist, ii = kt.query(hr, k=4)
        wgt = 1.0 / (dist + 1e-3)
        dsp = ((rest_f - rest)[ii] * wgt[:, :, None]).sum(1) / wgt.sum(1, keepdims=True)
        hf = hr + dsp
        np.savez_compressed(out / "hair_fit.npz", verts=hf)
        TH = int(cfgb["hair_texture"])
        hn = G.vertex_normals(hf, ht)
        htex = rasterize_uv(hf, hn, ht, hu, np.array(["hair"] * len(hf)), TH, {"hair": 0})
        hatlas, hst = C.bake_texture([dict(group="hair")], htex, views, TH, b.get("power", 4.0), b.get("arm_occlusion_px", 9), b.get("depth_tol", 0.012), log,
                                     clamp_z=None, margin=b.get("margin", 0.12), resample=b.get("resample", "bilinear"))
        Image.fromarray((np.clip(hatlas, 0, 1) * 255 + 0.5).astype(np.uint8)).save(out / "hair_albedo.png")
        rep["hair_unseen_fraction"] = hst["unseen_fraction"]
    log("bake done", {k: v for k, v in rep.items() if k in ("filled_fraction", "unseen_fraction", "texels")})
    return rep


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--dump", required=True)
    ap.add_argument("--out-dir", required=True)
    a = ap.parse_args(argv)
    run(a.config, a.dump, a.out_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
