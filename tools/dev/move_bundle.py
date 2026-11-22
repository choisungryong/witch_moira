"""Bundle what lives outside git into one zip for moving to another PC.

    python tools/dev/move_bundle.py --out D:/witch-moira-move-YYYYMMDD.zip            build
    python tools/dev/move_bundle.py --out D:/witch-moira-move-YYYYMMDD.zip --update   add files that are new or changed since

The repository itself is cloned from the remote and is not bundled. Stored without compression (images, video and models
do not shrink, and it is several times faster). The zip holds the image generation key (.env): delete it after the move.
Layout inside the zip and where each part goes is written to README-MOVE.txt at the zip root.
"""
import argparse, os, sys, time, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HOME = Path(os.environ.get('USERPROFILE', str(Path.home())))
APPDATA = Path(os.environ.get('APPDATA', str(HOME / 'AppData' / 'Roaming')))

# (source, path inside the zip, note)
LOCAL_KEEP = ['art', 'ref', 'ui', 'd19', 'd20-meteor', 'design', 'tools', 'vfx', 'char3d', 'char3d-blender-only', 'sfx', 'audio', 'builds']
PARTS = [
    (ROOT / '.env', 'repo-extras/.env', r'C:\Project\witch-moira\.env'),
    (ROOT / '.codex', 'repo-extras/.codex', r'C:\Project\witch-moira\.codex'),
    (ROOT.parent / 'CLAUDE.md', 'project-root/CLAUDE.md', r'C:\Project\CLAUDE.md'),
    (Path('D:/Project/witch-moira-work'), 'work', r'D:\Project\witch-moira-work'),
    (HOME / '.claude' / 'projects' / 'C--Project-witch-moira' / 'memory', 'claude-memory', r'C:\Users\<name>\.claude\projects\C--Project-witch-moira\memory'),
    (APPDATA / 'WitchMoira', 'appdata/WitchMoira', r'%APPDATA%\WitchMoira'),
    (HOME / '.agents' / 'skills' / 'sunra', 'user-home/.agents/skills/sunra', r'C:\Users\<name>\.agents\skills\sunra'),
]
SKIP_DIRS = {'.godot', '__pycache__', 'appdata', 'logs'}


def local_parts():
    out = []
    base = ROOT / '_local'
    for name in LOCAL_KEEP:
        if (base / name).exists():
            out.append((base / name, 'repo-extras/_local/' + name, r'C:\Project\witch-moira\_local' + '\\' + name))
    for f in sorted(base.glob('HANDOVER-*.md')):
        out.append((f, 'repo-extras/_local/' + f.name, r'C:\Project\witch-moira\_local' + '\\' + f.name))
    for f in sorted(ROOT.glob('*.txt')):          # untracked notes kept at the repository root
        out.append((f, 'repo-extras/' + f.name, r'C:\Project\witch-moira' + '\\' + f.name))
    for f in sorted((ROOT / 'tools' / 'manager').glob('local-*.json')):   # the user's own records of the manager tool (git-ignored)
        out.append((f, 'repo-extras/tools/manager/' + f.name, r'C:\Project\witch-moira\tools\manager' + '\\' + f.name))
    return out


def walk(src):
    if src.is_file():
        yield src, ''
        return
    for dirpath, dirnames, filenames in os.walk(src):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            p = Path(dirpath) / name
            yield p, p.relative_to(src).as_posix()


def readme(parts):
    lines = ['Witch Moira - move bundle', time.strftime('made %Y-%m-%d %H:%M'), '',
             'Repository: git clone https://github.com/choisungryong/witch_moira.git C:\\Project\\witch-moira', '',
             'Unpack each folder of this zip to:']
    seen = set()
    for _src, arc, dest in parts:
        top = arc.split('/')[0] + ('/' + arc.split('/')[1] if arc.startswith('repo-extras/') else '')
        if arc in seen:
            continue
        seen.add(arc)
        lines.append('  %-46s -> %s' % (arc, dest))
    lines += ['', 'First read: C:\\Project\\witch-moira\\_local\\HANDOVER-20261120b.ko.md',
              'This zip holds the image generation key (.env). Delete the zip after the move.', '']
    return '\r\n'.join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    ap.add_argument('--update', action='store_true')
    args = ap.parse_args()
    out = Path(args.out)
    parts = [p for p in PARTS if p[0].exists()] + local_parts()
    have = {}
    if args.update:
        if not out.exists():
            sys.exit('no zip to update: %s' % out)
        with zipfile.ZipFile(out) as z:
            have = {i.filename: (i.file_size, i.date_time) for i in z.infolist()}
    mode = 'a' if args.update else 'w'
    added = skipped = 0
    total = 0
    with zipfile.ZipFile(out, mode, zipfile.ZIP_STORED, allowZip64=True) as z:
        for src, arc, _dest in parts:
            for path, rel in walk(src):
                name = arc + ('/' + rel if rel else '')
                try:
                    st = path.stat()
                except OSError:
                    continue
                stamp = time.localtime(st.st_mtime)[:6]
                old = have.get(name)
                if old and old[0] == st.st_size and tuple(old[1]) >= (stamp[0], stamp[1], stamp[2], stamp[3], stamp[4], stamp[5] // 2 * 2):
                    skipped += 1
                    continue
                try:
                    z.write(path, name)
                except (OSError, ValueError) as error:
                    print('SKIP %s: %s' % (path, error))
                    continue
                added += 1
                total += st.st_size
        if not args.update:
            z.writestr('README-MOVE.txt', readme(parts))
    print('MOVE_BUNDLE %s' % {'out': str(out), 'added': added, 'unchanged': skipped, 'added_gb': round(total / 2 ** 30, 2),
                               'zip_gb': round(out.stat().st_size / 2 ** 30, 2)})


if __name__ == '__main__':
    main()
