"""Audition-bundle tool: level matching, blind files with a separate answer key, concatenation, m4a, zip, the P1 bundle.

    python tools/dev/audio_audition.py p1 --out C:/.../_local/audio/audition/20261117-P1 --requests _local/audio/requests
    python tools/dev/audio_audition.py concat --gap 0.5 --match mmax:-23 -o out.wav a.wav b.wav ...   # same-loudness comparison file
    python tools/dev/audio_audition.py pink -o 00_level.wav                                         # 10 s pink noise, -23 LUFS-I
    python tools/dev/audio_audition.py m4a FOLDER                                                  # every wav -> m4a (ffmpeg, AAC 160k)

Level conventions (S1 6.2, 9.2): "mmax" = loudest 400 ms block (BS.1770 K-weighted, as audio_measure.py), used for short
sound effects; "lufs" = integrated, used for long sounds. "game" level = the file as the player plays it (master 0.8 *
0.11 * gain); the bundle lifts every game-level file by the same +15 dB so that the relative levels stay and they are
within reach of a listening level. The tool measures and writes; it does not listen.
"""
import argparse, json, random, shutil, subprocess, sys, zipfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audio_measure as am
import audio_mix_offline as mix

SR = 48000
REPO = Path(__file__).resolve().parents[2]
BLIND_POOL = ['fire_0', 'fire_1', 'fire_2', 'cold_0', 'cold_1', 'lightning_0']
BLIND_REPEATS = ['fire_1', 'cold_0', 'lightning_0']          # three of the six are heard twice
FAMILY = {'fire': '화염', 'cold': '냉기', 'lightning': '번개'}
GAME_BOOST_DB = 15.0


# ---- basic operations -------------------------------------------------------------------------------------

def mono(path):
    return am.read_wav(path)[0].mean(axis=1)


def level(x, kind):
    """Measured level of a mono signal: 'mmax' or 'lufs'."""
    i, m = am.loudness(x[:, None], SR)
    return m if kind == 'mmax' or i is None else i


PEAK_CAP_DBTP = -1.0
CAPPED = []   # (what, wanted level, level after the cap) for sounds whose true peak limited the match


def match(x, kind, target, what=''):
    """Scale to the target level; if that would pass PEAK_CAP_DBTP the sound is held at the cap and recorded in CAPPED."""
    g = target - level(x, kind)
    over = am.true_peak_db((x * 10 ** (g / 20))[:, None]) - PEAK_CAP_DBTP
    if over > 0:
        CAPPED.append((what, target, round(target - over, 1)))
        g -= over
    return x * 10 ** (g / 20)


def silence(seconds):
    return np.zeros(int(round(seconds * SR)))


def concat(parts, gap=0.5, head=0.0, tail=0.0):
    out = [silence(head)]
    for i, p in enumerate(parts):
        out.append(p)
        if i < len(parts) - 1:
            out.append(silence(gap))
    out.append(silence(tail))
    return np.concatenate(out)


def fade_edges(x, ms=20):
    n = int(ms / 1000 * SR)
    x = x.copy()
    ramp = np.linspace(0, 1, n)
    x[:n] *= ramp
    x[-n:] *= ramp[::-1]
    return x


def pink_noise(seconds=10.0, lufs=-23.0, seed=1117):
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    spec[1:] /= np.sqrt(np.maximum(f[1:], 20.0))
    spec[f < 20] = 0
    x = fade_edges(np.fft.irfft(spec, n), 50)
    return match(x, 'lufs', lufs)


def to_m4a(wav, bitrate='160k'):
    out = Path(wav).with_suffix('.m4a')
    p = subprocess.run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-i', str(wav), '-c:a', 'aac', '-b:a', bitrate, '-movflags', '+faststart', str(out)],
                       capture_output=True, text=True)
    if p.returncode:
        raise SystemExit('ffmpeg failed for %s: %s' % (wav, p.stderr[:300]))
    return out


def write(path, x, notes):
    clipped = am.write_wav(path, x, SR)
    if clipped:
        raise SystemExit('%s would clip (%d samples)' % (path, clipped))
    i, m = am.loudness(x[:, None], SR)
    notes.append({'file': Path(path).name, 'seconds': round(len(x) / SR, 2), 'peak_dbfs': round(am.db(float(np.abs(x).max())), 2),
                  'true_peak_dbtp': round(am.true_peak_db(x[:, None]), 2), 'm_max': round(m, 1), 'lufs_i': None if i is None else round(i, 1)})


def headroom_gain(x, want_db, limit_dbtp=-1.0):
    """Largest gain <= want_db that keeps the true peak at or under limit_dbtp."""
    tp = am.true_peak_db(x[:, None])
    return min(want_db, limit_dbtp - tp)


# ---- P1 ---------------------------------------------------------------------------------------------------

QUESTIONS = [
    '01~09: 각 소리가 화염·냉기·번개 가운데 무엇 같습니까? 번호마다 "화염 / 냉기 / 번개 / 모름".',
    '세 계열을 가르는 데 무엇이 가장 도움이 됐습니까(높낮이, 시작의 날카로움, 꼬리의 길이 등)? 헷갈린 짝은 어느 것입니까?',
    '24 same_all: 듣기 싫거나 귀가 아픈 소리가 있습니까? 번호나 순서로 적어 주세요.',
    '너무 길거나 뒤가 끌리는 소리가 있습니까?',
    '화염 시전 셋(10 same_fire 안의 세 소리)이 같은 기술로 들립니까, 다른 기술로 들립니까?',
    '25~28 game_*: 게임 안 크기로 들었을 때, 들리지 않거나 거의 들리지 않는 소리는 무엇입니까?',
    '명중·처치·피격 가운데 피격(주인공이 맞음)을 따로 알아챌 수 있습니까?',
    '득템 소리(drop, jewel, legend, pickup)에서 "좋은 것이 떨어졌다"는 느낌이 legend에서만 납니까? jewel은 반지·목걸이로 연상됩니까?',
    '29 amb_loop_x8: 4초마다 반복되는 것이나 끊김이 들립니까? 몇 초쯤에서입니까?',
    '환경음이 수도원 폐허에 어울리는 바탕으로 들립니까, 기계 소리로 들립니까?',
    '30~33 crowd_*: 10초를 듣고 피곤하거나 시끄럽습니까(1~5)? 너무 빈약합니까(1~5)? (ember와 arc를 따로)',
    'crowd_* 안에서 무엇이 가장 잘 들리고 무엇이 묻힙니까?',
    '34~37 hurt_in_crowd: 피격 3번을 셀 수 있었습니까? (피격만 따로 든 파일과 비교해서)',
    '지금 소리 가운데 그대로 두고 싶은 것이 있습니까?',
]

README = """P1 — 지금 들어 있는 소리 듣기 (2026-11-17)

이 묶음은 소리를 들을 수 없는 에이전트가 기계로 만들었습니다. 크기는 측정값으로 맞췄지만
들어 보고 확인한 것이 아닙니다. 어색한 소리나 이상한 파일이 있으면 그대로 알려 주세요.

[듣는 법]
1. 되도록 같은 기기로 처음부터 끝까지 듣습니다. 다른 기기(헤드폰, 노트북 스피커, 휴대폰, 이어폰)로
   한 번 더 들어 주시면 더 좋습니다. 휴대폰에서는 .m4a를 쓰시면 됩니다(내용은 같습니다).
2. 먼저 00_level 을 틀어, 시끄럽지도 작지도 않은 편한 크기로 맞춥니다.
   그 뒤로는 끝까지 음량을 바꾸지 말아 주세요. (소리가 안 들리면 안 들린다고 적어 주세요. 그것도 답입니다.)
3. 번호 순서대로 듣습니다. 01~09는 이름을 가렸습니다. 먼저 이 아홉 개를 듣고 질문 1에 답한 뒤에
   나머지를 듣고, 정답은 마지막에(answers.ko.txt) 확인해 주세요. 정답을 알면 다른 질문이 달라질 수 있습니다.
4. 답에는 꼭 적어 주세요: 들은 기기(헤드폰 / 노트북 스피커 / 휴대폰 스피커 / 이어폰), 대략의 음량.
   답은 숫자(1~5)나 짧은 글이면 됩니다. 모르면 "모름".

[파일]
00_level            기준음(분홍 소음 10초). 음량 맞추기용.
01~09 blind         이름을 가린 소리 9개. 같은 크기로 맞췄습니다. 같은 소리가 두 번 나오는 것이 있습니다.
10~23 same_이름      지금 게임에 있는 소리를 이름별로 하나씩. 같은 크기로 맞췄습니다
                    (줍기 소리만 소리가 터지지 않게 1dB쯤 작게 두었습니다).
                    (변주가 여럿인 소리는 한 파일 안에 차례로 들어 있습니다.)
24 same_all         위 소리 전부를 1초 간격으로 이어 붙인 파일.
25~28 game_*        게임 안에서의 크기 차이를 그대로 둔 파일들(시전 / 명중·처치·피격·폭발 / 득템 / 발걸음).
                    모든 파일을 같은 만큼(+15dB) 키웠으므로 소리끼리의 크고 작음은 게임과 같습니다.
                    작게 들리거나 안 들리는 소리가 있어도 정상입니다. 그 소리가 무엇인지 적어 주세요.
29 amb_loop_x8      환경음 4초를 8번 이어 32초.
30~33 crowd_*       한 판을 기록해 지금 규칙대로 섞은 전투 10초(화염 판, 번개 판). plus15 는 게임보다 15dB
                    키운 것, game 은 게임 크기 그대로입니다(작습니다).
34~37 hurt_*        같은 화염 10초 안에 주인공이 맞는 소리 3번을 넣은 것과, 그 3번만 따로 든 것.
measure.md          측정표. 읽지 않으셔도 됩니다.

[질문]
{questions}
"""


def blind_order(items, rng):
    """Shuffle in place (rng is a random.Random) until no two neighbours are the same item. Returns the list.
    Shared by the P1 bundle and audio_scene_audition.py, so the blind order is made one way."""
    while True:
        rng.shuffle(items)
        if all(a != b for a, b in zip(items, items[1:])):
            return items


def build_blind(src_dir, out_dir, notes, rng):
    order = blind_order(BLIND_POOL + BLIND_REPEATS, rng)
    answers = []
    for i, name in enumerate(order, 1):
        x = match(mono(src_dir / (name + '.wav')), 'mmax', -23.0, name)
        fname = '%02d_blind.wav' % i
        write(out_dir / fname, concat([x], head=0.3, tail=0.7), notes)
        answers.append((fname, name))
    return answers


def build_p1(args):
    src_dir = Path(args.audio_dir)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    notes, rng = [], random.Random(20261117)
    rules = mix.parse_rules()
    gains = am.load_gains()
    cues = list(gains)  # S1 order: fire cold lightning impact death explosion hurt drop pickup equip step jewel legend
    variants = {c: ['%s_%d' % (c, i) for i in range(rules['counts'][c])] for c in cues}
    write(out / '00_level.wav', pink_noise(10.0, -23.0), notes)
    answers = build_blind(src_dir, out, notes, rng)
    n = 10
    same_names, all_parts = [], []
    for cue in cues + ['ambience']:
        if cue == 'ambience':
            parts = [match(mono(src_dir / 'ambience.wav'), 'lufs', -23.0, 'ambience')]
        else:
            parts = [match(mono(src_dir / (v + '.wav')), 'mmax', -23.0, v) for v in variants[cue]]
        write(out / ('%02d_same_%s.wav' % (n, cue)), concat(parts, gap=0.6, head=0.3, tail=0.5), notes)
        same_names.append('%02d_same_%s' % (n, cue))
        all_parts += parts
        n += 1
    write(out / '24_same_all.wav', concat(all_parts, gap=1.0, head=0.3, tail=0.5), notes)

    def game(cue_variant):
        cue = cue_variant.rsplit('_', 1)[0]
        return mono(src_dir / (cue_variant + '.wav')) * rules['master'] * rules['one_shot_gain'] * gains[cue] * 10 ** (GAME_BOOST_DB / 20)
    groups = {
        '25_game_cast': variants['fire'] + variants['cold'] + variants['lightning'],
        '26_game_hit': variants['impact'] + variants['death'] + variants['hurt'] + variants['explosion'],
        '27_game_loot': variants['drop'] + variants['jewel'] + variants['legend'] + variants['pickup'] + variants['equip'],
        '28_game_step': (variants['step'] * 4),
    }
    for name, vs in groups.items():
        write(out / (name + '.wav'), concat([game(v) for v in vs], gap=0.35 if 'step' in name else 0.8, head=0.3, tail=0.5), notes)
    amb = mono(src_dir / 'ambience.wav')
    write(out / '29_amb_loop_x8.wav', match(np.tile(amb, 8), 'lufs', -23.0, 'ambience x8'), notes)

    # crowd mixes from recorded runs
    req_dir = Path(args.requests)
    crowd_info = {}
    for tag, num in (('ember', 30), ('arc', 32)):
        log = mix.load_log(req_dir / ('req_%s.json' % tag))
        src = mix.load_sources(rules, src_dir)
        played, stats = mix.simulate(log['requests'], rules, src)
        t0, nreq = mix.best_window(log['requests'], log['ticks'], 10)
        x = mix.render(played, rules, src, float(t0), 10.0)
        boost = headroom_gain(x, GAME_BOOST_DB)
        write(out / ('%d_crowd_%s_10s_plus15.wav' % (num, tag)), x * 10 ** (boost / 20), notes)
        write(out / ('%d_crowd_%s_10s_game.wav' % (num + 1, tag)), x, notes)
        in_window = [p for p in played if t0 <= p['t'] < t0 + 10]
        hurts = [r for r in log['requests'] if t0 * 60 <= r[0] < (t0 + 10) * 60 and r[1] == 'hurt']
        crowd_info[tag] = {'start_s': t0, 'window_requests': nreq, 'played_in_window': len(in_window), 'boost_db': round(boost, 1), 'natural_hurt_requests': len(hurts),
                           'rendered_mix': mix.describe(x), 'total_requests': len(log['requests']), 'run_seconds': round(log['seconds'], 1)}
        if tag == 'ember':
            # three player hits at 2.0 / 5.0 / 8.0 s inside the same window; natural hits removed so that exactly three remain
            ticks = [int(t0 * 60 + s * 60) for s in (2, 5, 8)]
            kept = [r for r in log['requests'] if not (r[1] == 'hurt' and t0 * 60 - 120 <= r[0] < (t0 + 10) * 60 + 120)]
            injected = kept + [[t, 'hurt', 0, 1, 'injected'] for t in ticks]
            p2, _ = mix.simulate(injected, rules, src)
            y = mix.render(p2, rules, src, float(t0), 10.0)
            only = mix.render([p for p in p2 if p['cue'] == 'hurt'], rules, src, float(t0), 10.0, ambience=False)
            b2 = headroom_gain(y, GAME_BOOST_DB)
            b2 = min(b2, boost) if boost < GAME_BOOST_DB else b2
            write(out / '34_hurt_in_crowd_plus15.wav', y * 10 ** (b2 / 20), notes)
            write(out / '35_hurt_in_crowd_game.wav', y, notes)
            write(out / '36_hurt_only_plus15.wav', only * 10 ** (b2 / 20), notes)
            write(out / '37_hurt_only_game.wav', only, notes)
            crowd_info['hurt'] = {'ticks': ticks, 'boost_db': round(b2, 1), 'natural_hurts_removed': len(hurts),
                                  'hurt_played': sum(1 for p in p2 if p['cue'] == 'hurt' and t0 <= p['t'] < t0 + 10)}

    # measurement sheet
    src_rows = am.s1_order([am.measure(p, gains) for p in sorted(src_dir.glob('*.wav'))])
    lines = ['# P1 측정표', '', '## 지금 음원 22개 (audio_measure.py)', '', am.s1_table(src_rows), '', '## 이 묶음의 파일 (같은 방식으로 잼)', '',
             '| 파일 | 길이 s | 최대 dBFS | 참 최대 dBTP | M최대 LUFS | 통합 LUFS |', '|---|---|---|---|---|---|']
    for r in notes:
        lines.append('| %s | %.2f | %.2f | %.2f | %.1f | %s |' % (r['file'], r['seconds'], r['peak_dbfs'], r['true_peak_dbtp'], r['m_max'], r['lufs_i']))
    (out / 'measure.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')

    (out / 'README.ko.txt').write_text(README.format(questions='\n'.join('%d. %s' % (i, q) for i, q in enumerate(QUESTIONS, 1))), encoding='utf-8')

    ans = ['P1 정답표 (듣기 전에 보지 마세요. 보내는 묶음(zip)에는 들어 있지 않습니다)', '', '[01~09 이름을 가린 시전]']
    for fname, name in answers:
        ans.append('%s = %s (%s) 원본 파일 %s.wav, 같은 크기 -23 LUFS(M최대)로 맞춤' % (fname, FAMILY[name.rsplit('_', 1)[0]], name.rsplit('_', 1)[0], name))
    ans += ['', '반복된 것: ' + ', '.join(BLIND_REPEATS), '', '[군중·피격 파일]',
            json.dumps(crowd_info, ensure_ascii=False, indent=1), '',
            '같은 크기(-23)로 올리면 참 최대가 -1 dBTP를 넘는 소리는 -1 dBTP에서 멈췄습니다(그만큼 작게 들립니다): ' +
            (', '.join('%s %.1f' % (w, a) for w, _, a in sorted(set(CAPPED))) or '없음') + ' (M최대 LUFS)', '',
            '게임 크기 파일(25~28, game)은 게임의 크기 차이를 그대로 두고 +%.0f dB를 더했습니다.' % GAME_BOOST_DB]
    (out / 'answers.ko.txt').write_text('\n'.join(ans) + '\n', encoding='utf-8')
    (out / 'bundle_measurements.json').write_text(json.dumps({'files': notes, 'crowd': crowd_info}, ensure_ascii=False, indent=1), encoding='utf-8')

    wavs = sorted(out.glob('*.wav'))
    for w in wavs:
        to_m4a(w)
    zpath = out / ('P1-%s.zip' % out.name.split('-')[0])
    if zpath.exists():
        zpath.unlink()
    with zipfile.ZipFile(zpath, 'w', zipfile.ZIP_DEFLATED) as z:
        for f in sorted(list(out.glob('*.wav')) + list(out.glob('*.m4a')) + [out / 'README.ko.txt', out / 'measure.md']):
            z.write(f, f.name)
    print('bundle: %s  files: %d wav, %d m4a  zip: %s (%.1f MB)' % (out, len(wavs), len(list(out.glob('*.m4a'))), zpath.name, zpath.stat().st_size / 1e6))
    print(json.dumps(crowd_info, ensure_ascii=False))


# ---- small commands ---------------------------------------------------------------------------------------

def main():
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('p1', help='build the P1 bundle')
    p.add_argument('--out', required=True)
    p.add_argument('--requests', required=True, help='folder with req_ember.json and req_arc.json')
    p.add_argument('--audio-dir', default=str(am.DEFAULT_DIR))
    c = sub.add_parser('concat', help='join wav files with a gap, optionally matching their level')
    c.add_argument('files', nargs='+'); c.add_argument('-o', required=True); c.add_argument('--gap', type=float, default=0.5)
    c.add_argument('--match', help='mmax:-23 or lufs:-23')
    k = sub.add_parser('pink', help='pink noise at -23 LUFS-I'); k.add_argument('-o', required=True); k.add_argument('--seconds', type=float, default=10.0)
    m = sub.add_parser('m4a', help='convert every wav in a folder'); m.add_argument('folder')
    args = ap.parse_args()
    if args.cmd == 'p1':
        build_p1(args)
    elif args.cmd == 'concat':
        parts = [mono(f) for f in args.files]
        if args.match:
            kind, target = args.match.split(':')
            parts = [match(x, kind, float(target)) for x in parts]
        notes = []
        write(args.o, concat(parts, args.gap), notes)
        print(notes[0])
    elif args.cmd == 'pink':
        notes = []
        write(args.o, pink_noise(args.seconds), notes)
        print(notes[0])
    elif args.cmd == 'm4a':
        for w in sorted(Path(args.folder).glob('*.wav')):
            print(to_m4a(w))
    return 0


if __name__ == '__main__':
    sys.exit(main())
