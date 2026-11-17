"""Build a Windows executable with Godot's export.

    python tools/dev/build.py --preset store     # sales build: verification arguments are ignored
    python tools/dev/build.py --preset qa        # release template + "qa" feature tag: verification arguments work
    python tools/dev/build.py --preset debug     # debug template + "qa"

Output: _local/build/<stamp>/<preset>/WitchMoira.exe and build.json next to it (stamp = date-commit).

Templates are not read from the user folder (%APPDATA%/Godot). They are read from
$MOIRA_TEMPLATES (default C:/Project/rea-tools/godot-4.5.1/templates). The repository's
export_presets.cfg carries no machine path: the script writes the template paths into it just
before the export and puts the original bytes back afterwards. If the restore fails, the build fails.

Nothing is downloaded. Nothing outside the repository (other than the template and engine files
it reads) is touched. Saves in %APPDATA%/WitchMoira are never read or written.
"""
from pathlib import Path
import argparse, datetime, hashlib, json, os, struct, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
GODOT = Path(os.environ.get('MOIRA_GODOT', 'C:/Project/rea-tools/godot-4.5.1/Godot_v4.5.1-stable_win64_console.exe'))
TEMPLATES = Path(os.environ.get('MOIRA_TEMPLATES', 'C:/Project/rea-tools/godot-4.5.1/templates'))
EXPECTED_VERSION = '4.5.1.stable'
PRESETS = {
    'store': ('Windows Store', 'release'),
    'qa': ('Windows QA', 'release'),
    'debug': ('Windows Debug', 'debug'),
}
FORBIDDEN_PREFIXES = ('res://chapter1/tests/', 'res://docs/', 'res://tools/', 'res://_local/', 'res://art-archive/')
FORBIDDEN_SUFFIXES = ('.md',)
EXE_NAME = 'WitchMoira.exe'


def isolated_env(stamp):
    """Environment for the Godot child processes only: APPDATA points into _local/build, so the
    engine's own user-folder writes (logs, caches) never land in %APPDATA%/WitchMoira."""
    folder = ROOT / '_local' / 'build' / stamp / 'appdata_godot'
    folder.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env['APPDATA'] = str(folder)
    return env


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for block in iter(lambda: handle.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def fail(message):
    print('BUILD_FAIL ' + message)
    raise SystemExit(1)


def git(*args):
    result = subprocess.run(['git', '-C', str(ROOT)] + list(args), capture_output=True, text=True, encoding='utf-8', errors='replace')
    return result.stdout.strip() if result.returncode == 0 else ''


def check_templates(kind):
    version_file = TEMPLATES / 'version.txt'
    if not version_file.is_file():
        fail('template folder has no version.txt: %s (set MOIRA_TEMPLATES)' % TEMPLATES)
    version = version_file.read_text(encoding='utf-8').strip()
    if version != EXPECTED_VERSION:
        fail('template version %r, expected %r' % (version, EXPECTED_VERSION))
    template = TEMPLATES / ('windows_%s_x86_64.exe' % kind)
    if not template.is_file():
        fail('template missing: %s' % template)
    actual = sha256(template)
    evidence = TEMPLATES.parent / 'acquisition-evidence.json'
    recorded = ''
    if evidence.is_file():
        for entry in json.loads(evidence.read_text(encoding='utf-8')).get('files', []):
            if entry.get('file') == 'templates/' + template.name:
                recorded = entry.get('sha256', '')
    else:
        print('BUILD_WARN no acquisition-evidence.json next to the template folder; sha256 not verified')
    if recorded and recorded != actual:
        fail('template sha256 differs from the record: %s vs %s' % (actual, recorded))
    return template, actual, bool(recorded)


def import_project(env):
    fresh = not (ROOT / '.godot' / 'imported').is_dir()
    for index in range(2 if fresh else 1):
        result = subprocess.run([str(GODOT), '--headless', '--path', str(ROOT), '--import'], env=env, capture_output=True, text=True, encoding='utf-8', errors='replace')
        print('BUILD_IMPORT pass=%d exit=%d' % (index + 1, result.returncode))
        if result.returncode != 0:
            print(result.stdout[-2000:])
            fail('import failed')


def export(preset_name, kind, template, out_exe, log_path, env):
    cfg = ROOT / 'export_presets.cfg'
    original = cfg.read_bytes()
    path_text = template.parent.as_posix()
    patched = original
    for key, file_kind in (('release', 'release'), ('debug', 'debug')):
        line = ('custom_template/%s=""' % key).encode()
        value = ('custom_template/%s="%s/windows_%s_x86_64.exe"' % (key, path_text, file_kind)).encode()
        if line not in patched:
            fail('export_presets.cfg has no empty %s line (the repository file must carry no machine path)' % line.decode())
        patched = patched.replace(line, value)
    flag = '--export-release' if kind == 'release' else '--export-debug'
    out_exe.parent.mkdir(parents=True, exist_ok=True)
    restore_error = ''
    try:
        cfg.write_bytes(patched)
        result = subprocess.run([str(GODOT), '--headless', '--path', str(ROOT), flag, preset_name, str(out_exe)], env=env, capture_output=True, text=True, encoding='utf-8', errors='replace')
    finally:
        cfg.write_bytes(original)
        if cfg.read_bytes() != original:
            restore_error = 'export_presets.cfg could not be restored'
    log_path.write_text('exit=%d\n--- stdout ---\n%s\n--- stderr ---\n%s\n' % (result.returncode, result.stdout, result.stderr), encoding='utf-8')
    if restore_error:
        fail(restore_error)
    print('BUILD_EXPORT exit=%d log=%s' % (result.returncode, log_path))
    errors = [line for line in (result.stdout + '\n' + result.stderr).splitlines() if 'ERROR' in line or 'SCRIPT ERROR' in line]
    for line in errors[:20]:
        print('  ' + line)
    if result.returncode != 0 or not out_exe.is_file():
        fail('export failed (exit %d, exe exists=%s)' % (result.returncode, out_exe.is_file()))
    return errors


def list_pck(path):
    """Read the file list of the pck embedded in (or beside) an executable."""
    data = Path(path).read_bytes()
    position = len(data)
    while True:
        position = data.rfind(b'GDPC', 0, position)
        if position < 0:
            return None
        if position + 32 > len(data):
            continue
        version, major, minor, patch, flags = struct.unpack_from('<5I', data, position + 4)
        if version not in (2, 3) or major != 4:
            continue
        file_base, dir_offset = struct.unpack_from('<2Q', data, position + 24)
        for directory in (position + dir_offset, dir_offset):
            files = _read_directory(data, directory)
            if files:
                return files


def _read_directory(data, offset):
    try:
        count, = struct.unpack_from('<I', data, offset)
        if not 0 < count < 200000:
            return None
        cursor = offset + 4
        names = []
        for _ in range(count):
            length, = struct.unpack_from('<I', data, cursor)
            if length > 4096:
                return None
            name = data[cursor + 4:cursor + 4 + length].rstrip(b'\0').decode('utf-8')
            cursor += 4 + length + 8 + 8 + 16 + 4
            names.append(name)
        # Godot 4.5 stores paths relative to the project ("chapter1/..."); older packs carry "res://".
        return [name if name.startswith('res://') else 'res://' + name for name in names]
    except (struct.error, UnicodeDecodeError):
        return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--preset', choices=sorted(PRESETS), required=True)
    parser.add_argument('--stamp', default='', help='output folder name (default: date-commit)')
    parser.add_argument('--skip-import', action='store_true')
    args = parser.parse_args()
    if not GODOT.is_file():
        fail('Godot not found: ' + str(GODOT))
    preset_name, kind = PRESETS[args.preset]
    commit = git('rev-parse', '--short', 'HEAD') or 'nogit'
    dirty = bool(git('status', '--porcelain'))
    stamp = args.stamp or '%s-%s' % (datetime.date.today().strftime('%Y%m%d'), commit)
    out_dir = ROOT / '_local' / 'build' / stamp / args.preset
    out_exe = out_dir / EXE_NAME
    env = isolated_env(stamp)
    template, template_sha, verified = check_templates(kind)
    print('BUILD_TEMPLATE %s sha256=%s verified=%s' % (template, template_sha, verified))
    if not (ROOT / 'chapter1' / 'art' / 'brand' / 'icon.ico').is_file():
        print('BUILD_WARN chapter1/art/brand/icon.ico is missing: the executable keeps the Godot default icon')
    if not args.skip_import:
        import_project(env)
    out_dir.mkdir(parents=True, exist_ok=True)
    errors = export(preset_name, kind, template, out_exe, out_dir / 'export.log', env)
    files = list_pck(out_exe)
    if files is None:
        fail('could not read the pck file list from ' + str(out_exe))
    (out_dir / 'pck_files.txt').write_text('\n'.join(files) + '\n', encoding='utf-8')
    bad = [name for name in files if name.startswith(FORBIDDEN_PREFIXES) or name.endswith(FORBIDDEN_SUFFIXES)]
    record = {
        'preset': preset_name,
        'exe': str(out_exe),
        'bytes': out_exe.stat().st_size,
        'sha256': sha256(out_exe),
        'commit': commit,
        'working_tree_dirty': dirty,
        'godot_version': subprocess.run([str(GODOT), '--version'], capture_output=True, text=True).stdout.strip(),
        'template': template.name,
        'template_sha256': template_sha,
        'template_sha256_matches_record': verified,
        'pck_file_count': len(files),
        'pck_forbidden': bad,
        'export_error_lines': errors,
        'built_at': datetime.datetime.now().isoformat(timespec='seconds'),
    }
    (out_dir / 'build.json').write_text(json.dumps(record, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print('BUILD_RESULT %s bytes=%d sha256=%s pck_files=%d forbidden=%d' % (out_exe, record['bytes'], record['sha256'], len(files), len(bad)))
    for name in bad[:20]:
        print('  forbidden in pck: ' + name)
    if bad:
        fail('pck contains files that must not ship')
    return 0


if __name__ == '__main__':
    sys.exit(main())
