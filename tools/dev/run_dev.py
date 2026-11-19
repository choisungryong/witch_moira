"""Dev loop: import the project when needed, then run the game from the repository root.

    python tools/dev/run_dev.py -- --chapter1-start
    python tools/dev/run_dev.py --resolution 1920x1080 -- --chapter1-start --chapter1-pilot --chapter1-profile-off
    python tools/dev/run_dev.py --import-only

The repository root is the Godot project. docs/, tools/, art-archive/ and _local/
carry a .gdignore, so Godot never scans them. Saves go to the project's own user
directory (%APPDATA%/WitchMoira). The import step and any run with --chapter1-profile-off
use an isolated APPDATA (_local/appdata/dev/); a run without that argument is the user's own play.
A run with --chapter1-profile-off also has a time limit (godot_guard.py: 20 min, MOIRA_GODOT_TIMEOUT_S to change, 0 = none) and is
ended with its whole process tree after it; the user's own play never has a limit.
"""
from pathlib import Path
import argparse, os, subprocess, sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from isolated_env import isolated_env
import godot_guard

ROOT = Path(__file__).resolve().parents[2]
GODOT = Path(os.environ.get('MOIRA_GODOT', 'C:/Project/rea-tools/godot-4.5.1/Godot_v4.5.1-stable_win64_console.exe'))
ENTRY = 'res://chapter1/ChapterOne.tscn'


def import_project(passes=1):
    """Assets extracted from GLB files appear on the first pass and are imported on the second."""
    for index in range(passes):
        result = subprocess.run([str(GODOT), '--headless', '--path', str(ROOT), '--import'], capture_output=True, text=True, encoding='utf-8', errors='replace', env=isolated_env('dev'))
        print('DEV_IMPORT pass=%d exit=%d' % (index + 1, result.returncode))
        if result.returncode != 0:
            print(result.stdout[-2000:])
            print(result.stderr[-2000:])
            raise SystemExit(result.returncode)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--import-only', '--sync-only', dest='import_only', action='store_true', help='import assets and stop')
    parser.add_argument('--resolution', default='')
    parser.add_argument('game_args', nargs='*')
    args = parser.parse_args()
    if not GODOT.is_file():
        raise SystemExit('Godot not found: ' + str(GODOT))
    fresh = not (ROOT / '.godot' / 'imported').is_dir()
    import_project(2 if fresh else 1)
    if args.import_only:
        return 0
    command = [str(GODOT), '--path', str(ROOT)]
    if args.resolution:
        command += ['--resolution', args.resolution]
    command += [ENTRY, '--'] + args.game_args
    isolated = '--chapter1-profile-off' in args.game_args
    env = isolated_env('dev') if isolated else None
    limit = godot_guard.resolve_timeout(['--path'], None) if isolated else 0
    code, _, timed_out = godot_guard.run_guarded(command, limit, env=env)
    if timed_out:
        print('GODOT_TIMEOUT ended the process tree after %d s (MOIRA_GODOT_TIMEOUT_S changes the limit)' % limit, file=sys.stderr)
    return code


if __name__ == '__main__':
    sys.exit(main())
