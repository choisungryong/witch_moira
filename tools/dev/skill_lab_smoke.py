#!/usr/bin/env python3
"""Skill lab end-to-end smoke (T12 SL-D). Needs a real window and ffmpeg, so run_all.py does NOT run it.

It goes the server's way (tools/manager/skill_lab.py functions, no HTTP): opens the lab window, sends the 18 scenes
(3 characters x base/evolved/descent x single/pack), saves one picture of the window per scene, puts the lightning
candidate C7 into skill.arc.cast and checks that the window's sound request log (audio.recent) names c7_*, then closes
the window with the `quit` command. After that it films the same 18 scenes with tools/manager/skill_lab_clips.py
(the page's clip path) and checks each mp4 (length, size, audio stream), that asking again does not film again, and
that a changed sound map marks a clip stale (on a copy of the world files in a temp folder, never on the real ones).

  python tools/dev/skill_lab_smoke.py [--root DIR] [--out _local/skill-lab/smoke] [--no-clips] [--only ember/base/single,...]
                                      [--clip-timeout 300]

Output: <out>/shots/<char>-<form>-<layout>.png (18), <out>/sheet.png (contact sheet), <out>/report.json, one line per
step on stdout, last line `SKILL_LAB_SMOKE {"pass": bool, "failures": [...]}`. Exit code 0 only when nothing failed.
It uses the lab folder <root>/_local/skill-lab, so it refuses to start while a lab window is connected there.
The pictures are not judged here: whether the cast, effects and enemies look as commanded is for a person to see.
"""
import argparse, json, os, shutil, struct, subprocess, sys, tempfile, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools' / 'manager'))
import skill_lab, skill_lab_clips          # noqa: E402

FORMS = ('base', 'evolved', 'descent')
LAYOUTS = ('single', 'pack')
C7_ID = 'chain-lightning/round2/C7'
C7_SLOT = 'skill.arc.cast'
CLIP_SIZE = (1280, 720)
CLIP_SECONDS = (3.0, 4.6)          # the filming command asks for 4 s
START_TIMEOUT = 120
failures = []
report = {'steps': []}


def say(step, **kw):
    kw['step'] = step
    kw['t'] = round(time.time() - T0, 1)
    print('SMOKE ' + json.dumps(kw, ensure_ascii=False), flush=True)
    report['steps'].append(kw)


def fail(text):
    failures.append(text)
    print('SMOKE_FAIL ' + text, flush=True)


T0 = time.time()


def wait_for(fn, seconds, every=0.25):
    end = time.time() + seconds
    while time.time() < end:
        v = fn()
        if v:
            return v
        time.sleep(every)
    return None


def png_size(path):
    with open(path, 'rb') as f:
        head = f.read(24)
    if head[:8] != b'\x89PNG\r\n\x1a\n':
        return None
    return struct.unpack('>II', head[16:24])


def picture_stats(path):
    """(width, height, standard deviation of the gray level): a flat grey or black picture is a failed capture."""
    try:
        from PIL import Image, ImageStat
        with Image.open(path) as im:
            g = im.convert('L')
            return im.size[0], im.size[1], round(ImageStat.Stat(g).stddev[0], 1)
    except ImportError:
        size = png_size(path)
        return (size[0], size[1], None) if size else None


def scene_for(chars, elem, form, layout):
    c = next(x for x in chars if x['elem'] == elem)
    return {'character': c['id'], 'skill': c['primary'], 'form': form, 'layout': layout, 'count': 8, 'motion': 'hold', 'durable': False,
            'repeat': True, 'interval_s': 3.0, 'speed': 1.0, 'juice': True}


def state_now(root):
    st, _ = skill_lab.read_state(root)
    return st or {}


def wait_applied(root, seq, seconds):
    return wait_for(lambda: (lambda s: s if int(s.get('applied_seq', -1)) >= seq else None)(state_now(root)), seconds)


def one_scene(root, name, scene, first, shots, audio=None):
    """Sends a scene (the first one starts the window), waits for it to be applied and ready, waits for the cast, saves the picture."""
    res = {'name': name, 'ok': False}
    before = state_now(root)
    cast_before = int((before.get('casts') or {}).get('count', 0)) if not first else 0
    err_before = len(before.get('errors') or []) if not first else 0
    t0 = time.time()
    try:
        r = skill_lab.open_window(root, scene, audio or {}) if first else skill_lab.send_scene(root, scene, audio or {})
    except Exception as e:                      # LabError, ValueError
        res['error'] = 'send: %s' % e
        fail('%s: %s' % (name, res['error']))
        return res
    seq = r['seq']
    st = wait_applied(root, seq, START_TIMEOUT if first else 30)
    if not st:
        res['error'] = 'seq %d not applied' % seq
        fail('%s: %s' % (name, res['error']))
        return res
    ready = wait_for(lambda: state_now(root).get('ready'), 30)
    if not ready:
        fail('%s: not ready within 30 s' % name)
    # the cast happens when the stage stands; descent is called, not cast, so only base/evolved count casts
    if scene['form'] != 'descent':
        got = wait_for(lambda: int((state_now(root).get('casts') or {}).get('count', 0)) > cast_before, 25)
        if not got:
            fail('%s: no cast within 25 s' % name)
    time.sleep(3.0 if scene['form'] == 'descent' else 0.3)         # after the cast is seen (state lags up to 0.5 s): descent has a cut-in first, the others' effects are short
    shot = skill_lab.request_shot(root, 'smoke-' + name)           # one file name per scene: an older picture can never pass for this one
    got_shot = wait_for(lambda: state_now(root).get('last_shot') == shot['path'] and skill_lab.shot_file(root, 'smoke-' + name) is not None
                        and int(state_now(root).get('applied_seq', 0)) >= shot['seq'], 20)
    src = skill_lab.shot_file(root, 'smoke-' + name)
    final = state_now(root)
    new_errors = (final.get('errors') or [])[err_before:]
    if new_errors:
        fail('%s: window errors: %s' % (name, new_errors[:3]))
    if not got_shot or src is None:
        fail('%s: no picture saved' % name)
    else:
        dst = shots / (name + '.png')
        shutil.copyfile(src, dst)
        stats = picture_stats(dst)
        res['picture'] = dst.relative_to(root).as_posix() if dst.is_relative_to(root) else str(dst)
        res['picture_stats'] = stats
        if not stats or (stats[2] is not None and stats[2] < 8):
            fail('%s: picture looks blank (%s)' % (name, stats))
    run = final.get('run') or {}
    res.update({'seconds': round(time.time() - t0, 1), 'mode': run.get('mode'), 'staged': run.get('staged'), 'enemies_alive': run.get('enemies_alive'),
                'casts': (final.get('casts') or {}).get('count'), 'applied_seq': final.get('applied_seq'), 'errors': new_errors,
                'scene_echo_ok': all((final.get('scene') or {}).get(k) == v for k, v in scene.items() if k in ('character', 'skill', 'form', 'layout', 'count'))})
    if not res['scene_echo_ok']:
        fail('%s: the window reports another scene than the one sent: %s' % (name, final.get('scene')))
    if not run.get('staged'):
        fail('%s: nothing staged (staged=%s)' % (name, run.get('staged')))
    res['ok'] = not any(f.startswith(name + ':') for f in failures)
    return res


def check_c7(root, shots):
    """Arc, base, single, with C7 in skill.arc.cast: audio.recent must name c7_* ; then clear it and see the overrides empty."""
    out = {'candidate': C7_ID, 'slot': C7_SLOT}
    chars = skill_lab.characters_table(root)
    scene = scene_for(chars, 'arc', 'base', 'single')
    cand = skill_lab.find_candidate(root, C7_ID)
    if cand is None or cand['missing']:
        fail('c7: candidate %s not found or files missing (%s)' % (C7_ID, cand and cand['missing']))
        return out
    r = skill_lab.send_scene(root, scene, {C7_SLOT: C7_ID})
    st = wait_applied(root, r['seq'], 30)
    if not st:
        fail('c7: seq not applied')
        return out
    out['overrides'] = (st.get('audio') or {}).get('overrides')
    out['load_errors'] = (st.get('audio') or {}).get('load_errors')
    if out['load_errors']:
        fail('c7: load errors %s' % out['load_errors'])
    hit = wait_for(lambda: [x for x in (state_now(root).get('audio') or {}).get('recent', []) if x.get('slot') == C7_SLOT and 'c7_' in os.path.basename(str(x.get('path', '')))], 25)
    rows = (state_now(root).get('audio') or {}).get('recent', [])
    out['recent_tail'] = rows[-6:]
    out['c7_rows'] = len(hit or [])
    if not hit:
        fail('c7: audio.recent has no row of %s with a c7_* file within 25 s' % C7_SLOT)
    out['ok'] = bool(hit) and not out['load_errors']
    skill_lab.request_shot(root, 'smoke-c7')
    wait_for(lambda: skill_lab.shot_file(root, 'smoke-c7') is not None and state_now(root).get('last_shot', '').endswith('smoke-c7.png'), 20)
    src = skill_lab.shot_file(root, 'smoke-c7')
    if src is not None:
        shutil.copyfile(src, shots / 'arc-base-single-c7.png')
    # clear
    r2 = skill_lab.send_scene(root, scene, {})
    st2 = wait_applied(root, r2['seq'], 30)
    out['overrides_after_clear'] = ((st2 or {}).get('audio') or {}).get('overrides')
    if st2 and out['overrides_after_clear']:
        fail('c7: overrides not empty after sending audio {}: %s' % out['overrides_after_clear'])
    return out


def close_window(root, popen_wait=60):
    out = {}
    st = state_now(root)
    pid = st.get('pid')
    t0 = time.time()
    skill_lab.send_simple(root, 'quit')
    gone = wait_for(lambda: not skill_lab._pid_alive(pid), popen_wait)
    out.update({'pid': pid, 'closed': bool(gone), 'seconds': round(time.time() - t0, 1)})
    proc = skill_lab._LAUNCH.get('proc')
    if proc is not None:
        try:
            out['exit_code'] = proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            out['exit_code'] = None
    out['lock_left'] = (skill_lab.lab_dir(root) / 'lab.lock').exists()
    if not gone:
        fail('quit: the window (pid %s) did not close within %d s' % (pid, popen_wait))
        try:
            subprocess.run(['taskkill', '/PID', str(pid), '/T', '/F'], capture_output=True, timeout=20)
        except Exception:
            pass
    elif out.get('exit_code') not in (0, None):
        fail('quit: window exit code %s' % out.get('exit_code'))
    if out['lock_left']:
        fail('quit: lab.lock left behind')
    return out


def ffprobe_info(path):
    probe = shutil.which('ffprobe')
    if not probe:
        return None
    done = subprocess.run([probe, '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(path)], capture_output=True, timeout=60)
    try:
        return json.loads(done.stdout.decode('utf-8', 'replace'))
    except ValueError:
        return None


def audio_level(path):
    ff = shutil.which('ffmpeg')
    if not ff:
        return None
    done = subprocess.run([ff, '-v', 'info', '-i', str(path), '-af', 'volumedetect', '-vn', '-f', 'null', '-'], capture_output=True, timeout=60)
    text = done.stderr.decode('utf-8', 'replace')
    import re
    mean, peak = re.search(r'mean_volume: (-?[\d.]+|-inf) dB', text), re.search(r'max_volume: (-?[\d.]+|-inf) dB', text)
    return {'mean_db': mean.group(1) if mean else None, 'peak_db': peak.group(1) if peak else None}


def check_clip(root, name, cid):
    path = skill_lab_clips.video_file(root, cid)
    res = {'name': name, 'id': cid}
    if path is None:
        fail('clip %s: no video file' % name)
        return res
    info = ffprobe_info(path)
    if info is None:
        fail('clip %s: ffprobe unreadable' % name)
        return res
    streams = info.get('streams', [])
    v = next((s for s in streams if s.get('codec_type') == 'video'), None)
    a = next((s for s in streams if s.get('codec_type') == 'audio'), None)
    dur = float(info.get('format', {}).get('duration', 0) or 0)
    res.update({'bytes': path.stat().st_size, 'duration_s': round(dur, 2), 'video': v and [v.get('codec_name'), v.get('width'), v.get('height')],
                'audio': a and [a.get('codec_name'), a.get('sample_rate'), a.get('channels')]})
    if v is None or (v.get('width'), v.get('height')) != CLIP_SIZE:
        fail('clip %s: video size %s, wanted %s' % (name, v and (v.get('width'), v.get('height')), CLIP_SIZE))
    if a is None:
        fail('clip %s: no audio stream' % name)
    else:
        res['level'] = audio_level(path)
    if not CLIP_SECONDS[0] <= dur <= CLIP_SECONDS[1]:
        fail('clip %s: duration %.2f s outside %.1f..%.1f' % (name, dur, *CLIP_SECONDS))
    if res['bytes'] < 20000:
        fail('clip %s: only %d bytes' % (name, res['bytes']))
    return res


def run_clips(root, scenes, timeout):
    results, ids = [], {}
    for name, scene in scenes:
        t0 = time.time()
        try:
            job = skill_lab_clips.request(root, scene, {}, 'movie')
        except Exception as e:
            fail('clip %s: request: %s' % (name, e))
            continue
        cid = job['id']
        ids[name] = (cid, scene)
        if job.get('cached'):
            say('clip-cached-already', name=name, id=cid)
        done = wait_for(lambda: (lambda s: s if s and s['state'] in ('done', 'error') else None)(skill_lab_clips.status(root, cid)), timeout, every=1.0)
        if not done:
            fail('clip %s: not finished within %d s' % (name, timeout))
            continue
        if done['state'] == 'error':
            fail('clip %s: error: %s' % (name, done.get('error')))
            continue
        r = check_clip(root, name, cid)
        r['made_in_s'] = round(time.time() - t0, 1)
        r['cached_hit'] = bool(job.get('cached'))
        results.append(r)
        say('clip', **{k: v for k, v in r.items() if k != 'level'}, level=r.get('level'))
    return results, ids


def run_cache_check(root, ids):
    """Asking again for every filmed scene must answer from the cache: same id, `cached`, the mp4 and its meta untouched, no job queued."""
    out = {'asked': 0, 'cached': 0}
    for name, (cid, scene) in ids.items():
        p = skill_lab_clips.video_file(root, cid)
        if p is None:
            continue
        # a hit touches the mp4's mtime on purpose (the size limit drops what was used longest ago), so the file's identity is its size and the meta's made_at
        before = (p.stat().st_size, skill_lab_clips.read_meta(root, cid).get('made_at'))
        t0 = time.time()
        job = skill_lab_clips.request(root, scene, {}, 'movie')
        after = (p.stat().st_size, skill_lab_clips.read_meta(root, cid).get('made_at'))
        out['asked'] += 1
        ok = job.get('id') == cid and job.get('cached') is True and job.get('state') == 'done' and before == after
        if ok:
            out['cached'] += 1
        else:
            fail('cache %s: asked again and got %s (cached=%s), file before %s after %s' % (name, job.get('state'), job.get('cached'), before, after))
        if time.time() - t0 > 5:
            fail('cache %s: the answer took %.1f s' % (name, time.time() - t0))
    with skill_lab_clips._LOCK:
        out['jobs_left'] = [j for j in skill_lab_clips._JOBS.values() if j['state'] in ('queued', 'running')]
    if out['jobs_left']:
        fail('cache: %d job(s) queued by asking again' % len(out['jobs_left']))
        out['jobs_left'] = len(out['jobs_left'])
    else:
        out['jobs_left'] = 0
    return out


def run_stale_check(root, ids, tmp_parent):
    """A copy of the world files (what skill_lab_clips.world_hash reads) plus one clip: the same files give stale False; one more byte in
    the sound map gives stale True and a new id for the same request. The real files are only read."""
    out = {}
    if not ids:
        return out
    name, (cid, scene) = next(iter(ids.items()))
    shadow = Path(tempfile.mkdtemp(prefix='stale-', dir=str(tmp_parent)))
    try:
        files = {root / f for f in skill_lab_clips.WORLD_FILES}
        for g in skill_lab_clips.WORLD_GLOBS:
            files.update(p for p in root.glob(g) if p.is_file())
        for p in files:
            if p.is_file():
                dst = shadow / p.relative_to(root)
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(p, dst)
        cdir = skill_lab_clips.clips_dir(shadow)
        cdir.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(skill_lab_clips.clips_dir(root) / (cid + '.mp4'), cdir / (cid + '.mp4'))
        shutil.copyfile(skill_lab_clips.clips_dir(root) / (cid + '.json'), cdir / (cid + '.json'))
        same = skill_lab_clips.world_hash(shadow) == skill_lab_clips.world_hash(root)
        before = skill_lab_clips.status(shadow, cid)
        out['same_world_hash_on_copy'] = same
        out['stale_before'] = before and before.get('stale')
        if not same or before is None or before.get('stale'):
            fail('stale: the copy of the world files does not look the same as the real ones (same=%s, stale=%s)' % (same, before and before.get('stale')))
            return out
        amap = shadow / 'chapter1/data/audio_map.json'
        amap.write_bytes(amap.read_bytes() + b'\n')
        after = skill_lab_clips.status(shadow, cid)
        out['stale_after_sound_map_change'] = after and after.get('stale')
        out['stale_reason'] = after and after.get('stale_reason')
        shas = {}
        new_id = skill_lab_clips.clip_id(scene, shas, 'movie', skill_lab_clips.world_hash(shadow))
        out['new_id_differs'] = new_id != cid
        if not after or not after.get('stale'):
            fail('stale: a changed audio_map.json did not mark the clip stale')
        if new_id == cid:
            fail('stale: the clip id did not change with the sound map')
    finally:
        shutil.rmtree(shadow, ignore_errors=True)
    return out


def contact_sheet(shots, names, dst):
    try:
        from PIL import Image
    except ImportError:
        return False
    tiles = [(n, shots / (n + '.png')) for n in names if (shots / (n + '.png')).is_file()]
    if not tiles:
        return False
    w, h, cols = 640, 360, 3
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * w, rows * h), (20, 20, 20))
    for i, (_, p) in enumerate(tiles):
        with Image.open(p) as im:
            sheet.paste(im.convert('RGB').resize((w, h)), ((i % cols) * w, (i // cols) * h))
    sheet.save(dst)
    return True


def git_head(root):
    try:
        return subprocess.run(['git', '-C', str(root), 'rev-parse', '--short', 'HEAD'], capture_output=True, timeout=20).stdout.decode().strip()
    except Exception:
        return ''


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--root', default=str(ROOT))
    ap.add_argument('--out', default='_local/skill-lab/smoke')
    ap.add_argument('--no-clips', action='store_true', help='skip the 18 movies (about 10 minutes)')
    ap.add_argument('--no-window', action='store_true', help='skip the window part (pictures, C7, quit)')
    ap.add_argument('--only', default='', help='comma separated <elem>/<form>/<layout> to run instead of all 18')
    ap.add_argument('--clip-timeout', type=int, default=300)
    a = ap.parse_args(argv)
    root = Path(a.root).resolve()
    out = Path(a.out) if os.path.isabs(a.out) else root / a.out
    shots = out / 'shots'
    shots.mkdir(parents=True, exist_ok=True)
    for p in shots.glob('*.png'):
        p.unlink()
    if not (root / 'chapter1/tests/skill_lab.gd').is_file():
        print('SKILL_LAB_SMOKE ' + json.dumps({'pass': False, 'failures': ['chapter1/tests/skill_lab.gd is missing in ' + str(root)]}))
        return 1
    if skill_lab.window_status(root)['status'] in ('connected', 'starting'):
        print('SKILL_LAB_SMOKE ' + json.dumps({'pass': False, 'failures': ['a lab window is already connected in %s/_local/skill-lab; close it first' % root]}))
        return 1
    chars = skill_lab.characters_table(root)
    elems = [c['elem'] for c in chars]
    wanted = set(x for x in a.only.split(',') if x)
    scenes = [('%s-%s-%s' % (e, f, l), scene_for(chars, e, f, l)) for e in elems for f in FORMS for l in LAYOUTS if not wanted or '%s/%s/%s' % (e, f, l) in wanted]
    report.update({'root': str(root), 'head': git_head(root), 'started': time.strftime('%Y-%m-%d %H:%M:%S'), 'scenes_wanted': len(scenes),
                   'note': 'window 1600x900 started by skill_lab.build_launch_args; windows are not claimed to be focused (the lab runs with --chapter1-qa-ignore-focus); pictures are saved from the window\'s own viewport'})
    if len(elems) != 3 or (not wanted and len(scenes) != 18):
        fail('characters table: expected 3 characters, got %s' % elems)
    report['scenes'], report['c7'], report['quit'], report['clips'] = [], {}, {}, []

    if not a.no_window:
        say('window-start', scenes=len(scenes))
        for i, (name, scene) in enumerate(scenes):
            r = one_scene(root, name, scene, i == 0, shots)
            report['scenes'].append(r)
            say('scene', **{k: v for k, v in r.items() if k != 'picture_stats'}, stats=r.get('picture_stats'))
            if i == 0 and not r.get('ok') and not state_now(root).get('pid'):
                fail('window never came up; stopping')
                break
        if skill_lab.window_status(root)['status'] == 'connected':
            if not wanted or 'arc/base/single' in wanted:
                report['c7'] = check_c7(root, shots)
                say('c7', **{k: v for k, v in report['c7'].items() if k != 'recent_tail'})
            report['quit'] = close_window(root)
            say('quit', **report['quit'])
        else:
            fail('window is not connected after the scenes')
        report['sheet'] = contact_sheet(shots, [n for n, _ in scenes], out / 'sheet.png')

    if not a.no_clips:
        if not shutil.which('ffmpeg') or not shutil.which('ffprobe'):
            fail('clips: ffmpeg/ffprobe not on PATH')
        else:
            say('clips-start', scenes=len(scenes))
            results, ids = run_clips(root, scenes, a.clip_timeout)
            report['clips'] = results
            if results:
                times = sorted(r['made_in_s'] for r in results)
                report['clip_seconds'] = {'n': len(times), 'min': times[0], 'median': times[len(times) // 2], 'max': times[-1],
                                          'note': 'wall seconds per clip on a PC that may be busy with other Godot/GPU work'}
            report['cache'] = run_cache_check(root, ids)
            say('cache', **report['cache'])
            report['stale'] = run_stale_check(root, ids, out)
            say('stale', **report['stale'])

    report['failures'] = failures
    report['pass'] = not failures
    report['finished'] = time.strftime('%Y-%m-%d %H:%M:%S')
    report['seconds'] = round(time.time() - T0, 1)
    (out / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('SKILL_LAB_SMOKE ' + json.dumps({'pass': not failures, 'failures': failures, 'report': str(out / 'report.json')}, ensure_ascii=False))
    return 0 if not failures else 1


if __name__ == '__main__':
    sys.exit(main())
