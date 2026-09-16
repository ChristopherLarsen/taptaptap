#!/usr/bin/env python3
"""Run every stable golden case (argv/stdin -> stdout/stderr/exit code) against a binary.
Usage: check-goldens.py <binary> <cases-dir> [--name axe] [--version-skip]
The recorded argv[0] ("axe") is replaced by the binary; with --name, the binary name in the
expected output is substituted (for the 3f rename): only the standalone word "axe", never "AXe",
"axe-hid-..." or a path component. An "@UDID@" argv token is replaced by $TTT_GOLDEN_UDID (default:
the iPhone 17 Pro simulator used by the gate).
Since a longer tool name shifts where the renderer's 80-column word-wrap breaks a line (a text-
layout detail, not part of the parser's behavior contract these goldens exist to prove), stdout and
stderr are compared after reflowing: whitespace (including single newlines) within each blank-line-
delimited paragraph is collapsed to single spaces on both sides. Content, word order, option names,
exit codes and the stdout/stderr split all remain exact; only the column a wrap happens to land on
does not. Exit 0 only if every case matches."""
import os, re, shlex, subprocess, sys
binary, cases = sys.argv[1], sys.argv[2]
name = sys.argv[sys.argv.index('--name') + 1] if '--name' in sys.argv else 'axe'

def reflow(text):
    return '\n\n'.join(' '.join(paragraph.split()) for paragraph in re.split(r'\n\s*\n', text))

fails = 0; total = 0
for case in sorted(os.listdir(cases)):
    d = os.path.join(cases, case)
    udid = os.environ.get('TTT_GOLDEN_UDID', '77FC7DAB-191A-4A19-BC74-D4F882851A14')
    argv = [a.replace('@UDID@', udid) for a in shlex.split(open(os.path.join(d, 'argv.txt')).read())]
    if case == 'version' and '--version-skip' in sys.argv:
        continue
    stdin_path = os.path.join(d, 'stdin.txt')
    stdin = open(stdin_path, 'rb').read() if os.path.exists(stdin_path) else b''
    r = subprocess.run([binary] + argv[1:], input=stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    def expected(f):
        s = open(os.path.join(d, f), 'rb').read().decode()
        return re.sub(r'(?<![\w/.-])axe(?![\w-])', name, s) if name != 'axe' else s
    exp_out, exp_err, exp_rc = expected('stdout.txt'), expected('stderr.txt'), int(open(os.path.join(d, 'exit-code.txt')).read())
    out, err = r.stdout.decode(), r.stderr.decode()
    total += 1
    problems = []
    if r.returncode != exp_rc: problems.append(f'exit {r.returncode} != {exp_rc}')
    if reflow(out) != reflow(exp_out): problems.append('stdout differs')
    if reflow(err) != reflow(exp_err): problems.append('stderr differs')
    if problems:
        fails += 1
        print(f'FAIL {case}: {", ".join(problems)}')
        if '-v' in sys.argv:
            import difflib
            for label, a, b in (('stdout', exp_out, out), ('stderr', exp_err, err)):
                for line in difflib.unified_diff(a.splitlines(), b.splitlines(), f'expected {label}', f'actual {label}', lineterm='', n=0):
                    print('   ', line)
print(f'{total - fails}/{total} golden cases match')
sys.exit(1 if fails else 0)
