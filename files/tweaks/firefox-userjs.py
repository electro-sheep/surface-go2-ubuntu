"""Put our prefs (firefox-user.js) into the user.js of Firefox's default profile, keeping the
user's own lines. Ours go in a marked block at the top, rewritten on every run; lines below it
win, so setting a pref again there overrides ours. Elsewhere, lines that repeat one of ours
exactly (a copy made by hand) are dropped.

  firefox-userjs.py install firefox-user.js   exit 2 if Firefox has no profile yet
  firefox-userjs.py check   firefox-user.js   exit 0 if the block is in place and current
"""
import configparser, os, re, sys

ROOTS = ['~/snap/firefox/common/.mozilla/firefox', '~/.mozilla/firefox']   # snap, deb
BEGIN = '// >>> surface-go2-ubuntu'
END = '// <<< surface-go2-ubuntu'
HEADER = BEGIN + ': ./install.sh tweaks rewrites this block; set a pref again below it to change it'


def default_profiles():
    """The profiles Firefox starts with: [Profile…] Default=1, and [Install…] Default= if any."""
    found = []
    for root in map(os.path.expanduser, ROOTS):
        ini = configparser.ConfigParser(interpolation=None, strict=False)
        if not ini.read(os.path.join(root, 'profiles.ini')):
            continue
        for name, sec in ini.items():
            if name.startswith('Install'):
                path = sec.get('default')
            elif name.startswith('Profile') and sec.get('default') == '1':
                path = sec.get('path')
            else:
                continue
            d = os.path.join(root, path or '')
            if path and os.path.isdir(d) and d not in found:
                found.append(d)
    return found


def merged(ours, text):
    mine = {line.strip() for line in ours if line.strip()}
    keep, inside = [], False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith(BEGIN):
            inside = True
        elif inside:
            inside = not s.startswith(END)
        elif s not in mine:
            keep.append(line)
    rest = re.sub(r'\n{3,}', '\n\n', '\n'.join(keep)).strip('\n')
    return '\n'.join([HEADER, *ours, END]) + '\n' + ('\n' + rest + '\n' if rest else '')


mode, src = sys.argv[1:]
ours = open(src).read().strip('\n').splitlines()
profiles = default_profiles()
if not profiles:
    sys.exit(2)   # Firefox hasn't been opened yet
status = 0
for d in profiles:
    f = os.path.join(d, 'user.js')
    shown = f.replace(os.path.expanduser('~'), '~', 1)
    cur = open(f).read() if os.path.exists(f) else ''
    new = merged(ours, cur)
    if cur == new:
        print(f'{shown} already up to date')
    elif mode == 'check':
        print(f'{shown} is missing our prefs or has an old copy of them')
        status = 1
    else:
        with open(f + '.tmp', 'w') as out:
            out.write(new)
        os.replace(f + '.tmp', f)
        print(f'{shown} updated')
sys.exit(status)
