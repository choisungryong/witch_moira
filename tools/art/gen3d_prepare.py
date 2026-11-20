#!/usr/bin/env python3
"""이미지→3D 생성 모델(수십만 삼각형, 갈가리 찢긴 UV)을 게임용 저폴리로 줄이고 질감을 새로 굽는다(Blender 5.3 명령줄).
mesh_reduce.py의 함수를 가져다 쓰되, 생성 모델에 맞게 바꾼 점: UV 이음을 지키지 않고 줄이고(원래 UV가 수천 조각이라 지키면 줄지 않는다),
얼굴 텍셀 밀도를 키워 새 UV를 짜고, 머티리얼은 거칠기·금속을 상수로 새로 쓴다(생성 모델의 금속 0.57·거칠기 0.33은 게임 조명에서 비닐처럼 번들거린다).

  python tools/art/gen3d_prepare.py --in HIGH.glb --out-glb OUT.glb --work DIR [--target 15000] [--height 1.681] [--tex 2048]
        [--roughness 0.8] [--face-boost 1.8] [--cage 0.01] [--recolor-json recolor.json] [--blend OUT.blend] [--report r.json]
출력: OUT.glb(메시 + 머티리얼 하나, 바탕색·노멀 PNG 포함, 뼈대 없음), DIR/<이름>_color.png·_normal.png, 보고서(전후 삼각형, 머리·손 삼각형, 실루엣 IoU).
다음 걸음: gen3d_rig.py. 30,000판은 --target 30000 --out-glb ..._30k.glb로 한 번 더.
recolor-json: 몸 텍스처의 한 부위 색을 바꾸는 규칙 목록 [{"name":..,"side":"r|l","x_min":..,"z_range":[a,b],"to":"skin"}] (아래 recolor 함수).
"""
from __future__ import annotations

import argparse
import math
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rig_common as rc  # noqa: E402
import mesh_reduce as mr  # noqa: E402

_T0 = time.time()


def log(msg):
    print("GEN3D_PREPARE %6.1fs %s" % (time.time() - _T0, msg), flush=True)


def region_tris(obj, H):
    """머리(키의 86% 위)와 손(양쪽 가장 먼 점 둘레) 삼각형 수."""
    import numpy as np
    me = obj.data
    me.calc_loop_triangles()
    P = rc.mesh_coords(obj)
    T = np.empty(len(me.loop_triangles) * 3, int)
    me.loop_triangles.foreach_get("vertices", T)
    T = T.reshape(-1, 3)
    c = P[T].mean(axis=1)
    head = int((c[:, 2] > 0.86 * H).sum())
    hands = 0
    for sgn in (1, -1):
        m = (P[:, 2] > 0.35 * H) & (sgn * P[:, 0] > 0)
        idx = np.where(m)[0]
        sel = idx[np.argsort(-sgn * P[idx, 0])[:max(30, int(0.01 * len(P)))]]
        ctr = P[sel].mean(axis=0)
        hands += int((np.linalg.norm(c - ctr, axis=1) < 0.09 * H).sum())
    return {"head": head, "hands": hands, "total": int(len(T))}


def _collapse(obj, ratio, group_mode):
    """group_mode: 'keep' = 보호 그룹은 건드리지 않고 나머지를 줄임, 'only' = 보호 그룹만 줄임, None = 전부.
    (Blender 데시메이트의 정점 그룹은 '줄일 곳'이다: 그냥 쓰면 보호 부위만 줄고, 반전해야 보호가 된다. 실측 2026-11-20.)"""
    import bpy
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new("Decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = max(min(ratio, 1.0), 0.001)
    mod.use_collapse_triangulate = True
    if group_mode:
        mod.vertex_group = "protect"
        mod.invert_vertex_group = (group_mode == "keep")
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return mr.tri_count(obj)


def decimate_weighted(low, H, target, share, log=print):
    """부위별 배분 줄이기: 머리·손(보호 그룹)에 삼각형 share 몫, 나머지 몸에 1-share 몫을 준다. 1단계 몸만 줄이고 2단계 보호 부위만 줄인다."""
    cur = mr.tri_count(low)
    prot = region_tris(low, H)
    n_prot = prot["head"] + prot["hands"]
    body_target = int(target * (1 - share))
    t1 = n_prot + body_target
    guard = 0
    while cur > t1 * 1.03 and guard < 8:      # 비율이 너무 작으면 모양이 깨지니 한 번에 1/4까지만
        guard += 1
        cur = _collapse(low, max(t1 / cur, 0.25), "keep")
        log("몸 줄임 %d" % cur)
    guard = 0
    while cur > target * 1.02 and guard < 8:
        guard += 1
        cur = _collapse(low, max(target / cur, 0.25), "only")
        log("머리·손 줄임 %d" % cur)
    if cur > target * 1.03 or cur < target * 0.85:     # 마지막 맞춤은 전체
        cur = _collapse(low, target / cur, None) if cur > target else cur
    return cur


def flatten_metallic(obj):
    """고폴리 머티리얼의 금속 값을 0으로(연결 끊기). 금속이 높으면 Blender의 '확산' 굽기가 검게 나온다(머리카락·코르셋이 까맣게 구워지는 까닭, 2026-11-20 실측)."""
    n = 0
    for m in obj.data.materials:
        if not (m and m.use_nodes):
            continue
        for nd in m.node_tree.nodes:
            if nd.type == "BSDF_PRINCIPLED":
                s = nd.inputs["Metallic"]
                for l in list(s.links):
                    m.node_tree.links.remove(l)
                s.default_value = 0.0
                n += 1
    return n


def uv_islands(me):
    """UV 섬(정점+UV가 같은 점을 공유하는 면끼리 묶음). 반환: 면마다 섬 번호(numpy)."""
    import numpy as np
    uv = me.uv_layers.active.data
    n = len(me.polygons)
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    first = {}
    for p in me.polygons:
        for li in range(p.loop_start, p.loop_start + p.loop_total):
            key = (me.loops[li].vertex_index, round(uv[li].uv[0], 5), round(uv[li].uv[1], 5))
            q = first.setdefault(key, p.index)
            if q != p.index:
                ra, rb = find(p.index), find(q)
                if ra != rb:
                    parent[ra] = rb
    roots = np.array([find(i) for i in range(n)])
    _, inv = np.unique(roots, return_inverse=True)
    return inv


def unwrap_with_face_boost(low, H, angle_deg, boost, z_min=0.86):
    """새 UV를 펴고, 머리(키의 z_min 위) 섬의 크기를 boost배로 키운 뒤 다시 채운다(텍셀 밀도 배분)."""
    import bpy
    import numpy as np
    me = low.data
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    for n in list(me.uv_layers):
        me.uv_layers.remove(n)
    me.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle_deg), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")
    if boost and abs(boost - 1.0) > 1e-3:
        isl = uv_islands(me)
        P = rc.mesh_coords(low)
        fz = np.array([P[list(p.vertices)][:, 2].mean() for p in me.polygons])
        n_isl = int(isl.max()) + 1
        face_boost = np.ones(n_isl)
        for k in range(n_isl):
            zf = fz[isl == k]
            if len(zf) and float(zf.mean()) > z_min * H:
                face_boost[k] = boost
        loops = len(me.loops)
        UV = np.empty(loops * 2)
        me.uv_layers.active.data.foreach_get("uv", UV)
        UV = UV.reshape(-1, 2)
        loop_isl = np.empty(loops, int)
        for p in me.polygons:
            loop_isl[p.loop_start:p.loop_start + p.loop_total] = isl[p.index]
        for k in range(n_isl):
            if face_boost[k] != 1.0:
                m = loop_isl == k
                c = UV[m].mean(axis=0)
                UV[m] = c + (UV[m] - c) * face_boost[k]
        me.uv_layers.active.data.foreach_set("uv", UV.ravel())
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.context.scene.tool_settings.use_uv_select_sync = True
        bpy.ops.uv.select_all(action="SELECT")
        bpy.ops.uv.pack_islands(rotate=True, margin=0.004)
        bpy.ops.object.mode_set(mode="OBJECT")
        return {"face_islands": int((face_boost > 1).sum()), "islands": n_isl}
    return {}


def make_material_pbr(name, img_c, img_n, roughness):
    import bpy
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img_c
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = img_n
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(n.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def save_and_reload(img, path, non_color):
    """바꾼 픽셀을 파일로 저장하고 그 파일을 새 이미지로 읽어 싼다(이미 싸인 이미지는 다시 pack()해도 옛 픽셀이 남는다: 2026-11-20 실측)."""
    import bpy
    name = img.name
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    new = bpy.data.images.load(str(path), check_existing=False)
    new.name = name
    if non_color:
        new.colorspace_settings.name = "Non-Color"
    new.pack()
    return new


def uv_raster(low, tex):
    """UV 공간의 텍셀마다 닿은 면의 3D 좌표를 보간해 돌려준다(tex x tex x 3, 이미지 행 0 = 아래 = Blender 픽셀 배열 순서)와 덮인 곳 마스크.
    이음 정리·부위 색 바꾸기가 '3D에서 같은 높이'를 질감에서 짚으려고 쓴다."""
    import numpy as np
    me = low.data
    me.calc_loop_triangles()
    P = rc.mesh_coords(low)
    uv = np.empty(len(me.loops) * 2)
    me.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2) * tex
    pos = np.zeros((tex, tex, 3), np.float32)
    cov = np.zeros((tex, tex), bool)
    for t in me.loop_triangles:
        q = uv[list(t.loops)]
        p3 = P[list(t.vertices)]
        x0, y0 = np.floor(q.min(axis=0)).astype(int)
        x1, y1 = np.ceil(q.max(axis=0)).astype(int)
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, tex - 1), min(y1, tex - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        d = (q[1, 1] - q[2, 1]) * (q[0, 0] - q[2, 0]) + (q[2, 0] - q[1, 0]) * (q[0, 1] - q[2, 1])
        if abs(d) < 1e-12:
            continue
        l0 = ((q[1, 1] - q[2, 1]) * (gx - q[2, 0]) + (q[2, 0] - q[1, 0]) * (gy - q[2, 1])) / d
        l1 = ((q[2, 1] - q[0, 1]) * (gx - q[2, 0]) + (q[0, 0] - q[2, 0]) * (gy - q[2, 1])) / d
        l2 = 1 - l0 - l1
        m = (l0 >= -0.02) & (l1 >= -0.02) & (l2 >= -0.02)
        if not m.any():
            continue
        xs, ys = gx[m].astype(int), gy[m].astype(int)
        pos[ys, xs] = (l0[m, None] * p3[0] + l1[m, None] * p3[1] + l2[m, None] * p3[2])
        cov[ys, xs] = True
    return pos, cov


def fill_band(px, band, cov, near, iters=60):
    """px(tex x tex x 4)의 band 텍셀을 band 밖 텍셀의 이웃 평균 확산으로 메운다(제자리)."""
    import numpy as np
    work = px[..., :3].copy()
    known = cov & ~band
    work[~known] = 0
    wgt = known.astype(np.float32)
    for it in range(iters):
        acc = np.zeros_like(work)
        cnt = np.zeros(wgt.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            acc += np.roll(work * wgt[..., None], (dy, dx), (0, 1))
            cnt += np.roll(wgt, (dy, dx), (0, 1))
        fill = band & (wgt == 0) & (cnt > 0)
        if not fill.any():
            break
        work[fill] = acc[fill] / cnt[fill][:, None]
        wgt[fill] = 1.0
    px[..., :3][near] = work[near]


def repair_face_seam(img_c, low, H, tex, log=print, seam_z_frac=None, img_n=None):
    """얼굴을 가로지르는 가는 선(생성 모델 질감 이음)을 찾아 지운다. 얼굴 앞면 텍셀을 높이 0.4mm 띠로 나눠 평균 밝기가 이웃 띠와 가장 다른 띠를 이음으로 보고,
    그 띠(와 위아래 1띠)를 주변 텍셀 평균으로 메운다. 반환: {z_m, dip, texels} 또는 {} (뚜렷한 이음이 없을 때)."""
    import numpy as np
    pos, cov = uv_raster(low, tex)
    px = np.array(img_c.pixels[:], dtype=np.float32).reshape(tex, tex, 4)
    lum = px[..., :3] @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    z = pos[..., 2]
    cx = float(np.median(pos[cov][:, 0]))
    face = cov & (z > 0.80 * H) & (z < 0.97 * H) & (np.abs(pos[..., 0] - cx) < 0.045 * H) & (pos[..., 1] < float(pos[cov][:, 1].min()) + 0.06 * H)
    if face.sum() < 2000:
        return {}
    bw = 0.0004 * H / 0.4 * 0.4
    zb = np.floor((z[face] - 0.80 * H) / bw).astype(int)
    L = lum[face]
    nb = zb.max() + 1
    mean = np.array([L[zb == i].mean() if (zb == i).sum() > 8 else np.nan for i in range(nb)])
    dev = np.full(nb, 0.0)
    for i in range(4, nb - 4):
        nbr = np.nanmean(np.concatenate([mean[i - 4:i - 1], mean[i + 2:i + 5]]))
        if not np.isnan(mean[i]) and not np.isnan(nbr):
            dev[i] = (nbr - mean[i])
    top = np.argsort(-np.abs(dev))[:8]
    cand = [(round(float((0.80 * H + (j + 0.5) * bw) / H), 4), round(float(dev[j]), 4)) for j in top]
    i = int(np.argmax(np.abs(dev)))
    zlist = [float(v) * H for v in seam_z_frac] if seam_z_frac else None
    if zlist:
        i = int(round((zlist[0] - 0.80 * H) / bw - 0.5))
    # 이웃과 어긋남이 평균 띠 흔들림의 5배 이상일 때만
    noise = float(np.nanstd(np.diff(mean)))
    if not seam_z_frac and abs(dev[i]) < 5 * max(noise, 1e-4):
        log("얼굴 이음: 뚜렷한 띠 없음 (dev %.4f noise %.4f)" % (dev[i], noise))
        return {"found": False, "dev": float(dev[i]), "noise": noise}
    zs = 0.80 * H + (i + 0.5) * bw
    zs_all = zlist or [zs]
    band = np.zeros_like(cov)
    for zq in zs_all:
        band |= cov & (np.abs(z - zq) < 2.4 * bw) & (z > 0.80 * H) & (z < 0.97 * H)
    near = band.copy()
    # 메우기: 띠 밖 텍셀에서 확산. 색과 노멀 맵 둘 다(이음선이 굽기에서 노멀 쪽에 들어가는 경우가 있다)
    before = px[..., :3].copy()
    fill_band(px, band, cov, near)
    changed = int((np.abs(px[..., :3] - before).sum(axis=2) > 0.01).sum())
    img_c.pixels[:] = px.ravel().tolist()
    if img_n is not None:
        pn = np.array(img_n.pixels[:], dtype=np.float32).reshape(tex, tex, 4)
        fill_band(pn, band, cov, near)
        v = pn[..., :3] * 2 - 1
        v /= np.maximum(np.linalg.norm(v, axis=2, keepdims=True), 1e-6)
        pn[..., :3] = v * 0.5 + 0.5
        img_n.pixels[:] = pn.ravel().tolist()
    return {"found": True, "candidates": cand, "z_m": float(zs), "z_frac": float(zs / H), "dev": float(dev[i]), "noise": noise, "texels": int(near.sum()), "changed": changed}


def recolor_region(low, img_c, rules, H, tex):
    """몸 텍스처의 한 부위에서 '푸르스름한 텍셀'을 맨살 색으로 바꾼다(생성 모델이 맨살 팔을 옅은 하늘색 소매처럼 구운 것을 고침).
    규칙(키 H 비율): side 'r'(캐릭터 오른쪽 = -X) 또는 'l', x_min(중심에서 이만큼 이상 바깥), z_range, blue_lo/blue_hi(파랑 - 빨강이 이 사이면 0~1로 섞음),
    max_sat(이보다 채도 높은 텍셀은 보석으로 보고 둠), ref {x_abs:[a,b], z_range:[a,b]}(맨살 색을 이 영역의 중앙값에서 가져옴: 허벅지 등), keep_detail(밝기 무늬 유지 지수).
    반환: 규칙별 바꾼 텍셀 수와 기준 맨살 색."""
    import numpy as np
    pos, cov = uv_raster(low, tex)
    px = np.array(img_c.pixels[:], dtype=np.float32).reshape(tex, tex, 4)
    rgb = px[..., :3]
    x, z = pos[..., 0], pos[..., 2]
    cx = float(np.median(pos[cov][:, 0]))
    lumw = np.array([0.2126, 0.7152, 0.0722], np.float32)
    out = {}
    for r in rules:
        sgn = -1.0 if r["side"] == "r" else 1.0
        dx = sgn * (x - cx)
        za, zb = r["z_range"]
        reg = cov & (dx >= r["x_min"] * H) & (z >= za * H) & (z <= zb * H)
        mx, mn = rgb.max(axis=2), rgb.min(axis=2)
        sat = (mx - mn) / np.maximum(mx, 1e-4)
        blue = rgb[..., 2] - rgb[..., 0]
        w = np.clip((blue - r.get("blue_lo", 0.04)) / max(r.get("blue_hi", 0.12) - r.get("blue_lo", 0.04), 1e-4), 0, 1)
        w = np.where(sat > r.get("max_sat", 0.5), 0.0, w)
        w = np.where(reg, w, 0.0)
        ra = r["ref"]
        refm = cov & (np.abs(x - cx) >= ra["x_abs"][0] * H) & (np.abs(x - cx) <= ra["x_abs"][1] * H) & (z >= ra["z_range"][0] * H) & (z <= ra["z_range"][1] * H) & (blue < 0.03)
        if refm.sum() < 200:
            out[r.get("name", "rule")] = {"error": "기준 맨살 영역 텍셀 %d개" % int(refm.sum())}
            continue
        ref = np.median(rgb[refm], axis=0)
        ref_l = float(np.median((rgb[refm] * lumw).sum(axis=1)))
        lum = (rgb * lumw).sum(axis=2, keepdims=True)
        sel = w > 0
        k = float(r.get("keep_detail", 0.8))
        reg_l = float(np.median(lum[sel])) if sel.any() else 1.0
        new = ref[None, :] * (lum[sel] / max(reg_l, 1e-4)) ** k
        new = np.clip(new, 0, 1)
        rgb[sel] = rgb[sel] * (1 - w[sel][:, None]) + new * w[sel][:, None]
        out[r.get("name", "rule")] = {"texels": int(sel.sum()), "ref_rgb_linear": [round(float(v), 3) for v in ref]}
    img_c.pixels[:] = px.ravel().tolist()
    return out


def main(argv):
    import bpy
    ap = argparse.ArgumentParser(description="생성 모델을 게임용으로 줄이고 질감을 굽는다")
    ap.add_argument("--in", dest="input", required=True)
    ap.add_argument("--out-glb", required=True)
    ap.add_argument("--work", required=True, help="텍스처 PNG·중간 파일 폴더(큰 파일은 D 드라이브)")
    ap.add_argument("--target", type=int, default=15000)
    ap.add_argument("--height", type=float, default=2.03, help="맞출 키(m). 기본 2.03 = 게임 본체의 HERO_MODEL_SCALE 1.32와 곱해 세계 키 2.67이 되는 값(옛 마법사와 같은 키). 계약 배율을 따로 둘 때는 2.67/배율")
    ap.add_argument("--facing", default="-Y")
    ap.add_argument("--tex", type=int, default=2048)
    ap.add_argument("--normal-tex", type=int, default=2048)
    ap.add_argument("--cage", type=float, default=0.01, help="굽기 광선 밀기(키 대비)")
    ap.add_argument("--uv-angle", type=float, default=70.0)
    ap.add_argument("--face-boost", type=float, default=1.8, help="머리 UV 섬을 키우는 배율(텍셀 밀도). 1이면 균일")
    ap.add_argument("--roughness", type=float, default=0.8)
    ap.add_argument("--protect", default="head,hands")
    ap.add_argument("--protect-share", type=float, default=0.30, help="삼각형 중 머리·손 몫(0.3 = 30%)")
    ap.add_argument("--fix-face-seam", action="store_true", help="얼굴을 가로지르는 질감 이음선을 찾아 메운다")
    ap.add_argument("--seam-z-frac", type=float, nargs="+", help="이음선 높이를 직접 지정(키 비율). 없으면 자동 탐지")
    ap.add_argument("--recolor-json", help="몸 텍스처 부위 색 바꾸기 규칙(JSON 목록)")
    ap.add_argument("--blend")
    ap.add_argument("--report")
    ap.add_argument("--no-silhouette", action="store_true")
    a = ap.parse_args(argv)
    work = Path(a.work)
    work.mkdir(parents=True, exist_ok=True)
    rc.reset_scene(30)
    rc.import_any(a.input)
    obj = rc.single_mesh_from_import({"mesh": {"min_vertices": 200, "drop_names": [], "facing": "-Y"}})
    rep = {"tool": "gen3d_prepare.py", "input": a.input, "target": a.target, "height_m": a.height}
    k = mr.normalize_pose(obj, a.height, a.facing)
    H = a.height
    rep["input_triangles"] = mr.tri_count(obj)
    rep["scale_applied"] = k
    rep["cleanup"] = mr.cleanup(obj, H)
    log("정리 끝 삼각형 %d" % mr.tri_count(obj))
    high = obj
    high.name = "high"
    rep["high_regions"] = region_tris(high, H)
    rep["high_metallic_unlinked"] = flatten_metallic(high)
    low = high.copy()
    low.data = high.data.copy()
    low.name = "low"
    bpy.context.scene.collection.objects.link(low)
    bpy.context.view_layer.update()
    bpy.context.view_layer.objects.active = low
    protect = [s for s in a.protect.split(",") if s]
    rep["protected_vertices"] = mr.protect_group(low, H, protect) if protect else 0
    final = decimate_weighted(low, H, a.target, a.protect_share, log) if protect else mr.decimate(low, a.target, False, keep_seams=False)
    for p in low.data.polygons:
        p.use_smooth = True
    low.vertex_groups.clear()
    rep["output_triangles"] = final
    rep["low_regions"] = region_tris(low, H)
    log("줄임 끝 %d (머리 %d, 손 %d)" % (final, rep["low_regions"]["head"], rep["low_regions"]["hands"]))
    rep["uv"] = unwrap_with_face_boost(low, H, a.uv_angle, a.face_boost)
    base = Path(a.out_glb).stem
    # 굽기: mesh_reduce.bake_pair는 머티리얼을 자기 것으로 갈아 끼우므로 그림만 쓰고 머티리얼은 아래에서 다시 만든다
    img_c, img_n, notes = mr.bake_pair(high, low, a.tex, a.normal_tex, a.cage * H, str(work), base)
    log("굽기 끝")
    if a.recolor_json:
        import json
        rules = json.loads(Path(a.recolor_json).read_text(encoding="utf-8"))
        rep["recolor"] = recolor_region(low, img_c, rules, H, a.tex)
    if a.fix_face_seam:
        rep["face_seam"] = repair_face_seam(img_c, low, H, a.tex, log, a.seam_z_frac, img_n)
    if a.recolor_json or a.fix_face_seam:
        img_c = save_and_reload(img_c, work / (base + "_color.png"), False)
        img_n = save_and_reload(img_n, work / (base + "_normal.png"), True)
    low.data.materials.clear()
    low.data.materials.append(make_material_pbr(base + "_mat", img_c, img_n, a.roughness))
    rep["textures"] = {"color": "%dx%d" % (a.tex, a.tex), "normal": "%dx%d" % (a.normal_tex, a.normal_tex), "roughness_const": a.roughness, "metallic_const": 0.0}
    rep["notes"] = notes
    if not a.no_silhouette:
        sil = mr.silhouette_compare(high, low, H, 8)
        rep["silhouette"] = {"iou_min": min(s["iou"] for s in sil), "iou_mean": sum(s["iou"] for s in sil) / len(sil), "mismatch_max": max(s["mismatch_ratio"] for s in sil), "views": sil}
    bpy.data.objects.remove(high, do_unlink=True)
    low.name = base
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    Path(a.out_glb).parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=a.out_glb, export_format="GLB", use_selection=True, export_yup=True, export_animations=False, export_apply=False, export_extras=False)
    rep["out_glb"] = a.out_glb
    rep["game_scale"] = 2.67 / H
    rep["seconds"] = round(time.time() - _T0, 1)
    if a.blend:
        bpy.ops.wm.save_as_mainfile(filepath=a.blend, compress=True)
    if a.report:
        rc.write_json(a.report, rep)
    print("GEN3D_PREPARE_DONE", rep["input_triangles"], "->", rep["output_triangles"], "iou", rep.get("silhouette", {}).get("iou_mean"))
    return 0


if __name__ == "__main__":
    rc.entry(__file__, main)
