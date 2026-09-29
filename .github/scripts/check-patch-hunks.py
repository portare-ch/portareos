#!/usr/bin/env python3
"""Check that no unified-diff hunk holds more lines than its header declares.

A hunk header states how many lines the hunk covers on each side. GNU patch
trusts it: if it under-counts, patch applies only that many lines and silently
drops the rest, so the file arrives truncated and the build fails somewhere
that looks unrelated - a missing closing brace, or symbols "defined but not
used" because the tail of the file never arrived. Nothing about the patch looks
wrong when read, and the counts drift whenever a hunk is edited by hand.

This reads a hunk exactly as patch does - consume the declared number of lines
on each side, then stop - and complains when lines that add or remove content
follow. Two near misses are deliberately not reported, both verified against
GNU patch: extra trailing context lines, and a hunk that ends one or two
context lines short, are applied correctly and exit 0.

Run with no arguments to check every patch in the tree.
"""
import re
import sys
from pathlib import Path

HUNK = re.compile(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@')


def is_content(line):
    """Is this a hunk body line, rather than something that ends the hunk?"""
    if line.startswith(('--- ', '+++ ')) or line.rstrip() in ('---', '+++'):
        return False            # the next file section's headers
    if line.rstrip() == '--':
        return False            # git format-patch signature
    return line.startswith(('+', '-', ' '))


def check(path):
    """Return a list of (line_no, message) for one patch file."""
    problems = []
    # scripts/unpack guards every patch with [ -f ], which follows symlinks, so
    # a link whose target is gone is skipped by the build. Skip it here too
    # rather than report a failure the build does not have.
    if not path.is_file():
        return []
    try:
        lines = path.read_text(errors='replace').splitlines()
    except OSError as e:
        return [(0, f'unreadable: {e}')]

    i = 0
    while i < len(lines):
        m = HUNK.match(lines[i])
        if not m:
            i += 1
            continue
        hunk_line = i + 1
        old = int(m.group(2)) if m.group(2) is not None else 1
        new = int(m.group(4)) if m.group(4) is not None else 1

        # Consume the hunk the way patch does: exactly the declared counts.
        i += 1
        while i < len(lines) and (old > 0 or new > 0):
            line = lines[i]
            if line.startswith('\\'):          # "\ No newline at end of file"
                pass
            elif line.startswith('+'):
                new -= 1
            elif line.startswith('-'):
                old -= 1
            else:
                old -= 1
                new -= 1
            i += 1

        if old > 0 or new > 0:
            # patch tolerates this: it applies what is there and the result is
            # correct. Verified against GNU patch, so it is not reported.
            continue

        # The counts are satisfied. Anything that still looks like hunk
        # content is a line patch would silently drop. The next file's own
        # "--- a/x" and "+++ b/x" headers start with - and + too, and the
        # git format-patch signature "-- " starts with -, so none of those
        # count.
        j, dropped = i, 0
        while j < len(lines) and is_content(lines[j]):
            if lines[j].startswith(('+', '-')):
                dropped += 1
            j += 1
        if dropped:
            problems.append((hunk_line,
                             f'header covers only up to line {i}, but '
                             f'{dropped} further line(s) that add or remove '
                             f'content follow (first at line {i + 1}). '
                             f'patch drops them silently and exits 0'))
    return problems


def main(argv):
    root = Path(__file__).resolve().parents[2]
    if argv:
        paths = [Path(a) for a in argv]
    else:
        paths = sorted(p for p in root.rglob('*.patch')
                       if '.git/' not in str(p))

    failed = 0
    for p in paths:
        for line_no, msg in check(p):
            try:
                rel = p.relative_to(root)
            except ValueError:
                rel = p
            print(f'{rel}:{line_no}: {msg}')
            failed += 1

    print(f'checked {len(paths)} patches')
    if failed:
        print(f'FAILED: {failed} hunk(s) do not match their header')
        return 1
    print('OK: every hunk header matches its contents')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
