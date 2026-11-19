"""Compare two snapshot dumps field by field.

    python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd -- --case=11:chapter1.skill.frost --dump-at=1800 --dump-out=_local/diff/a.json
    (change something, run again with --dump-out=_local/diff/b.json)
    python tools/dev/snapshot_diff.py _local/diff/a.json _local/diff/b.json [--limit 200]

Prints one line per differing leaf: `hero.hp_raw 1200→1180`. Arrays are compared by index (`enemies[3].hp_raw`);
a different length is its own line, and the extra elements are listed as added/removed. Exit code 0 when the dumps
are the same, 1 when they differ, 2 when a file cannot be read.

The field that diverged first is where the two states are first visible apart, not necessarily where the cause is:
a changed random draw, order or timer can move many fields at once, and the one listed first is just the first one met.
"""
from pathlib import Path
import argparse, json, sys


def join(path, key):
    return '%s.%s' % (path, key) if path else str(key)


def short(value, width=80):
    text = json.dumps(value, ensure_ascii=False, separators=(',', ':'))
    return text if len(text) <= width else text[:width - 1] + '…'


def diff(a, b, path, out):
    if isinstance(a, dict) and isinstance(b, dict):
        for key in a:
            if key in b:
                diff(a[key], b[key], join(path, key), out)
            else:
                out.append('%s removed (was %s)' % (join(path, key), short(a[key])))
        for key in b:
            if key not in a:
                out.append('%s added (%s)' % (join(path, key), short(b[key])))
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            out.append('%s length %d→%d' % (path or '(root)', len(a), len(b)))
        for index in range(min(len(a), len(b))):
            diff(a[index], b[index], '%s[%d]' % (path, index), out)
        for index in range(len(b), len(a)):
            out.append('%s[%d] removed (was %s)' % (path, index, short(a[index])))
        for index in range(len(a), len(b)):
            out.append('%s[%d] added (%s)' % (path, index, short(b[index])))
    elif a != b or type(a) is not type(b):
        out.append('%s %s→%s' % (path or '(root)', short(a), short(b)))


def main():
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('before')
    parser.add_argument('after')
    parser.add_argument('--limit', type=int, default=200, help='most lines printed (the count is always complete)')
    options = parser.parse_args()
    try:
        before = json.loads(Path(options.before).read_text(encoding='utf-8'))
        after = json.loads(Path(options.after).read_text(encoding='utf-8'))
    except (OSError, ValueError) as error:
        print('SNAPSHOT_DIFF cannot read: %s' % error)
        return 2
    out = []
    diff(before, after, '', out)
    for line in out[:options.limit]:
        print(line)
    if len(out) > options.limit:
        print('... %d more' % (len(out) - options.limit))
    print('SNAPSHOT_DIFF %s' % json.dumps({'differences': len(out), 'first': out[0] if out else ''}, ensure_ascii=False))
    if out:
        print('참고: 처음 갈린 필드는 원인이 아닐 수 있다(난수·순서·타이머 하나가 여러 필드를 한꺼번에 움직인다).')
    return 1 if out else 0


if __name__ == '__main__':
    sys.exit(main())
