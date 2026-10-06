#!/usr/bin/env python3
"""Local release regression checks. Never logs matched secret values.
This is defense in depth alongside review, not a proof of all runtime behavior.
"""
import argparse, pathlib, re, subprocess, sys, zipfile
parser = argparse.ArgumentParser()
parser.add_argument('--app', type=pathlib.Path)
parser.add_argument('--zip', type=pathlib.Path)
parser.add_argument('--history', action='store_true')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parent.parent
patterns = {
    'private key': rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----',
    'GitHub token': rb'\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b',
    'provider token': rb'\bsk-(?:proj-|ant-)?[A-Za-z0-9_-]{20,}\b',
    'AWS key': rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b',
    'credentials in URL': rb'https?://[^\s/<>"\x00]+:[^\s/<>"\x00]+@',
    'personal build path': rb'/Users/[A-Za-z0-9_.-]+/',
}
failures = []
def scan(label, data, artifact=False):
    for category, pattern in patterns.items():
        # Tooling may describe /Users as an excluded path. Artifacts may not contain it.
        if category == 'personal build path' and not artifact: continue
        if re.search(pattern, data): failures.append((label, category))

def git(*argv): return subprocess.check_output(['git', '-C', str(root), *argv])
for path in (root / 'Sources').rglob('*.swift'):
    data = path.read_bytes(); scan(str(path.relative_to(root)), data)
    # A regression in these APIs requires an explicit redesign and security review.
    forbidden = rb'\b(?:URLSession|URLRequest|NWConnection|NWListener|SecItemCopyMatching|SecItemAdd|SecItemUpdate|SecItemDelete|SecKeychain\w*|WKWebView|NSURLConnection|CFReadStreamCreateForHTTPRequest)\b'
    if re.search(forbidden, data): failures.append((str(path.relative_to(root)), 'network/keychain/web API outside local power-only policy'))

if args.app:
    for path in args.app.rglob('*'):
        if path.is_symlink(): failures.append((path.name, 'unexpected symlink in app'))
        elif path.is_file(): scan('app/' + str(path.relative_to(args.app)), path.read_bytes(), artifact=True)

if args.zip:
    with zipfile.ZipFile(args.zip) as archive:
        for entry in archive.infolist():
            path = pathlib.PurePosixPath(entry.filename)
            if '..' in path.parts or path.is_absolute(): failures.append(('archive', 'unsafe entry path'))
            if any(part in ('.git', '.env', 'work', '__MACOSX', '.DS_Store') for part in path.parts) or path.suffix.lower() in ('.p12', '.pfx', '.pem', '.key'):
                failures.append((entry.filename, 'private or unexpected archive entry'))
            if not entry.is_dir(): scan('archive/' + entry.filename, archive.read(entry), artifact=True)

if args.history:
    for line in git('rev-list', '--objects', '--all').decode().splitlines():
        oid = line.split(' ', 1)[0]
        kind = git('cat-file', '-t', oid).decode().strip()
        if kind in ('blob', 'commit', 'tag'):
            data = git('cat-file', kind, oid); scan('git object ' + oid, data)
            if kind == 'commit':
                for identity in re.findall(rb'^(?:author|committer) .* <([^>]+)>', data, re.M):
                    if not identity.endswith(b'@users.noreply.github.com'):
                        failures.append(('commit ' + oid, 'non-noreply author/committer email'))
    tracked = git('ls-files', '-z').decode().split('\0')
    for name in filter(None, tracked):
        path = pathlib.PurePosixPath(name)
        if path.suffix.lower() in ('.p12', '.pfx', '.pem', '.key') or path.name == '.env':
            failures.append((name, 'credential file tracked by Git'))

for label, category in failures: print(f'FAIL: {category}: {label}', file=sys.stderr)
if failures: sys.exit(1)
print('PASS: local-only source policy and requested artifact/history privacy checks; no matched values printed')
