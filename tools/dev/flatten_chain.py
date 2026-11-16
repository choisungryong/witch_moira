"""Inline a GDScript inheritance chain into one script without changing behaviour.

    python tools/dev/flatten_chain.py chapter1/view/ui51/chapter_hud_quality51.gd chapter1/view/hud/chapter_hud.gd

The chain is followed through `extends "res://..."` down to the engine base class.
Every script's members are emitted base-first in their original order. A method
that a later script overrides is kept under a suffixed name (sync -> sync__q40),
and each `super.method(` / `super(` call is rewritten to the name of the nearest
earlier definition. Dispatch is therefore identical by construction: an ordinary
call still reaches the most derived method, a super call reaches exactly the
method it reached before.

The result is one flat file with layered methods. It is a safe starting point for
simplifying by hand, not the simplification itself.
"""
from pathlib import Path
import re, sys

ROOT = Path(__file__).resolve().parents[2]
STARTER = re.compile(r'^(?:static\s+func|func|var|const|signal|enum|class|class_name|extends|@)\b')
FUNC = re.compile(r'^(static\s+)?func\s+([A-Za-z_0-9]+)\s*\(')
MEMBER = re.compile(r'^(?:@\w+(?:\([^)]*\))?\s+)*(var|const|signal|enum|class)\s+([A-Za-z_0-9]+)')
EXTENDS = re.compile(r'^extends\s+"res://([^"]+)"')
SUPER = re.compile(r'\bsuper(?:\.([A-Za-z_0-9]+))?\(')


def read_lines(rel):
    return (ROOT / rel).read_text(encoding='utf-8-sig').replace('\r\n', '\n').split('\n')


def retab(lines):
    """Convert space indentation to tabs using the smallest indent as the unit."""
    widths = [len(l) - len(l.lstrip(' ')) for l in lines if l.startswith(' ')]
    if not widths:
        return lines
    unit = min(widths)
    out = []
    for line in lines:
        if line.startswith(' '):
            n = len(line) - len(line.lstrip(' '))
            if n % unit:
                raise SystemExit('Irregular indentation: ' + repr(line))
            line = '\t' * (n // unit) + line.lstrip(' ')
        out.append(line)
    return out


def chain_of(leaf):
    chain = []
    rel = leaf
    while rel:
        lines = retab(read_lines(rel))
        first = next(l for l in lines if l.strip() and not l.startswith('#'))
        if not first.startswith('extends'):
            raise SystemExit(rel + ' does not start with extends')
        chain.append((rel, lines, first))
        match = EXTENDS.match(first)
        rel = match.group(1) if match else None
    chain.reverse()
    return chain


def blocks_of(lines):
    blocks, current = [], []
    for line in lines:
        if STARTER.match(line) and current:
            blocks.append(current)
            current = []
        current.append(line)
    if current:
        blocks.append(current)
    return blocks


def tag_of(rel, used):
    stem = Path(rel).stem
    match = re.search(r'quality(\w+)$', stem)
    tag = 'q' + match.group(1) if match else stem.split('_')[0]
    while tag in used:
        tag += 'x'
    used.add(tag)
    return tag


def flatten(leaf, out):
    chain = chain_of(leaf)
    used = set()
    levels = []
    for rel, lines, first in chain:
        levels.append({'rel': rel, 'tag': tag_of(rel, used), 'blocks': blocks_of(lines), 'extends': first})
    definitions = {}
    members = {}
    for index, level in enumerate(levels):
        for block in level['blocks']:
            func = FUNC.match(block[0])
            if func:
                definitions.setdefault(func.group(2), []).append(index)
                continue
            member = MEMBER.match(block[0])
            if member:
                name = member.group(2)
                if name in members:
                    raise SystemExit('Member %s declared in both %s and %s' % (name, members[name], level['rel']))
                members[name] = level['rel']

    def name_at(method, index):
        owners = definitions[method]
        return method if index == owners[-1] else '%s__%s' % (method, levels[index]['tag'])

    def nearest_below(method, index):
        owners = [i for i in definitions.get(method, []) if i < index]
        return owners[-1] if owners else None

    output = [levels[0]['extends'], '## Flattened by tools/dev/flatten_chain.py from ' + leaf + '.',
              '## Methods named x__tag are the earlier layers of x; calls between them were super calls.', '']
    renamed = 0
    rewired = 0
    for index, level in enumerate(levels):
        output.append('# ---- ' + level['rel'] + ' ----')
        for block in level['blocks']:
            head = block[0]
            if head.startswith('extends'):
                block = [l for l in block[1:]]
                while block and not block[0].strip():
                    block = block[1:]
                if not block:
                    continue
                output.extend(block)
                continue
            func = FUNC.match(head)
            if func:
                method = func.group(2)
                new_name = name_at(method, index)
                if new_name != method:
                    renamed += 1
                    head = head[:func.start(2)] + new_name + head[func.end(2):]

                def replace(match, method=method, index=index):
                    nonlocal rewired
                    target = match.group(1) or method
                    owner = nearest_below(target, index)
                    if owner is None:
                        return match.group(0)
                    rewired += 1
                    return name_at(target, owner) + '('

                block = [head] + [SUPER.sub(replace, line) for line in block[1:]]
                # A one-line function keeps its body on the header line.
                if ':' in head and head.rstrip()[-1] != ':':
                    colon = head.index(')')
                    block[0] = head[:colon] + SUPER.sub(replace, head[colon:])
            output.extend(block)
        if output[-1].strip():
            output.append('')
    while len(output) > 1 and not output[-1].strip() and not output[-2].strip():
        output.pop()
    target = ROOT / out
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text('\n'.join(output), encoding='utf-8', newline='\n')
    print('FLATTEN %s -> %s: %d scripts, %d lines, %d layered methods, %d super calls rewired' % (leaf, out, len(levels), len(output), renamed, rewired))


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    flatten(sys.argv[1].replace('\\', '/'), sys.argv[2].replace('\\', '/'))
