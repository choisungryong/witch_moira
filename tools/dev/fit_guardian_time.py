"""Fits a guardian-time model to measured guardian kill times and predicts a damage_bps curve (a MODEL answer, not a measurement).

    python tools/dev/fit_guardian_time.py --none <src json,...> --runs LABEL=<json,...>[|kit,kit] ... --reads <reads json,...> --out _local/x/fit.json
        [--curve K,s ...] [--curve-kits kit.f2v.@.r15.q25,...] [--boot 4000] [--seed 20261124]

Model, per primary (ember / frost / arc): time = o + w / (damage * rate^beta * shape^gamma). beta and gamma are shared by the three primaries; o and w are
per primary. The fraction f = o / (o + w) is the per-primary fixed share of the bare time, so the predicted time ratio of a kit against the bare hero is
    ratio = f + (1 - f) / m,   m = damage * rate^beta * shape^gamma.
For a given (beta, gamma), f of each primary is the closed-form least squares value (clipped to 0..0.95); beta and gamma come from a grid (default step 0.05, 0..1.5).
The squared error is the sum over the data points of (predicted ratio - measured ratio)^2, every point weighs the same.

Inputs
  --none   measure_rhythm result files of the bare hero (kit "none"); the paired ratio of a kit run is taken against the none run of the same primary and seed.
  --runs   LABEL=path[,path...][|kit,kit]  measure_rhythm result files with kit runs. Every (kit, primary) of a label is one data point. A path may hold * . "|kit,kit"
           keeps only those kit names. A kit name with "@" is the primary's own series (kit.f2.@.r15 -> kit.f2.ember.r15 in the reads file).
  --reads  report_kit_reads result files (rows of kit x primary with the totals). damage, rate and shape are recomputed from the totals with the keys of
           loot.json upgrade_verdict (--loot, default chapter1/data/loot.json) and must equal the file's own numbers (1e-6) or the tool stops.
Measured ratio of a point = median over seeds of (median over the guardians of kit time / none time) (the an_final.py definition: guardian kinds that died in both).
Volley (first volley shots) does not change guardian times (VR-B 9.1 (1)), so runs of the volley-on and volley-off paths can be fitted together; that is the caller's choice.

Curve (--curve K,s, repeatable): the equipment sum D of damage_bps becomes D' = D if D <= K else K + (D - K) * s; the damage factor is recomputed (the primary's other damage keys, fire_damage_bps and
arc_damage_bps, are untouched) and the ratio is predicted with the fitted model for --curve-kits (default kit.f2v.@.r15.q25, .q50, .q75, three primaries). M2 per curve (lines fixed before the result):
ember ratio >= 0.50 in at least 2 of 3 kits, frost and arc ratio <= 0.70 each in at least 2 of 3, every prediction in 0.40..0.80; the chosen curve is the passing one with the largest K, then the largest s.
M1: every residual (predicted - measured) of a data point within +-0.08; three or more outside means the model is not to be trusted.
Bands: seeds of every data point are resampled with replacement --boot times (default 4000, seed --seed); a line that lies inside the 10..90 % band of its value is written "boundary".
Everything printed is a model answer; the measured ratios are bot runs.
"""
import argparse
import glob
import json
import math
import random
import statistics
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PRIMS = ['ember', 'frost', 'arc']
RESID_LIMIT = 0.08


def prim_name(value):
    return str(value).split('.')[-1]


def expand(spec):
    out = []
    for part in spec.split(','):
        part = part.strip()
        if not part:
            continue
        hits = sorted(glob.glob(part))
        if not hits:
            raise SystemExit('fit_guardian_time: no file for %r' % part)
        out.extend(hits)
    return out


def load_runs(paths):
    runs = []
    for p in paths:
        with open(p, encoding='utf-8') as f:
            runs.extend(json.load(f)['runs'])
    return runs


def guardian_times(run):
    return {b['kind']: b['lived_s'] for b in run['sweep']['big'] if str(b['kind']).startswith('guardian') and b.get('death_s', -1) >= 0}


def seed_ratios(none_runs, kit_runs):
    """{seed: median over shared guardians of kit time / none time}."""
    base = {r['seed']: guardian_times(r) for r in none_runs}
    out = {}
    for r in kit_runs:
        gn = base.get(r['seed'])
        if not gn:
            continue
        gk = guardian_times(r)
        vals = [gk[k] / gn[k] for k in gn if k in gk and gn[k] > 0]
        if vals:
            out[r['seed']] = statistics.median(vals)
    return out


def verdict_block(loot_path):
    with open(loot_path, encoding='utf-8') as f:
        return json.load(f)['upgrade_verdict']


def factors(totals, prim, block, curve=None):
    """damage, rate, shape of one kit for one primary, the way loot._verdict_worth reads them. curve = (K, s) bends damage_bps."""
    pid = 'chapter1.skill.' + prim
    damage = 1.0
    for key in block['damage_keys'][pid]:
        v = float(totals.get(key, 0))
        if curve is not None and key == 'damage_bps':
            k, s = curve
            v = v if v <= k else k + (v - k) * s
        damage *= max(.05, 1.0 + v / 10000.0)
    rate = max(.1, 1.0 + float(totals.get(block['cooldown_key'], 0)) / 10000.0)
    count = sum(int(totals.get(key, 0)) for key in block['shape_keys'][pid])
    base = max(1, int(block['shots_r1'][pid]))
    shape = max(.05, 1.0 + float(block['shape_share']) * count / base)
    return damage, rate, shape


def build_points(none_runs, run_specs, reads_rows, block):
    points = []
    for label, paths, kits in run_specs:
        runs = load_runs(paths)
        groups = {}
        for r in runs:
            if r['kit'] == 'none':
                continue
            if kits and r['kit'] not in kits:
                continue
            groups.setdefault((r['kit'], prim_name(r['primary'])), []).append(r)
        for (kit, prim), rs in sorted(groups.items()):
            real = kit.replace('@', prim)
            row = reads_rows.get((real, prim))
            if row is None:
                print('fit_guardian_time: no reads row for %s / %s (point %s skipped)' % (real, prim, label), file=sys.stderr)
                continue
            damage, rate, shape = factors(row['totals'], prim, block)
            for name, mine in (('damage', damage), ('rate', rate), ('shape', shape)):
                if abs(mine - float(row[name])) > 1e-6:
                    raise SystemExit('fit_guardian_time: %s of %s/%s differs from the reads file (%.9f vs %.9f)' % (name, real, prim, mine, float(row[name])))
            nr = [r for r in none_runs if prim_name(r['primary']) == prim]
            ratios = seed_ratios(nr, rs)
            if not ratios:
                continue
            points.append({'label': label, 'kit': kit, 'real_kit': real, 'primary': prim, 'n': len(ratios), 'seed_ratios': ratios, 'obs': statistics.median(ratios.values()),
                           'damage': damage, 'rate': rate, 'shape': shape, 'totals': row['totals']})
    return points


def fit(points, step=0.05, top=1.5):
    """Grid over beta, gamma; f per primary closed form. Returns {beta, gamma, f:{prim}, sse}."""
    n = int(round(top / step))
    best = None
    ln = [(math.log(p['damage']), math.log(p['rate']), math.log(p['shape']), p['obs'], p['primary']) for p in points]
    for ib in range(n + 1):
        beta = ib * step
        for ig in range(n + 1):
            gamma = ig * step
            acc = {pr: [0.0, 0.0, 0.0, 0.0] for pr in PRIMS}  # sum b*b, sum b*(obs-a), sum (obs-a)^2, count
            for ld, lr, ls, obs, pr in ln:
                a = math.exp(-(ld + beta * lr + gamma * ls))
                b = 1.0 - a
                d = obs - a
                s = acc[pr]
                s[0] += b * b
                s[1] += b * d
                s[2] += d * d
                s[3] += 1
            sse = 0.0
            f = {}
            for pr in PRIMS:
                bb, bd, dd, cnt = acc[pr]
                if cnt == 0:
                    f[pr] = None
                    continue
                fv = bd / bb if bb > 1e-12 else 0.0
                fv = min(0.95, max(0.0, fv))
                f[pr] = fv
                sse += dd - 2 * fv * bd + fv * fv * bb
            if best is None or sse < best['sse'] - 1e-15:
                best = {'beta': beta, 'gamma': gamma, 'f': f, 'sse': sse}
    return best


def predict(model, damage, rate, shape, prim):
    m = damage * (rate ** model['beta']) * (shape ** model['gamma'])
    f = model['f'][prim]
    if f is None:
        f = 0.0
    return f + (1.0 - f) / m


def band(values, lo=10, hi=90):
    v = sorted(values)
    n = len(v)
    return v[int(lo / 100.0 * (n - 1))], v[int(.5 * (n - 1))], v[int(hi / 100.0 * (n - 1))]


def in_band(line, b):
    return b[0] <= line <= b[2]


def m2_eval(preds, bands):
    """preds {(kit, prim): ratio}, bands {(kit, prim): (p10, p50, p90)}; kits = ordered list of kit names. Returns {pass, notes}."""
    kits = sorted({k for k, _ in preds})
    ok_e = sum(1 for k in kits if preds[(k, 'ember')] >= 0.50)
    ok_f = sum(1 for k in kits if preds[(k, 'frost')] <= 0.70)
    ok_a = sum(1 for k in kits if preds[(k, 'arc')] <= 0.70)
    inside = all(0.40 <= v <= 0.80 for v in preds.values())
    need = max(2, (2 * len(kits) + 2) // 3) if len(kits) != 3 else 2
    passed = ok_e >= need and ok_f >= need and ok_a >= need and inside
    notes = []
    if bands:
        for (k, pr), b in sorted(bands.items()):
            for line, what in ((0.50, 'ember >= 0.50'), (0.70, 'frost/arc <= 0.70'), (0.40, 'floor 0.40'), (0.80, 'ceiling 0.80')):
                if (what.startswith('ember') and pr != 'ember') or (what.startswith('frost') and pr == 'ember'):
                    continue
                if in_band(line, b):
                    notes.append('%s %s: line %.2f inside the 10..90 band %.3f..%.3f' % (k, pr, line, b[0], b[2]))
    return {'pass': passed, 'ember_ge_050': ok_e, 'frost_le_070': ok_f, 'arc_le_070': ok_a, 'all_in_040_080': inside, 'boundary_notes': notes}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--none', required=True)
    ap.add_argument('--runs', action='append', required=True, help='LABEL=path[,path...][|kit,kit]')
    ap.add_argument('--reads', required=True)
    ap.add_argument('--loot', default=str(REPO / 'chapter1' / 'data' / 'loot.json'))
    ap.add_argument('--curve', action='append', default=[], help='K,s')
    ap.add_argument('--curve-kits', default='kit.f2v.@.r15.q25,kit.f2v.@.r15.q50,kit.f2v.@.r15.q75')
    ap.add_argument('--boot', type=int, default=4000)
    ap.add_argument('--seed', type=int, default=20261124)
    ap.add_argument('--step', type=float, default=0.05)
    ap.add_argument('--out', default='')
    a = ap.parse_args(argv)

    block = verdict_block(a.loot)
    none_runs = [r for r in load_runs(expand(a.none)) if r['kit'] == 'none']
    reads_rows = {}
    for p in expand(a.reads):
        with open(p, encoding='utf-8') as f:
            for row in json.load(f)['rows']:
                reads_rows[(row['kit'], row['primary'])] = row
    specs = []
    for spec in a.runs:
        label, _, rest = spec.partition('=')
        paths_part, _, kit_part = rest.partition('|')
        specs.append((label, expand(paths_part), [k for k in kit_part.split(',') if k] if kit_part else []))
    points = build_points(none_runs, specs, reads_rows, block)
    if len(points) < 3:
        raise SystemExit('fit_guardian_time: %d data points are too few' % len(points))
    model = fit(points, a.step)
    bare = {}
    for pr in PRIMS:
        ts = [statistics.median(guardian_times(r).values()) for r in none_runs if prim_name(r['primary']) == pr and guardian_times(r)]
        bare[pr] = statistics.median(ts) if ts else None

    rng = random.Random(a.seed)
    lines = []

    def P(*x):
        s = ' '.join(str(v) for v in x)
        print(s)
        lines.append(s)

    P('FIT (model answer) beta=%.2f gamma=%.2f sse=%.5f points=%d' % (model['beta'], model['gamma'], model['sse'], len(points)))
    fixed = {}
    for pr in PRIMS:
        f = model['f'][pr]
        if f is None or bare[pr] is None:
            continue
        fixed[pr] = {'f': f, 'bare_s': bare[pr], 'o_s': f * bare[pr], 'w_s': (1 - f) * bare[pr]}
        P('  %-5s bare %.1f s  f=%.3f  fixed time o=%.1f s  work w=%.1f s' % (pr, bare[pr], f, f * bare[pr], (1 - f) * bare[pr]))

    # resample the seeds of every point
    boots_obs = []
    for _ in range(a.boot):
        row = []
        for p in points:
            vals = list(p['seed_ratios'].values())
            row.append(statistics.median([vals[rng.randrange(len(vals))] for _ in vals]))
        boots_obs.append(row)
    resid_bands = []
    for i, p in enumerate(points):
        pred = predict(model, p['damage'], p['rate'], p['shape'], p['primary'])
        p['pred'] = pred
        p['resid'] = pred - p['obs']
        resid_bands.append(band([pred - b[i] for b in boots_obs]))
    outside = [p for p in points if abs(p['resid']) > RESID_LIMIT]
    P('M1 residual (predicted - measured ratio), limit +-%.2f; the band is the 10..90 %% of %d seed resamples (fixed fit)' % (RESID_LIMIT, a.boot))
    for p, rb in zip(points, resid_bands):
        flag = ''
        if abs(p['resid']) > RESID_LIMIT:
            flag = ' OUTSIDE'
        elif in_band(RESID_LIMIT, rb) or in_band(-RESID_LIMIT, rb):
            flag = ' boundary'
        P('  %-12s %-34s %-5s n=%2d measured %.3f predicted %.3f resid %+.3f band %+.3f..%+.3f%s' % (p['label'], p['real_kit'], p['primary'], p['n'], p['obs'], p['pred'], p['resid'], rb[0], rb[2], flag))
    m1 = 'trusted' if len(outside) == 0 else ('not trusted' if len(outside) >= 3 else 'partly: %d point(s) outside' % len(outside))
    P('M1: %d of %d points outside +-%.2f -> %s' % (len(outside), len(points), RESID_LIMIT, m1))

    # refit on resampled seeds (for the band of the curve predictions)
    refits = []
    curves = []
    for c in a.curve:
        k, s = c.split(',')
        curves.append((float(k), float(s)))
    kit_names = [k for k in a.curve_kits.split(',') if k]
    curve_rows = {}
    if curves:
        for bi in range(a.boot):
            tmp = [dict(p, obs=boots_obs[bi][i]) for i, p in enumerate(points)]
            refits.append(fit(tmp, 0.1))
    results = []
    for (k, s) in curves:
        preds, bands, cuts = {}, {}, {}
        for kn in kit_names:
            for pr in PRIMS:
                real = kn.replace('@', pr)
                row = reads_rows.get((real, pr))
                if row is None:
                    raise SystemExit('fit_guardian_time: no reads row for %s / %s (curve kit)' % (real, pr))
                d, r, sh = factors(row['totals'], pr, block, (k, s))
                preds[(kn, pr)] = predict(model, d, r, sh, pr)
                bands[(kn, pr)] = band([predict(rf, d, r, sh, pr) for rf in refits])
                dsum = float(row['totals'].get('damage_bps', 0))
                cuts[(kn, pr)] = (dsum, dsum if dsum <= k else k + (dsum - k) * s)
        ev = m2_eval(preds, bands)
        results.append({'K': k, 's': s, 'preds': {'%s|%s' % kk: v for kk, v in preds.items()}, 'bands': {'%s|%s' % kk: list(v) for kk, v in bands.items()},
                        'damage_bps': {'%s|%s' % kk: list(v) for kk, v in cuts.items()}, 'm2': ev})
        P('CURVE K=%d s=%.2f  M2 %s (ember>=0.50 %d/3, frost<=0.70 %d/3, arc<=0.70 %d/3, all in 0.40..0.80 %s)' % (k, s, 'PASS' if ev['pass'] else 'fail', ev['ember_ge_050'], ev['frost_le_070'], ev['arc_le_070'], ev['all_in_040_080']))
        for kn in kit_names:
            P('   %-26s ' % kn + '  '.join('%s %.3f (%.3f..%.3f, D %d->%d)' % (pr, preds[(kn, pr)], bands[(kn, pr)][0], bands[(kn, pr)][2], cuts[(kn, pr)][0], cuts[(kn, pr)][1]) for pr in PRIMS))
        for note in ev['boundary_notes']:
            P('   boundary: ' + note)
    chosen = None
    passing = [r for r in results if r['m2']['pass']]
    if curves:
        if passing:
            chosen = max(passing, key=lambda r: (r['K'], r['s']))
            P('CHOSEN K=%d s=%.2f (passing, largest K then largest s)' % (chosen['K'], chosen['s']))
        else:
            P('CHOSEN none: no candidate passes M2')
    if a.out:
        out_path = Path(a.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        pts = [{k: v for k, v in p.items() if k not in ('seed_ratios', 'totals')} for p in points]
        for p, rb in zip(pts, resid_bands):
            p['resid_band'] = list(rb)
        out_path.write_text(json.dumps({'note': 'model answer fitted to bot runs; fun is unevaluated', 'beta': model['beta'], 'gamma': model['gamma'], 'sse': model['sse'], 'f': model['f'], 'fixed': fixed,
                                        'points': pts, 'm1': {'outside': len(outside), 'verdict': m1}, 'curves': results, 'chosen': ({'K': chosen['K'], 's': chosen['s']} if chosen else None),
                                        'boot': a.boot, 'seed': a.seed}, indent=1, ensure_ascii=False), encoding='utf-8')
    return 0


if __name__ == '__main__':
    sys.exit(main())
