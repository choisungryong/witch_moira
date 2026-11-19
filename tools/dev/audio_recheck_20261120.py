"""Builds the 2026-11-20 recheck bundle (fire comparison again under one rule set + running-current lightning candidates).

    python tools/dev/make_lightning_candidates.py --out _local/audio/lightning-cands-20261120
    python tools/dev/audio_recheck_20261120.py --out C:/Project/witch-moira/_local/sfx/recheck-20261120

Everything is laid on the SAME recorded footage and request log with tools/dev/audio_scene_audition.py, which reads the playback rules
from chapter1/presentation/combat_audio.gd (one rule set, one "common" loudness gain per set). Nothing goes into the game.

  fire/NN.mp4              the baseline (today's game sounds, lightning SILENT as in the game) + the first taste's sets A, B and B with the
                           three hit layers T1..T3 baked onto the B hit sounds. Numbers are shuffled; the key is answers.json.
  lightning/NN.mp4         the baseline (lightning silent, as in the game) + four lightning cast candidates (unsilenced in that video only).
  lightning-cadence/NN.mp4 the same, with lightning requests added at the game's own cast spacing (73 ticks, taken from the log) so the
                           repetition can be judged. The picture has no lightning in it; this is a sound-only stress test.
  README.txt               what the listener reads. answers.json: the key (do not send). _work/: tool outputs and measurements.
This tool measures and writes. It does not listen.
"""
import argparse, json, shutil, subprocess, sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import audio_measure as am
import audio_scene_audition as sa

REPO = HERE.parents[1]
MAIN = Path('C:/Project/witch-moira')
CAPTURE = MAIN / '_local/sfx/ember-a'
REQUESTS = MAIN / '_local/sfx/req_ember.json'
T1 = MAIN / '_local/audio/taste-20261118'
T2 = MAIN / '_local/audio/taste-20261118b'
LIGHT = MAIN / '_local/audio/lightning-cands-20261120'
SR = 48000
CAST_SPACING = 73            # ticks between lightning casts in the recorded run (6050, 6123, 6196, ...)

LIGHTNING = [
    ('L1', 'synth_discharge_hum', '합성: 지직거림이 잦아든 뒤 낮은 웅웅거림', 0.0,
     '프로젝트 합성(tools/dev/make_lightning_candidates.py), 출처 문제 없음'),
    ('L2', 'synth_tick_small', '합성: 아주 작고 짧은 지직(0.18초), 화염 시전보다 6dB 작게', -6.0,
     '프로젝트 합성(같은 스크립트), 출처 문제 없음'),
    ('L3', 'local_arc_design', '로컬 재료: InMotionAudio Arc의 아크 소리 0.8초, 6kHz 위를 깎음', 0.0,
     'Sonniss GameAudioGDC 2026 묶음 / InMotionAudio - Arc / ELECArc_ArcDesign15_InMotionAudio_Arc.wav (로컬 D:\\witch-moira-audio-sources, 상업 이용 가능·표시 불필요·학습 금지)'),
    ('L4', 'local_arc_low', '로컬 재료: Sound Spark LLC 전기 아크(낮은 쪽) 1.2초', 0.0,
     'Sonniss GameAudioGDC 2020 묶음 / Sound Spark LLC - Electric Arcs and Energy / Electric_Arc_Reverberant_Shock_Long_05.wav (로컬, 같은 약관)'),
]


def run(cmd):
    p = subprocess.run([sys.executable] + [str(c) for c in cmd], capture_output=True, text=True, encoding='utf-8', errors='replace')
    if p.returncode:
        print(p.stdout + p.stderr)
        raise SystemExit('failed: %s' % cmd[:3])
    return p.stdout


def bake_layers(work):
    """B hit variant i + hit layer T.. variant i, the layer at -3 dB under the hit's peak (the recipe of the second taste, build2.py)."""
    out = {}
    for t in ('T1', 'T2', 'T3'):
        files = []
        for i in (1, 2, 3):
            base = sa.load_mono48(T1 / ('fire_hit_B%d.wav' % i))
            lay = sa.load_mono48(T2 / ('hitlayer_%s_%d.wav' % (t, i)))
            lay = lay / (np.abs(lay).max() + 1e-12) * np.abs(base).max() * 10 ** (-3 / 20)
            y = np.zeros(max(len(base), len(lay)))
            y[:len(base)] += base
            y[:len(lay)] += lay
            y = y / max(1.0, np.abs(y).max() / 10 ** (-1 / 20))
            p = work / ('fire_hit_B%d_plus%s.wav' % (i, t))
            am.write_wav(p, y, SR)
            files.append(str(p).replace('\\', '/'))
        out[t] = files
    return out


def taste_set(x, impact=None):
    d = lambda stem, n: ['%s/%s%d.wav' % (T1.as_posix(), stem, i) for i in range(1, n + 1)]
    return {'fire': d('fire_cast_%s' % x, 3), 'cold': d('frost_cast_%s' % x, 2), 'impact': impact or d('fire_hit_%s' % x, 3),
            'death': d('kill_normal_%s' % x, 3), 'explosion': d('fire_boom_%s' % x, 1), 'hurt': d('hero_hit_%s' % x, 1)}


def fire_spec(baked):
    cands = [{'id': 'A', 'label': '첫 시식 A 묶음', 'files': taste_set('A')},
             {'id': 'B', 'label': '첫 시식 B 묶음', 'files': taste_set('B')}]
    for t in ('T1', 'T2', 'T3'):
        cands.append({'id': 'B+' + t, 'label': '첫 시식 B 묶음 + 타격 겹 ' + t, 'files': taste_set('B', baked[t])})
    return {'title': 'fire scene, same rules for all', 'level_match': 'game', 'baseline': True, 'candidates': cands}


def lightning_spec():
    cands = []
    for cid, stem, label, off, _src in LIGHTNING:
        cands.append({'id': cid, 'label': label, 'unsilence': ['lightning'], 'level_ref': {'lightning': 'fire'}, 'level_offset_db': {'lightning': off},
                      'files': {'lightning': [(LIGHT / (stem + '.wav')).as_posix()]}})
    return {'title': 'lightning cast candidates', 'level_match': 'game', 'baseline': True, 'candidates': cands}


def build(name, capture, requests, spec, out, work, seed):
    cj = work / ('cands_%s.json' % name)
    cj.write_text(json.dumps(spec, ensure_ascii=False, indent=1), encoding='utf-8')
    o = work / name
    text = run([HERE / 'audio_scene_audition.py', capture, '--requests', requests, '--candidates', cj, '--out', o, '--seed', seed])
    (work / (name + '.log.txt')).write_text(text, encoding='utf-8')
    m = json.loads((o / 'measure.json').read_text(encoding='utf-8'))
    dst = out / name
    dst.mkdir(parents=True, exist_ok=True)
    for v in m['videos']:
        shutil.copy2(o / 'send' / (v['file'] + '.mp4'), dst / (v['file'] + '.mp4'))
    return m


def table(m, cues):
    rows = ['| 영상 | LUFS-I | 참 최대 dBTP | 이득 dB | 잘림 | ' + ' | '.join(cues) + ' |', '|' + '---|' * (5 + len(cues))]
    for v in m['videos']:
        p = v['played_in_window']
        rows.append('| %s | %.1f | %.1f | %.1f | %d | %s |' % (v['file'], v['lufs_i'], v['true_peak_dbtp'], v['gain_db'], v['clipped'], ' | '.join(str(p.get(c, 0)) for c in cues)))
    return '\n'.join(rows)


def lightning_measure(m):
    """Signal measurements of the candidate files and the levels they get in the game (M max + game gain), against the old lightning file."""
    gain_offset = am.db(.8 * .11 * .82)
    rows = ['| 소리 | 길이 s | 중심 Hz | 2kHz 위 비중 | 150~600Hz 비중 | 최대 도달 ms | 게임 안 M-max LUFS(추정) |', '|---|---|---|---|---|---|---|']
    old = am.measure(REPO / 'chapter1/art/quality03_audio/lightning_0.wav')
    b = old['band_ratio']
    rows.append('| 지금 번개(lightning_0, 꺼져 있음) | %.2f | %d | %.3f | %.3f | %.0f | %.1f |' % (old['duration_s'], old['centroid_hz'], b['2k_6k'] + b['gt6k'], b['150_600'], old['attack_ms'], old['ingame_lufs']))
    for key in ('fire_0', 'cold_0'):
        r = am.measure(REPO / ('chapter1/art/quality03_audio/%s.wav' % key))
        b = r['band_ratio']
        rows.append('| 참고 %s | %.2f | %d | %.3f | %.3f | %.0f | %.1f |' % (key, r['duration_s'], r['centroid_hz'], b['2k_6k'] + b['gt6k'], b['150_600'], r['attack_ms'], r['ingame_lufs']))
    by_id = {v['id']: v for v in m['videos']}
    for cid, stem, label, off, _src in LIGHTNING:
        r = am.measure(LIGHT / (stem + '.wav'))
        b = r['band_ratio']
        g = by_id[cid]['candidate_files']['cues']['lightning'][0]['gain_db']
        rows.append('| %s %s | %.2f | %d | %.3f | %.3f | %.0f | %.1f |' % (cid, stem, r['duration_s'], r['centroid_hz'], b['2k_6k'] + b['gt6k'], b['150_600'], r['attack_ms'], r['momentary_max_lufs'] + g + gain_offset))
    return '\n'.join(rows)


README = """소리 비교 영상 두 묶음 (다시 보기)

이 영상들은 소리를 들을 수 없는 에이전트가 기계로 만들었습니다. 크기와 길이는 측정으로 맞췄지만, 들어 보고 확인한 것이 아닙니다. 듣고 판단해 주세요.
같은 전투 장면(12초)에 소리만 바꾼 영상입니다. 번호는 섞여 있고, 어느 번호가 무엇인지는 말씀드리지 않습니다.
영상끼리의 크고 작음은 게임에서 날 크기 그대로입니다(같은 크기로 키웠습니다). 들은 기기(헤드폰 / 스피커)와 대략의 음량을 적어 주세요.

[1] fire 폴더 (영상 6개): 화염 장면, 소리 묶음만 다릅니다. 모두 같은 게임 규칙으로 만들었습니다.
  지난번 비교는 한 영상만 게임 규칙이었고 나머지는 임시 규칙이어서 소리 말고도 차이가 섞였습니다. 이번에는 조건이 같습니다.
  답: 6개 가운데 가장 마음에 드는 번호 둘과 가장 거슬리는 번호 하나, 이유 한 줄씩.
  타격 때 소리가 화면과 맞는지, 군중이 몰릴 때 피곤한 번호가 있는지도 있으면 적어 주세요.

[2] lightning 폴더 (영상 5개): 번개를 "전류가 흐르는 소리"로 바꿀 후보입니다. 그중 하나는 번개 소리가 아예 없는 영상(지금 게임)입니다.
  이 장면에서 번개 시전은 12초 끝 무렵에 한 번만 나옵니다. 번호마다 그때 나는 소리를 들어 주세요.
  답: 거슬리지 않는 순서(번호로), 전류가 흐르는 느낌에 가까운 번호, 이유 한 줄.

[3] lightning-cadence 폴더 (영상 5개, 선택): 위와 같은 소리를 번개를 자주 쓸 때의 간격(1.2초마다)으로 반복해 넣었습니다.
  화면에는 번개 그림이 나오지 않고 소리만 얹은 시험입니다. 반복해서 들어도 괜찮은지만 봐 주세요.
  답: 반복이 피곤한 번호, 괜찮은 번호.
"""


def main():
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', required=True)
    args = ap.parse_args()
    out = Path(args.out)
    if '_local' not in out.resolve().parts:
        raise SystemExit('--out must be under _local/')
    work = out / '_work'
    work.mkdir(parents=True, exist_ok=True)
    baked = bake_layers(work)
    answers, tables = {}, []

    mf = build('fire', CAPTURE, REQUESTS, fire_spec(baked), out, work, 20261120)
    answers['fire'] = {v['file']: {'id': v['id'], 'label': v['label']} for v in mf['videos']}
    tables.append('[fire] ' + str(mf['alignment']['ok']) + '\n' + table(mf, ['fire', 'cold', 'lightning', 'impact', 'explosion', 'death', 'hurt', 'step']))

    ml = build('lightning', CAPTURE, REQUESTS, lightning_spec(), out, work, 20261121)
    answers['lightning'] = {v['file']: {'id': v['id'], 'label': v['label']} for v in ml['videos']}
    tables.append('[lightning] ' + str(ml['alignment']['ok']) + '\n' + table(ml, ['fire', 'cold', 'lightning', 'impact', 'explosion', 'death']))
    tables.append(lightning_measure(ml))

    # cadence stress: lightning requests at the recorded spacing, going back from the one real cast in the window
    log = json.loads(REQUESTS.read_text(encoding='utf-8'))
    real = sorted(int(r[0]) for r in log['requests'] if r[1] == 'lightning')
    cap = sa.load_capture(CAPTURE)
    t0, t1 = cap['from'], cap['from'] + cap['frames']
    first = next(t for t in real if t0 <= t < t1)
    extra = [[t, 'lightning', 0, 1, 'cast'] for t in range(first - CAST_SPACING, t0 - 1, -CAST_SPACING)]
    log['requests'] = log['requests'] + extra
    (work / 'req_cadence.json').write_text(json.dumps(log), encoding='utf-8')
    mc = build('lightning-cadence', CAPTURE, work / 'req_cadence.json', lightning_spec(), out, work, 20261122)
    answers['lightning-cadence'] = {v['file']: {'id': v['id'], 'label': v['label']} for v in mc['videos']}
    tables.append('[lightning-cadence: %d requests added, real cast at tick %d, spacing %d]\n' % (len(extra), first, CAST_SPACING) + table(mc, ['fire', 'cold', 'lightning', 'impact', 'explosion', 'death']))

    (out / 'answers.json').write_text(json.dumps(answers, ensure_ascii=False, indent=1), encoding='utf-8')
    (out / 'README.txt').write_text(README, encoding='utf-8')
    (work / 'tables.txt').write_text('\n\n'.join(tables) + '\n', encoding='utf-8')
    print('\n\n'.join(tables))
    return 0


if __name__ == '__main__':
    sys.exit(main())
