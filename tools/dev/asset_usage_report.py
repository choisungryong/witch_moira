"""Merge several `hud_dump.gd --asset-usage=` files into one asset usage table (T7-0).

    python tools/dev/asset_usage_report.py --out _local/tools/t7-0/asset-usage \
        frost=_local/t7/usage-frost.json ember=... arc=... menu=...

Each input is one run's probe output (chapter1/tests/asset_usage_probe.gd). A file is
  drawn        some run saw a visible node holding it (sound: a player playing it; font: a visible text node using it)
  loaded only  some run saw it loaded or held by a node, but never visible / playing
  not loaded   no run saw it at all
Written: <out>.json and <out>.md. The ledger (chapter1/art/ASSET-LEDGER.json) is only read.
"""
from pathlib import Path
import argparse, json, re, sys

ROOT = Path(__file__).resolve().parents[2]
LEDGER = ROOT / 'chapter1' / 'art' / 'ASSET-LEDGER.json'
PRESETS = ROOT / 'export_presets.cfg'
SHEETS = ['hero', 'walker', 'ranged', 'charger', 'elite']
ELEVEN = ['actors/%s%s.png' % (n, s) for n in SHEETS for s in ('', '_actions')] + ['actors/battle_mage_walk_4x4_v01.png']
STATUS = {'drawn': '그려짐', 'loaded_only': '로드만 됨', 'not_loaded': '로드 안 됨'}


def file_status(row):
    if row.get('visible') or row.get('played'):
        return 'drawn'
    if row.get('cached_ever') or row.get('attached'):
        return 'loaded_only'
    return 'not_loaded'


def export_filters():
    """[(preset name, export_filter, [exclude patterns])] from export_presets.cfg."""
    out, name, ef, ex = [], None, '', []
    if not PRESETS.is_file():
        return out
    for line in PRESETS.read_text(encoding='utf-8').splitlines():
        if re.match(r'^\[preset\.\d+\]$', line):
            if name is not None:
                out.append((name, ef, ex))
            name, ef, ex = None, '', []
        m = re.match(r'^name="(.*)"$', line)
        if m and name is None:
            name = m.group(1)
        m = re.match(r'^export_filter="(.*)"$', line)
        if m:
            ef = m.group(1)
        m = re.match(r'^exclude_filter="(.*)"$', line)
        if m:
            ex = [p.strip() for p in m.group(1).split(',') if p.strip()]
    if name is not None:
        out.append((name, ef, ex))
    return out


def glob_match(pattern, path):
    regex = '^' + re.escape(pattern).replace(r'\*\*', '.*').replace(r'\*', '.*') + '$'
    return re.match(regex, path) is not None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', required=True, help='output path without extension (under _local/)')
    parser.add_argument('inputs', nargs='+', help='name=probe.json')
    args = parser.parse_args()
    runs = {}
    for item in args.inputs:
        name, _, path = item.partition('=')
        runs[name] = json.loads(Path(path).read_text(encoding='utf-8'))
    ledger = json.loads(LEDGER.read_text(encoding='utf-8'))
    ledger_paths = {('chapter1/art/' + a['path']): a for a in ledger['assets']}
    presets = export_filters()

    all_files = sorted({f for r in runs.values() for f in r['files']})
    rows = []
    for f in all_files:
        per_run = {n: file_status(r['files'][f]) if f in r['files'] else 'not_loaded' for n, r in runs.items()}
        order = ['drawn', 'loaded_only', 'not_loaded']
        best = min(per_run.values(), key=order.index)
        details = {}
        for n, r in runs.items():
            row = r['files'].get(f, {})
            d = {}
            for key in ('visible_kinds', 'attached_kinds', 'first_visible_tick', 'first_visible_mode', 'max_visible_nodes', 'played_info', 'first_cached_tick'):
                if key in row:
                    d[key] = row[key]
            if row.get('identified_by_content'):
                d['identified_by_content'] = True
            if row.get('cached_ever'):
                d['cached_ever'] = True
            if d:
                details[n] = d
        rel = f
        in_ledger = rel in ledger_paths
        led = ledger_paths.get(rel, {})
        excluded_by = [p for (pn, ef, ex) in presets for p in ex if glob_match(p, rel)]
        rows.append({'path': rel, 'status': best, 'status_ko': STATUS[best], 'per_run': per_run, 'in_ledger': in_ledger,
                     'ledger_source_type': led.get('source_type'), 'details': details,
                     'in_export_all_presets': not excluded_by, 'export_excluded_by': sorted(set(excluded_by))})

    ledger_rows = [r for r in rows if r['in_ledger']]
    outside = [r for r in rows if not r['in_ledger']]
    missing_from_probe = sorted(set(ledger_paths) - set(all_files))
    counts = {k: sum(1 for r in ledger_rows if r['status'] == k) for k in STATUS}
    counts_all = {k: sum(1 for r in rows if r['status'] == k) for k in STATUS}
    sprite = {n: r.get('sprite3d', {}) for n, r in runs.items()}
    unidentified = {n: r.get('unidentified_visible_textures', {}) for n, r in runs.items()}
    raw = {n: r.get('raw_fallbacks', {}) for n, r in runs.items()}
    eleven = [r for r in rows if r['path'].replace('chapter1/art/', '') in ELEVEN]
    document = {'runs': {n: r['meta'] for n, r in runs.items()}, 'counts_ledger_104': counts, 'counts_all_probed_files': counts_all,
                'ledger_entries': len(ledger_paths), 'files_not_probed_but_in_ledger': missing_from_probe,
                'files_outside_ledger': [r['path'] for r in outside], 'sheets_eleven': eleven,
                'sprite3d': sprite, 'unidentified_visible_textures': unidentified, 'raw_fallbacks': raw,
                'export_presets': [{'name': n, 'export_filter': ef, 'exclude_filter': ex} for n, ef, ex in presets], 'files': rows,
                'limits': next(iter(runs.values())).get('limits', [])}
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.with_suffix('.json').write_text(json.dumps(document, ensure_ascii=False, indent=1), encoding='utf-8', newline='\n')

    lines = ['# 에셋 사용 표 (T7-0)', '', '실행: ' + ', '.join('%s(주력 %s, 시드 %s, 끝 틱 %s, 모드 %s)' % (n, m.get('primary'), m.get('seed'), m.get('final_tick'), m.get('mode')) for n, m in document['runs'].items()), '',
             '## 합계', '', '| | 그려짐(소리는 재생됨) | 로드만 됨 | 로드 안 됨 | 합 |', '|---|---|---|---|---|',
             '| 원장 104항목 | %d | %d | %d | %d |' % (counts['drawn'], counts['loaded_only'], counts['not_loaded'], len(ledger_rows)),
             '| 원장 밖 | %d | %d | %d | %d |' % tuple([sum(1 for r in outside if r['status'] == k) for k in STATUS] + [len(outside)]), '']
    if missing_from_probe:
        lines += ['원장에는 있고 디스크 훑기에는 없는 파일: ' + ', '.join(missing_from_probe), '']
    for key in ('not_loaded', 'loaded_only', 'drawn'):
        lines += ['## %s' % STATUS[key], '', '| 파일 | 실행별 | 원장 출처 유형 | 내보내기 |', '|---|---|---|---|']
        for r in rows:
            if r['status'] != key:
                continue
            per = ' '.join('%s:%s' % (n, {'drawn': 'O', 'loaded_only': 'L', 'not_loaded': '-'}[s]) for n, s in r['per_run'].items())
            lines.append('| %s | %s | %s | %s |' % (r['path'].replace('chapter1/', ''), per, r['ledger_source_type'] or ('원장 밖' if not r['in_ledger'] else ''), '포함' if r['in_export_all_presets'] else '제외(' + ', '.join(r['export_excluded_by']) + ')'))
        lines.append('')
    lines += ['## 출처 미확인 2D 시트 11개', '', '| 파일 | 판정 | 비고 |', '|---|---|---|']
    for r in eleven:
        note = ', '.join('%s=%s' % (n, ','.join(d.get('attached_kinds', d.get('visible_kinds', [])))) for n, d in r['details'].items()) or ''
        lines.append('| %s | %s | %s |' % (r['path'].replace('chapter1/art/', ''), r['status_ko'], note))
    lines += ['', '## 화면의 Sprite3D / AnimatedSprite3D', '']
    for n, rep in sprite.items():
        for label, s in rep.items():
            lines.append('- %s %s(틱 %s): 보이는 %s개, 숨은 %s개, 텍스처별 %s' % (n, label, s.get('tick'), s.get('visible_sprites'), s.get('hidden_sprites'), s.get('by_texture')))
    lines += ['', '## 파일 경로 없는 보이는 텍스처(개수는 표본 합)', '']
    for n, u in unidentified.items():
        lines.append('- %s: %s' % (n, u))
    lines += ['', '## 원시 PNG 대체 로드(raw_texture_fallbacks)', '']
    for n, u in raw.items():
        lines.append('- %s: actors=%s audio=%s world=%s' % (n, u.get('actors'), u.get('audio'), (u.get('world') or {}).get('raw_texture_fallbacks')))
    lines += ['', '## 한계', ''] + ['- ' + x for x in document['limits']]
    out.with_suffix('.md').write_text('\n'.join(lines) + '\n', encoding='utf-8', newline='\n')
    print('ASSET_USAGE_REPORT', json.dumps({'ledger': counts, 'all': counts_all, 'json': str(out.with_suffix('.json')), 'md': str(out.with_suffix('.md'))}, ensure_ascii=False))


if __name__ == '__main__':
    sys.exit(main())
