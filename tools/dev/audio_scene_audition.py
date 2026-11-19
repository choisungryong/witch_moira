"""Scene audition: lay candidate sounds under captured game footage, one video per candidate, plus an answer key and measurements.

    python tools/dev/audio_scene_audition.py CAPTURE_DIR --requests REQ.json --candidates CANDS.json --out _local/audio/audition/20261119-scene
    python tools/dev/audio_scene_audition.py _local/sfx/ember-a --requests _local/sfx/req_ember.json --candidates cands.json --out OUT --open-labels --no-video

Inputs
  CAPTURE_DIR   frames/f00000.jpg ... and events.json ({"primary", "from": first tick, "frames", "rows": [{"f", "tick", "mode", ...}]}),
                as written by a capture run (one frame per tick at 60 fps). This tool does not capture.
  --requests    the request log of the same run (report_audio_requests.gd: same seed and skill; [tick, cue, ui, playing, source] rows).
                The footage's events.json carries event types, not the game's cue names, so the cue list comes from here; the
                tool checks that the event counts in the window match the request counts and says so when they do not.
  --candidates  JSON: {"title": "...", "level_match": "game" | "none", "questions": ["..."], "baseline": true,
                       "candidates": [{"id": "A", "label": "Candidate A", "files": {"fire": ["a1.wav", "a2.wav", "a3.wav"], "impact": [...]}}]}
                "files" maps a GAME sound name (the cue names of combat_audio.gd COUNTS) to candidate files; paths are relative to the
                JSON file or the repository. A cue not listed keeps the game's own file. Variant v of a cue plays files[v % len(files)].
                "level_match": "game" brings each candidate file to the level (RMS of the part within 30 dB of the peak) of the
                game file it replaces, so GAINS keep their meaning; "none" uses the files as they are.
                The game's own sounds are added as candidate "0" unless "baseline": false.

Playback rules: ONLY audio_mix_offline.py, which reads them from chapter1/presentation/combat_audio.gd (COUNTS, COOLDOWNS, GAINS,
MAX_VOICES, SILENT, pitch, voice reserve). Nothing is copied here. A cue in SILENT makes no sound in any video, candidate or not.

Loudness (--loudness): "common" (default) one gain for all videos, chosen so the loudest video reaches the target LUFS-I
(and no video passes -1 dBTP), so loudness differences between candidates stay as they are in the game; "each" every video to
the target on its own (for comparing timbre alone). Target default -16 LUFS-I, measured on the stereo (dual mono) file.

Output (OUT/)
  send/NN.mp4, send/NN.wav, send/README.ko.txt   what goes to the listener (blind: numbers only, shuffled)
  answers.ko.txt                                  which number is which candidate (do not send)
  measure.json                                    per video: LUFS-I, momentary max, true peak, gain, per-cue played counts
This tool measures and writes. It does not listen.
"""
import argparse, json, math, random, subprocess, sys
from pathlib import Path

import numpy as np
from scipy import signal

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audio_measure as am
import audio_mix_offline as mo
import audio_audition as ad

REPO = Path(__file__).resolve().parents[2]
SR = mo.SR
FPS = 60
# sanity table for the alignment check only (event type in events.json -> cue it normally requests); not a playback rule
EVENT_TO_CUE = {'hit': 'impact', 'explosion': 'explosion', 'death': 'death', 'hero_hit': 'hurt'}
QUESTIONS = [
    '영상마다 소리가 장면(맞는 순간, 터지는 순간)과 맞아 들어갑니까? 어긋나 들리는 번호가 있습니까?',
    '가장 마음에 드는 번호와 가장 거슬리는 번호는 무엇입니까? 이유를 한 줄로.',
    '군중이 몰릴 때 피곤하거나 시끄럽습니까(1~5)? 번호마다.',
    '들리지 않거나 묻히는 소리가 있습니까?',
]


def die(msg, code=2):
    print('ERROR: ' + msg)
    raise SystemExit(code)


def resolve(base, p):
    p = Path(p)
    if p.is_absolute():
        return p
    for root in (base, REPO):
        if (root / p).exists():
            return root / p
    return base / p


def load_mono48(path):
    x, sr, _ = am.read_wav(path)
    x = x.mean(axis=1)
    return signal.resample_poly(x, SR, sr) if sr != SR else x


def level(x):
    """RMS of the part of the sound within 30 dB of its peak."""
    a = np.abs(x)
    part = x[a > a.max() * 10 ** (-30 / 20)]
    return float(np.sqrt(np.mean(part ** 2)))


def load_capture(folder):
    folder = Path(folder)
    ev = folder / 'events.json'
    if not ev.is_file() or not (folder / 'frames').is_dir():
        die('%s needs events.json and frames/' % folder)
    data = json.loads(ev.read_text(encoding='utf-8'))
    rows = data['rows']
    ticks = [r['tick'] for r in rows]
    if any(b - a != 1 for a, b in zip(ticks, ticks[1:])):
        die('events.json ticks are not one per frame; the audio would not line up with the picture')
    names = sorted((folder / 'frames').glob('f*.jpg'))
    if len(names) < len(rows):
        die('%d frames but %d rows' % (len(names), len(rows)))
    return {'folder': folder, 'rows': rows, 'from': int(data['from']), 'primary': data.get('primary'), 'frames': len(rows)}


def alignment_report(cap, log):
    t0, n = cap['from'], cap['frames']
    ev, rq = {}, {}
    for r in cap['rows']:
        for e in r['events']:
            ev[e['type']] = ev.get(e['type'], 0) + 1
    for q in log['requests']:
        if t0 <= int(q[0]) < t0 + n:
            rq[q[1]] = rq.get(q[1], 0) + 1
    notes, ok = [], True
    if cap['primary'] and log.get('primary') and cap['primary'] != log['primary']:
        notes.append('skill differs: footage %s, request log %s' % (cap['primary'], log['primary']))
        ok = False
    for etype, cue in EVENT_TO_CUE.items():
        if ev.get(etype, 0) != rq.get(cue, 0):
            notes.append('%s events %d vs %s requests %d in the window' % (etype, ev.get(etype, 0), cue, rq.get(cue, 0)))
            ok = False
    return ok, notes, {'events': ev, 'requests': rq}


def build_sources(base, rules, cand, level_match, cand_dir):
    """Game sources with the candidate's files in the listed cues. Returns (src, notes)."""
    src = dict(base)
    notes = {'level_match': level_match, 'cues': {}, 'warnings': []}
    for cue, files in (cand.get('files') or {}).items():
        if cue != 'ambience' and cue not in rules['counts']:
            die('candidate %s: "%s" is not a game sound name (%s)' % (cand['id'], cue, ', '.join(rules['counts'])))
        if not files:
            die('candidate %s: no files for %s' % (cand['id'], cue))
        if cue in rules['silent']:
            notes['warnings'].append('%s is SILENT in the game: its files are not played' % cue)
        count = 1 if cue == 'ambience' else rules['counts'][cue]
        if len(files) < count:
            notes['warnings'].append('%s: %d files for %d variants; files repeat' % (cue, len(files), count))
        out, info = [], []
        for v in range(count):
            p = resolve(cand_dir, files[v % len(files)])
            if not p.is_file():
                die('candidate %s: %s not found' % (cand['id'], p))
            x = load_mono48(p)
            gain = 1.0
            if level_match == 'game':
                gain = level(base[cue][v]) / level(x)
                x = x * gain
            out.append(x)
            info.append({'variant': v, 'file': p.name, 'gain_db': round(20 * math.log10(gain), 1)})
        src[cue] = out
        notes['cues'][cue] = info
    return src, notes


def drawtext_arg(label):
    font = Path('C:/Windows/Fonts/malgunbd.ttf')
    text = label.replace('\\', '\\\\').replace("'", "\\'").replace(':', '\\:').replace('%', '\\%')
    f = "drawtext=text='%s':fontsize=64:fontcolor=white:borderw=4:x=40:y=h-180" % text
    if font.is_file():
        f += ":fontfile='C\\:/Windows/Fonts/malgunbd.ttf'"
    return f


def make_video(cap, wav, label, out):
    cmd = ['ffmpeg', '-y', '-loglevel', 'error', '-framerate', str(FPS), '-start_number', '0', '-i', str(cap['folder'] / 'frames/f%05d.jpg'),
           '-i', str(wav), '-frames:v', str(cap['frames']), '-vf', 'scale=1280:720,' + drawtext_arg(label), '-c:v', 'libx264', '-crf', '20',
           '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k', '-shortest', str(out)]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode:
        die('ffmpeg failed for %s: %s' % (out, p.stderr[:400]), 3)


def gain_for(lufs, tp, target):
    return min(target - lufs, -1.0 - tp)


def main():
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('capture')
    ap.add_argument('--requests', required=True, help='request log JSON of the same run')
    ap.add_argument('--candidates', required=True)
    ap.add_argument('--out', required=True, help='output folder (under _local/)')
    ap.add_argument('--loudness', choices=['common', 'each'], default='common')
    ap.add_argument('--target-lufs', type=float, default=-16.0)
    ap.add_argument('--open-labels', action='store_true', help='show candidate ids in the video (default: blind numbers, shuffled)')
    ap.add_argument('--seed', type=int, default=20261119, help='blind order')
    ap.add_argument('--no-video', action='store_true', help='write the wav files and measurements only')
    ap.add_argument('--audio-dir', default=str(am.DEFAULT_DIR))
    ap.add_argument('--player', default=str(am.PLAYER), help='combat_audio.gd to read the rules from (default: the product file)')
    args = ap.parse_args()

    out = Path(args.out)
    out = out if out.is_absolute() else REPO / out
    if '_local' not in out.parts:
        die('--out must be under _local/')
    cap = load_capture(resolve(REPO, args.capture))
    log = mo.load_log(resolve(REPO, args.requests))
    cpath = resolve(REPO, args.candidates)
    spec = json.loads(cpath.read_text(encoding='utf-8'))
    cands = list(spec.get('candidates') or [])
    if not cands:
        die('no candidates in %s' % cpath)
    if spec.get('baseline', True):
        cands.insert(0, {'id': '0', 'label': '지금 게임 소리', 'files': {}})
    ids = [c['id'] for c in cands]
    if len(set(ids)) != len(ids):
        die('candidate ids repeat: %s' % ids)
    level_match = spec.get('level_match', 'game')

    ok, align_notes, align = alignment_report(cap, log)
    print('alignment (footage events vs request log): %s' % ('matches' if ok else 'DIFFERS'))
    for n in align_notes:
        print('  ' + n)

    rules = mo.parse_rules(args.player)
    base = mo.load_sources(rules, args.audio_dir)
    t0 = cap['from'] / FPS
    seconds = cap['frames'] / FPS
    print('rules from combat_audio.gd: SILENT=%s MAX_VOICES=%d window %.2f s from %.2f s' % (rules['silent'], rules['max_voices'], seconds, t0))

    mixes = []
    for c in cands:
        src, notes = build_sources(base, rules, c, level_match, cpath.parent)
        played, stats = mo.simulate(log['requests'], rules, src)
        x = mo.render(played, rules, src, t0, seconds, ambience=True)
        y = np.stack([x, x], axis=1)
        lufs, mmax = am.loudness(y, SR)
        if lufs is None:
            die('candidate %s renders silence' % c['id'])
        in_window = {}
        for e in played:
            if t0 <= e['t'] < t0 + seconds:
                in_window[e['cue']] = in_window.get(e['cue'], 0) + 1
        mixes.append({'cand': c, 'y': y, 'lufs': lufs, 'tp': am.true_peak_db(y), 'played_in_window': in_window, 'stats': stats, 'notes': notes})
        print('  %-3s raw %.1f LUFS-I, %.1f dBTP, played in window %s' % (c['id'], lufs, mixes[-1]['tp'], in_window))

    if args.loudness == 'common':
        g_common = min(min(args.target_lufs - m['lufs'] for m in mixes), min(-1.0 - m['tp'] for m in mixes))
    for m in mixes:
        m['gain_db'] = g_common if args.loudness == 'common' else gain_for(m['lufs'], m['tp'], args.target_lufs)

    order = list(ids)
    if not args.open_labels:
        ad.blind_order(order, random.Random(args.seed))
    (out / 'send').mkdir(parents=True, exist_ok=True)
    by_id = {m['cand']['id']: m for m in mixes}
    report, answers = [], []
    for i, cid in enumerate(order, 1):
        m = by_id[cid]
        y = m['y'] * 10 ** (m['gain_db'] / 20)
        name = '%02d' % i if not args.open_labels else 'cand_%s' % cid
        wav = out / 'send' / (name + '.wav')
        clipped = am.write_wav(wav, y, SR)
        lufs, mmax = am.loudness(y, SR)
        row = {'file': name, 'id': cid, 'label': m['cand'].get('label', cid), 'gain_db': round(m['gain_db'], 2), 'lufs_i': round(lufs, 1), 'm_max': round(mmax, 1),
               'true_peak_dbtp': round(am.true_peak_db(y), 2), 'peak_dbfs': round(am.db(float(np.abs(y).max())), 2), 'clipped': clipped,
               'played_in_window': m['played_in_window'], 'rule_stats_whole_run': m['stats'], 'candidate_files': m['notes']}
        report.append(row)
        answers.append('%s = %s (%s)' % (name, cid, row['label']))
        if not args.no_video:
            make_video(cap, wav, cid if args.open_labels else str(i), out / 'send' / (name + '.mp4'))
        print('%s  id=%s  gain %.1f dB  %.1f LUFS-I  %.1f dBTP  clipped %d' % (name, cid, row['gain_db'], row['lufs_i'], row['true_peak_dbtp'], clipped))

    qs = list(QUESTIONS) + list(spec.get('questions') or [])
    readme = ['장면 소리 비교 (%s)' % spec.get('title', ''), '',
              '이 묶음은 소리를 들을 수 없는 에이전트가 기계로 만들었습니다. 크기는 측정값으로 맞췄지만 들어 보고 확인한 것이 아닙니다.',
              '같은 장면(%.1f초)에 소리만 다른 영상 %d개입니다. 번호는 섞여 있고, 정답표는 따로 있습니다. 모두 듣고 답한 뒤에 정답표를 보세요.' % (seconds, len(order)),
              '크기: %s.' % ('모든 영상에 같은 이득을 줘서 영상끼리의 크고 작음이 게임과 같습니다' if args.loudness == 'common' else '영상마다 같은 크기(%.0f LUFS)로 맞췄습니다' % args.target_lufs),
              '들은 기기(헤드폰 / 스피커 / 휴대폰)와 대략의 음량을 함께 적어 주세요.', '', '[질문]'] + ['%d. %s' % (k, q) for k, q in enumerate(qs, 1)]
    (out / 'send' / 'README.ko.txt').write_text('\n'.join(readme) + '\n', encoding='utf-8')
    key = ['정답표 (듣기 전에 보지 마세요. send/ 폴더에는 들어 있지 않습니다)', ''] + sorted(answers) + ['', '소리 대응 파일과 크기 맞춤(level_match=%s):' % level_match]
    for r in report:
        key.append('%s: %s' % (r['file'], json.dumps(r['candidate_files'], ensure_ascii=False)))
    key += ['', '규칙: chapter1/presentation/combat_audio.gd의 값을 audio_mix_offline.parse_rules로 읽음. SILENT=%s' % rules['silent']]
    if not ok:
        key += ['', '주의: 영상의 이벤트와 요청 기록이 어긋남: ' + '; '.join(align_notes)]
    (out / 'answers.ko.txt').write_text('\n'.join(key) + '\n', encoding='utf-8')
    (out / 'measure.json').write_text(json.dumps({'capture': str(cap['folder']), 'requests': str(args.requests), 'window': {'from_tick': cap['from'], 'frames': cap['frames']},
                                                  'alignment': {'ok': ok, 'notes': align_notes, **align}, 'loudness': args.loudness, 'target_lufs': args.target_lufs,
                                                  'rules': {k: rules[k] for k in ('max_voices', 'silent', 'cooldowns', 'gains', 'counts')}, 'videos': report},
                                                 ensure_ascii=False, indent=1), encoding='utf-8')
    print('wrote %s (send/, answers.ko.txt, measure.json)' % out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
