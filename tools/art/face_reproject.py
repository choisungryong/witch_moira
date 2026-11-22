#!/usr/bin/env python3
"""정면 얼굴 그림을 3D 모델(glb)의 얼굴 살갗 텍셀에만 다시 입힌다 (메시·UV·텍스처 해상도는 그대로).

쓰는 법(Blender 없이 파이썬 + numpy + scipy + Pillow만 쓴다. 보기 그림은 gen3d_views.py로 따로 그린다):

  python face_reproject.py --model 모델.glb --image 정면얼굴.png --landmarks 표지점.json \
      --out-glb 새모델.glb --report 보고서.txt [--debug-dir 폴더] [옵션]

표지점 json 꼴(그림 쪽은 그림 픽셀, 모델 쪽은 둘 중 하나):
  {
    "image": {"eyeL": [u,v], "eyeR": [u,v], "nose": [u,v], "mouthL": [u,v], "mouthR": [u,v], "chin": [u,v]},
    "model": {"eyeL": [x, 위쪽좌표], ...},                # 미터. x는 화면 오른쪽(+), 위쪽좌표는 glTF의 y
    "model_px": {"eyeL": [px,py], ...},                   # 또는 정면 직교 그림(아래 model_view)의 픽셀
    "model_view": {"center": [0.0, 0.92], "width": 0.16, "size": 2048},
    "weights": {"chin": 0.5},                             # 선택: 표지점별 무게(기본 1)
    "mask_poly": [[u,v], ...]                             # 가리개 다각형(그림 픽셀). 이마~턱끝, 관자놀이 안쪽
  }
  표지점 이름은 image와 model(또는 model_px)에서 서로 같아야 한다. 짝 3개 이상.

방법:
 1) 짝지은 표지점으로 모델(x,위) -> 그림(u,v) 아핀 변환을 최소제곱으로 구한다.
 2) 모델을 정면 직교(+Z에서 -Z로)로 그려 깊이 지도를 만들고, 깊이의 중앙값 곡면보다 --skin-tol 이상 앞에 튀어나온
    것(머리카락 가닥·속눈썹 판)과 뒤에 있는 것(뒤통수)은 살갗이 아니라고 본다.
 3) 텍스처의 각 텍셀(UV 삼각형 안, 틈새 --pad 텍셀 포함)을 3D 점으로 되돌려, 살갗이면서 가리개 안이면
    그림의 색을 입힌다. 가리개 = 다각형을 --feather 픽셀로 번지게 한 것 x 앞면 각도 무게(법선 z가 --face-lo에서 --face-hi로).
 4) 색 맞춤: 가리개 가장자리 띠(번짐 값 --ring-lo~--ring-hi)에서 (원래 살갗 - 입힌 그림)의 평균을 큰 가우시안
    (--color-sigma 미터)으로 퍼뜨린 저주파 차이를 --color-strength 만큼 그림에 더한다(저주파만 더하므로 눈·입술·눈썹의 대비는 남는다).
 5) glb의 텍스처 이미지만 JPEG(--jpeg-quality)로 바꿔 쓴다. 나머지 바이트(정점·UV·법선·인덱스)는 그대로다.
"""
import argparse
import io
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

Image.MAX_IMAGE_PIXELS = None


# ---------------------------------------------------------------- glb 입출력
def read_glb(p):
    b = Path(p).read_bytes()
    _, _, ln = struct.unpack('<III', b[:12])
    off = 12
    js = bin_ = None
    while off < ln:
        cl, ct = struct.unpack('<II', b[off:off + 8])
        d = b[off + 8:off + 8 + cl]
        off += 8 + cl
        if ct == 0x4E4F534A:
            js = json.loads(d)
        elif ct == 0x004E4942:
            bin_ = d
    return js, bin_


def accessor(js, bin_, i):
    a = js['accessors'][i]
    bv = js['bufferViews'][a['bufferView']]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
    dt = {5126: '<f4', 5123: '<u2', 5125: '<u4', 5121: 'u1'}[a['componentType']]
    o = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    return np.frombuffer(bin_, dtype=dt, count=a['count'] * n, offset=o).reshape(a['count'], n)


def write_glb(p, js, bin_):
    j = json.dumps(js, separators=(',', ':')).encode()
    j += b' ' * ((4 - len(j) % 4) % 4)
    bn = bin_ + b'\0' * ((4 - len(bin_) % 4) % 4)
    with open(p, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(j) + 8 + len(bn)))
        f.write(struct.pack('<II', len(j), 0x4E4F534A)); f.write(j)
        f.write(struct.pack('<II', len(bn), 0x004E4942)); f.write(bn)


def replace_image(js, bin_, img_index, jpeg_bytes):
    """img_index번 이미지의 bufferView 바이트만 바꿔 새 (js, bin)을 돌려준다."""
    target = js['images'][img_index]['bufferView']
    parts = []
    off = 0
    for i, bv in enumerate(js['bufferViews']):
        o = bv.get('byteOffset', 0)
        data = jpeg_bytes if i == target else bin_[o:o + bv['byteLength']]
        pad = (4 - len(data) % 4) % 4
        bv['byteOffset'] = off
        bv['byteLength'] = len(data)
        parts.append(data + b'\0' * pad)
        off += len(data) + pad
    js['buffers'][0]['byteLength'] = off
    return js, b''.join(parts)


# ---------------------------------------------------------------- 래스터
def raster_depth(V2, T, zv, W, H, subset):
    """깊이 시험(가까운 z 승). tri id, bary, z 를 돌려준다."""
    tid = -np.ones((H, W), np.int32)
    bar = np.zeros((H, W, 3), np.float32)
    zb = np.full((H, W), -1e9, np.float32)
    for t in subset:
        a, b, c = V2[T[t, 0]], V2[T[t, 1]], V2[T[t, 2]]
        x0 = max(int(np.floor(min(a[0], b[0], c[0]))) - 1, 0); x1 = min(int(np.ceil(max(a[0], b[0], c[0]))) + 1, W - 1)
        y0 = max(int(np.floor(min(a[1], b[1], c[1]))) - 1, 0); y1 = min(int(np.ceil(max(a[1], b[1], c[1]))) + 1, H - 1)
        if x1 < x0 or y1 < y0:
            continue
        X, Y = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-12:
            continue
        l0 = ((b[1] - c[1]) * (X - c[0]) + (c[0] - b[0]) * (Y - c[1])) / d
        l1 = ((c[1] - a[1]) * (X - c[0]) + (a[0] - c[0]) * (Y - c[1])) / d
        l2 = 1 - l0 - l1
        ok = (l0 >= -1e-6) & (l1 >= -1e-6) & (l2 >= -1e-6)
        z = l0 * zv[T[t, 0]] + l1 * zv[T[t, 1]] + l2 * zv[T[t, 2]]
        sub = zb[y0:y1 + 1, x0:x1 + 1]
        upd = ok & (z > sub)
        if not upd.any():
            continue
        sub[upd] = z[upd]
        tid[y0:y1 + 1, x0:x1 + 1][upd] = t
        bb = bar[y0:y1 + 1, x0:x1 + 1]
        bb[..., 0][upd] = l0[upd]; bb[..., 1][upd] = l1[upd]; bb[..., 2][upd] = l2[upd]
    return tid, bar, zb


def raster_collect(V2, T, subset, pad, W, H):
    """UV 공간 래스터. 삼각형 안과 틈새(pad 텍셀)의 텍셀을 모아 (tri, x, y, bary, 점수)로 돌려준다.
    같은 텍셀은 점수(가장자리까지 부호 있는 거리, 안쪽이 큼)가 큰 쪽이 이긴다."""
    out = []
    for t in subset:
        a, b, c = V2[T[t, 0]], V2[T[t, 1]], V2[T[t, 2]]
        x0 = max(int(np.floor(min(a[0], b[0], c[0]) - pad - 1)), 0); x1 = min(int(np.ceil(max(a[0], b[0], c[0]) + pad + 1)), W - 1)
        y0 = max(int(np.floor(min(a[1], b[1], c[1]) - pad - 1)), 0); y1 = min(int(np.ceil(max(a[1], b[1], c[1]) + pad + 1)), H - 1)
        if x1 < x0 or y1 < y0:
            continue
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-9:
            continue
        X, Y = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        l0 = ((b[1] - c[1]) * (X - c[0]) + (c[0] - b[0]) * (Y - c[1])) / d
        l1 = ((c[1] - a[1]) * (X - c[0]) + (a[0] - c[0]) * (Y - c[1])) / d
        l2 = 1 - l0 - l1
        ad = abs(d)
        s = np.minimum(np.minimum(l0 * ad / (np.hypot(c[0] - b[0], c[1] - b[1]) + 1e-12),
                                  l1 * ad / (np.hypot(a[0] - c[0], a[1] - c[1]) + 1e-12)),
                       l2 * ad / (np.hypot(b[0] - a[0], b[1] - a[1]) + 1e-12))
        if d < 0:
            pass  # 부호는 l 이 이미 반영(안쪽이면 양수)
        ok = s >= -pad
        if not ok.any():
            continue
        yy, xx = np.nonzero(ok)
        out.append((np.full(len(yy), t, np.int32), (xx + x0).astype(np.int32), (yy + y0).astype(np.int32),
                    l0[ok].astype(np.float32), l1[ok].astype(np.float32), l2[ok].astype(np.float32), s[ok].astype(np.float32)))
    if not out:
        return None
    cat = [np.concatenate([o[i] for o in out]) for i in range(7)]
    key = cat[2].astype(np.int64) * W + cat[1]
    order = np.lexsort((cat[6], key))
    key = key[order]
    last = np.ones(len(key), bool)
    last[:-1] = key[1:] != key[:-1]
    sel = order[last]
    return [c[sel] for c in cat]


def smoothstep(a, b, x):
    t = np.clip((x - a) / max(b - a, 1e-9), 0, 1)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- 본체
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--model', required=True)
    ap.add_argument('--image', required=True)
    ap.add_argument('--landmarks', required=True)
    ap.add_argument('--out-glb', required=True)
    ap.add_argument('--report', required=True)
    ap.add_argument('--debug-dir')
    ap.add_argument('--grid', type=int, default=2048, help='정면 직교 지도 한 변(픽셀)')
    ap.add_argument('--view-center', type=float, nargs=2, default=None, help='정면 지도 중심(x, 위). 기본: json의 model_view')
    ap.add_argument('--view-width', type=float, default=None, help='정면 지도가 덮는 폭(미터). 기본: json의 model_view')
    ap.add_argument('--feather', type=float, default=45.0, help='가리개 번짐(가우시안 시그마, 그림 픽셀)')
    ap.add_argument('--mask-grow', type=float, default=0.0, help='가리개 다각형을 이 픽셀만큼 부풀림(음수=줄임)')
    ap.add_argument('--face-lo', type=float, default=0.35, help='법선 z가 이 값 이하면 무게 0')
    ap.add_argument('--face-hi', type=float, default=0.80, help='법선 z가 이 값 이상이면 무게 1')
    ap.add_argument('--skin-tol', type=float, default=0.0008, help='살갗 판정: 깊이 중앙값 곡면과의 허용 차이(미터)')
    ap.add_argument('--pad', type=float, default=3.0, help='텍스처 틈새로 번질 텍셀 수')
    ap.add_argument('--strength', type=float, default=1.0, help='입히는 세기(0~1)')
    ap.add_argument('--color-strength', type=float, default=1.0, help='색 맞춤 세기(0=끔)')
    ap.add_argument('--color-sigma', type=float, default=0.02, help='색 맞춤 차이를 퍼뜨리는 가우시안(미터)')
    ap.add_argument('--ring-lo', type=float, default=0.03)
    ap.add_argument('--ring-hi', type=float, default=0.65)
    ap.add_argument('--jpeg-quality', type=int, default=94)
    a = ap.parse_args()

    log = []

    def say(*s):
        t = ' '.join(str(x) for x in s)
        print(t, flush=True)
        log.append(t)

    # --- 모델
    js, bin_ = read_glb(a.model)
    prim = js['meshes'][0]['primitives'][0]
    P = accessor(js, bin_, prim['attributes']['POSITION']).astype(np.float64)
    N = accessor(js, bin_, prim['attributes']['NORMAL']).astype(np.float64)
    UV = accessor(js, bin_, prim['attributes']['TEXCOORD_0']).astype(np.float64)
    T = accessor(js, bin_, prim['indices']).reshape(-1, 3).astype(np.int64)
    bvi = js['images'][0]['bufferView']
    bv = js['bufferViews'][bvi]
    tex = np.array(Image.open(io.BytesIO(bin_[bv['byteOffset']:bv['byteOffset'] + bv['byteLength']])).convert('RGB'))
    TH, TW = tex.shape[:2]
    say('model', a.model, 'tris', len(T), 'verts', len(P), 'tex', (TW, TH))

    # --- 표지점 -> 아핀
    lm = json.loads(Path(a.landmarks).read_text(encoding='utf-8'))
    mv = lm.get('model_view', {})
    vc = a.view_center or mv.get('center', [0.0, 0.92])
    vw = a.view_width or mv.get('width', 0.16)
    S = a.grid
    msrc = {}
    if 'model' in lm:
        msrc.update({k: tuple(v) for k, v in lm['model'].items()})
    for k, v in lm.get('model_px', {}).items():
        sz = mv.get('size', 2048)
        msrc[k] = ((v[0] / sz - 0.5) * mv.get('width', vw) + mv.get('center', vc)[0],
                   mv.get('center', vc)[1] + (0.5 - v[1] / sz) * mv.get('width', vw))
    names = [k for k in lm['image'] if k in msrc]
    wts = np.array([lm.get('weights', {}).get(k, 1.0) for k in names])
    Xm = np.array([[msrc[k][0], msrc[k][1], 1.0] for k in names])
    Yi = np.array([lm['image'][k] for k in names], float)
    sw = np.sqrt(wts)[:, None]
    coef, *_ = np.linalg.lstsq(Xm * sw, Yi * sw, rcond=None)     # (3,2): [u,v] = [x,up,1] @ coef
    pred = Xm @ coef
    say('landmarks', names)
    for k, p, y in zip(names, pred, Yi):
        say('  %-8s 그림 (%.0f,%.0f)  변환한 모델점 (%.0f,%.0f)  어긋남 %.1f px' % (k, y[0], y[1], p[0], p[1], np.hypot(*(p - y))))
    A = coef.T[:, :2]
    say('affine [u,v] = A [x,up] + t : A=', np.round(A, 1).tolist(), 't=', np.round(coef[2], 1).tolist(),
        ' (미터->그림픽셀; 배율 가로 %.0f 세로 %.0f 픽셀/미터)' % (np.hypot(*A[:, 0]), np.hypot(*A[:, 1])))

    def to_img(x, up):
        return x * coef[0, 0] + up * coef[1, 0] + coef[2, 0], x * coef[0, 1] + up * coef[1, 1] + coef[2, 1]

    # --- 그림, 가리개
    img = np.asarray(Image.open(a.image).convert('RGB')).astype(np.float32)
    IH, IW = img.shape[:2]
    poly = lm['mask_poly']
    from PIL import ImageDraw, ImageFilter
    mk = Image.new('L', (IW, IH), 0)
    ImageDraw.Draw(mk).polygon([tuple(p) for p in poly], fill=255)
    if a.mask_grow:
        mk = mk.filter(ImageFilter.MaxFilter(int(abs(a.mask_grow)) * 2 + 1)) if a.mask_grow > 0 else mk.filter(ImageFilter.MinFilter(int(abs(a.mask_grow)) * 2 + 1))
    maskf = ndi.gaussian_filter(np.asarray(mk, np.float32) / 255.0, a.feather)
    if a.debug_dir:
        Path(a.debug_dir).mkdir(parents=True, exist_ok=True)

    def samp_img(u, v):
        co = np.stack([v - 0.5, u - 0.5])
        return np.stack([ndi.map_coordinates(img[..., c], co, order=1, mode='nearest') for c in range(3)], 1)

    def samp_mask(u, v):
        return ndi.map_coordinates(maskf, np.stack([v - 0.5, u - 0.5]), order=1, mode='constant', cval=0.0)

    # --- 정면 직교 지도(깊이·색)
    x0w = vc[0] - vw / 2
    ytop = vc[1] + vw / 2
    gx = (P[:, 0] - x0w) / vw * S
    gy = (ytop - P[:, 1]) / vw * S
    V2 = np.stack([gx, gy], 1)
    inwin = ((V2[T, 0] > -50).all(1) & (V2[T, 0] < S + 50).all(1) & (V2[T, 1] > -50).all(1) & (V2[T, 1] < S + 50).all(1))
    sub = np.where(inwin)[0]
    say('정면 지도 삼각형', len(sub))
    tid, bar, zb = raster_depth(V2, T, P[:, 2], S, S, sub)
    vis = tid >= 0
    zz = np.where(vis, zb, -0.05)
    h = S // 2
    med = ndi.median_filter(zz[::2, ::2], size=21)
    med = np.kron(med, np.ones((2, 2)))[:S, :S]
    resid = zz - med

    tt = T[np.maximum(tid, 0)]
    uvf = (UV[tt] * bar[..., None]).sum(2)
    uu = np.clip((uvf[..., 0] * TW).astype(int), 0, TW - 1)
    vv = np.clip((uvf[..., 1] * TH).astype(int), 0, TH - 1)
    cfront = tex[vv, uu].astype(np.float32)
    skin_front = vis & (resid < a.skin_tol)
    skin_front = ndi.binary_erosion(skin_front, iterations=2)       # 가닥·속눈썹 가장자리에서 2픽셀 물러선다

    # 그림을 정면 격자로 옮긴 것, 가리개도
    gxs = (np.arange(S) + 0.5) / S * vw + x0w
    gys = ytop - (np.arange(S) + 0.5) / S * vw
    GX, GY = np.meshgrid(gxs, gys)
    FU, FV = to_img(GX, GY)
    img_front = np.stack([ndi.map_coordinates(img[..., c], np.stack([FV - 0.5, FU - 0.5]), order=1, mode='nearest') for c in range(3)], -1)
    mask_front = ndi.map_coordinates(maskf, np.stack([FV - 0.5, FU - 0.5]), order=1, mode='constant', cval=0.0)

    # --- 색 맞춤 차이장
    corr = np.zeros((S, S, 3), np.float32)
    if a.color_strength > 0:
        ring = skin_front & (mask_front > a.ring_lo) & (mask_front < a.ring_hi)
        say('색 맞춤 띠 픽셀', int(ring.sum()))
        if ring.sum() > 500:
            sg = a.color_sigma / vw * S
            w = ring.astype(np.float32)
            den = ndi.gaussian_filter(w, sg) + 1e-6
            gmean = ((cfront - img_front) * w[..., None]).sum((0, 1)) / w.sum()
            for c in range(3):
                num = ndi.gaussian_filter((cfront[..., c] - img_front[..., c]) * w, sg)
                wgt = np.clip(den / 0.02, 0, 1)             # 띠에서 먼 곳은 전체 평균으로
                corr[..., c] = (num / den) * wgt + gmean[c] * (1 - wgt)
            say('색 맞춤 전체 평균 차이(RGB)', np.round(gmean, 1).tolist())
        corr *= a.color_strength

    # --- 텍셀 후보 삼각형
    cen = P[T].mean(1)
    cgx = ((cen[:, 0] - x0w) / vw * S).astype(int)
    cgy = ((ytop - cen[:, 1]) / vw * S).astype(int)
    ok = (cgx >= 0) & (cgx < S) & (cgy >= 0) & (cgy < S)
    cand = np.zeros(len(T), bool)
    ii = np.where(ok)[0]
    cand[ii] = (mask_front[cgy[ii], cgx[ii]] > 0.002) & (np.abs(cen[ii, 2] - med[cgy[ii], cgx[ii]]) < 0.01)
    cand_idx = np.where(cand)[0]
    say('후보 삼각형', len(cand_idx))
    UVpx = np.stack([UV[:, 0] * TW, UV[:, 1] * TH], 1)
    col = raster_collect(UVpx, T, cand_idx, a.pad, TW, TH)
    tri, tx, ty, l0, l1, l2, sc = col
    say('후보 텍셀', len(tri))
    Tt = T[tri]
    L = np.stack([l0, l1, l2], 1).astype(np.float64)
    pos = (P[Tt] * L[..., None]).sum(1)
    nor = (N[Tt] * L[..., None]).sum(1)
    nor /= np.linalg.norm(nor, axis=1, keepdims=True) + 1e-9
    px_ = np.clip(((pos[:, 0] - x0w) / vw * S).astype(int), 0, S - 1)
    py_ = np.clip(((ytop - pos[:, 1]) / vw * S).astype(int), 0, S - 1)
    inwin_t = ((pos[:, 0] - x0w) / vw * S >= 0) & ((pos[:, 0] - x0w) / vw * S < S) & ((ytop - pos[:, 1]) / vw * S >= 0) & ((ytop - pos[:, 1]) / vw * S < S)
    dz = pos[:, 2] - med[py_, px_]
    skin = inwin_t & (np.abs(dz) < a.skin_tol)
    # 가닥·속눈썹이 덮은 곳의 살갗은 보이지 않아도 곡면 위에 있으면 살갗으로 친다(위의 |dz| 시험)
    u, v = to_img(pos[:, 0], pos[:, 1])
    mw = samp_mask(u, v)
    wf = smoothstep(a.face_lo, a.face_hi, nor[:, 2])
    W = (mw * wf * skin * a.strength).astype(np.float32)
    keep = W > 1e-4
    say('칠할 텍셀', int(keep.sum()), '(무게>0.5: %d)' % int((W > 0.5).sum()))
    new = samp_img(u[keep], v[keep]) + corr[py_[keep], px_[keep]]
    new = np.clip(new, 0, 255)
    xs, ys, Wk = tx[keep], ty[keep], W[keep]
    old = tex[ys, xs].astype(np.float32)
    out = tex.copy()
    out[ys, xs] = np.clip(np.rint(old * (1 - Wk[:, None]) + new * Wk[:, None]), 0, 255).astype(np.uint8)

    # --- 저장
    buf = io.BytesIO()
    Image.fromarray(out).save(buf, format='JPEG', quality=a.jpeg_quality, subsampling=0, optimize=True)
    js2, bin2 = replace_image(js, bin_, 0, buf.getvalue())
    Path(a.out_glb).parent.mkdir(parents=True, exist_ok=True)
    write_glb(a.out_glb, js2, bin2)
    say('wrote', a.out_glb, 'tex jpeg', len(buf.getvalue()), 'bytes; glb', Path(a.out_glb).stat().st_size)

    if a.debug_dir:
        d = Path(a.debug_dir)
        Image.fromarray((np.clip(mask_front, 0, 1) * 255).astype(np.uint8)).save(d / 'mask_front.png')
        Image.fromarray(np.clip(img_front, 0, 255).astype(np.uint8)).save(d / 'img_front.png')
        Image.fromarray((skin_front * 255).astype(np.uint8)).save(d / 'skin_front.png')
        Image.fromarray(np.clip(cfront, 0, 255).astype(np.uint8)).save(d / 'orig_front.png')
        Image.fromarray(np.clip(img_front + corr, 0, 255).astype(np.uint8)).save(d / 'img_front_corrected.png')
        Image.fromarray((maskf * 255).astype(np.uint8)).save(d / 'mask_on_image.png')
    Path(a.report).parent.mkdir(parents=True, exist_ok=True)
    Path(a.report).write_text('\n'.join(log) + '\n', encoding='utf-8')


if __name__ == '__main__':
    sys.exit(main())
