"""One command to ship an update to everyone who has the app.

    python tool/release.py --notes "ما الجديد في هذا التحديث"

It does, in order:
  1. raises the version in pubspec.yaml (patch by default: 1.0.2+4 -> 1.0.3+5),
  2. builds the signed release APK,
  3. checks the APK really carries the new versionCode and the release key,
  4. copies it to netlify/public/download/ and rewrites version.json
     (sha256, size, apkUrl with ?v=<versionCode>, notes),
  5. tells you to deploy (or deploys for you with --deploy).

Options:
  --notes "..."   what the update dialog shows the user
  --minor         1.0.2+4 -> 1.1.0+5        (default is patch)
  --major         1.0.2+4 -> 2.0.0+5
  --version X.Y.Z set the name explicitly; the build number always +1
  --force         every user must update before using the app
  --min N         refuse to run below versionCode N
  --disable       publish with updates switched off (no prompt at all)
  --deploy        run netlify deploy --prod when the CLI is installed
  --dry-run       show what would happen, change nothing
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUBSPEC = os.path.join(ROOT, 'pubspec.yaml')
APK_DIR = os.path.join(ROOT, 'build', 'app', 'outputs', 'flutter-apk')
APK_ARM64_SRC = os.path.join(APK_DIR, 'app-arm64-v8a-release.apk')
APK_SRC = os.path.join(APK_DIR, 'app-release.apk')
DL = os.path.join(ROOT, 'netlify', 'public', 'download')
MANIFEST = os.path.join(DL, 'version.json')
VERSION_RE = re.compile(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$', re.M)


def read_version():
    text = open(PUBSPEC, encoding='utf-8').read()
    m = VERSION_RE.search(text)
    if not m:
        raise SystemExit('pubspec.yaml: the version line must look like "version: 1.2.0+12"')
    major, minor, patch, code = (int(g) for g in m.groups())
    return text, m, (major, minor, patch), code


def bump(args):
    text, m, (major, minor, patch), code = read_version()
    if args.version:
        if not re.fullmatch(r'\d+\.\d+\.\d+', args.version):
            raise SystemExit('--version must look like 1.2.0')
        name = args.version
    elif args.major:
        name = f'{major + 1}.0.0'
    elif args.minor:
        name = f'{major}.{minor + 1}.0'
    else:
        name = f'{major}.{minor}.{patch + 1}'
    new_code = code + 1  # must always grow, or Android refuses the update
    line = f'version: {name}+{new_code}'
    print(f'version: {major}.{minor}.{patch}+{code}  ->  {name}+{new_code}')
    if not args.dry_run:
        open(PUBSPEC, 'w', encoding='utf-8', newline='').write(text[:m.start()] + line + text[m.end():])
    return name, new_code


def run(cmd, why):
    print(f'\n== {why}\n$ {" ".join(cmd)}')
    if subprocess.call(cmd, cwd=ROOT, shell=(os.name == 'nt')) != 0:
        raise SystemExit(f'failed: {why}')


def apk_facts(path):
    """versionCode/versionName from the APK itself, when aapt is available."""
    sdk = os.environ.get('LOCALAPPDATA', '')
    tools = os.path.join(sdk, 'Android', 'Sdk', 'build-tools')
    aapt = None
    if os.path.isdir(tools):
        for d in sorted(os.listdir(tools), reverse=True):
            candidate = os.path.join(tools, d, 'aapt.exe' if os.name == 'nt' else 'aapt')
            if os.path.exists(candidate):
                aapt = candidate
                break
    if not aapt:
        return None
    out = subprocess.run([aapt, 'dump', 'badging', path], capture_output=True, text=True).stdout
    m = re.search(r"versionCode='(\d+)'\s+versionName='([^']*)'", out)
    return (int(m.group(1)), m.group(2)) if m else None


def signed_by_release_key(path):
    """The APK is signed by something other than the Android debug key."""
    out = subprocess.run(['keytool', '-printcert', '-jarfile', path],
                         capture_output=True, text=True, shell=(os.name == 'nt')).stdout
    if 'Owner:' not in out:
        return None  # keytool unavailable; skip the check
    return 'CN=Android Debug' not in out


def update_url_inside(path):
    """The update host compiled into the app, read back out of the APK."""
    host = json.load(open(MANIFEST, encoding='utf-8'))['apkUrl'].split('/')[2].split('?')[0]
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            if name.endswith('libapp.so') and host.encode() in z.read(name):
                return host
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--notes', default=None, help='what the update dialog shows')
    ap.add_argument('--minor', action='store_true')
    ap.add_argument('--major', action='store_true')
    ap.add_argument('--version', default=None)
    ap.add_argument('--force', action='store_true')
    ap.add_argument('--min', type=int, default=None)
    ap.add_argument('--disable', action='store_true')
    ap.add_argument('--deploy', action='store_true')
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    name, code = bump(args)
    if args.dry_run:
        print('\ndry run: nothing was built, copied or published.')
        return

    # The TMDB token is a compile-time constant inside the app (see
    # lib/features/trailers/tmdb_config.dart), so it is present in every
    # build. It is deliberately NOT passed as --dart-define: a release built
    # that way was found to ship WITHOUT the token in libapp.so, which hid the
    # trailers section for users, while the plain build carries it correctly.
    build_cmd = ['flutter', 'build', 'apk', '--split-per-abi', '--release']
    # Force the Dart snapshot to be rebuilt so the APK always matches the
    # current source, without a full `flutter clean` (which fails on Windows
    # when another process holds a file in build/). Removing just the compiled
    # kernel/snapshot dir is enough and rarely locked; ignore any error.
    import shutil
    for sub in ('.dart_tool/flutter_build', 'build/app/intermediates/flutter'):
        p = os.path.join(ROOT, *sub.split('/'))
        if os.path.isdir(p):
            print(f'== refresh Dart build cache\n$ rm -r {sub}')
            shutil.rmtree(p, ignore_errors=True)
    run(build_cmd, 'build the signed release APKs (split-per-abi)')

    target_apk = APK_ARM64_SRC if os.path.exists(APK_ARM64_SRC) else APK_SRC
    facts = apk_facts(target_apk)
    if facts:
        got_code, got_name = facts
        print(f'\nAPK reports versionCode={got_code} versionName={got_name}')
        if got_code != code and (got_code % 1000) != (code % 1000):
            raise SystemExit(f'the APK carries versionCode {got_code}, not {code}. '
                             'The build did not pick up the new version; run it again.')
    signed = signed_by_release_key(target_apk)
    if signed is False:
        raise SystemExit('this APK is signed with the DEBUG key. Set up android/key.properties, '
                         'or users cannot install it over their copy.')

    manifest_args = [sys.executable, os.path.join(ROOT, 'tool', 'release_manifest.py')]
    if args.notes is not None:
        manifest_args += ['--notes', args.notes]
    if args.force:
        manifest_args += ['--force']
    if args.min is not None:
        manifest_args += ['--min', str(args.min)]
    if args.disable:
        manifest_args += ['--disable']
    run(manifest_args, 'copy the APK and write version.json')

    host = update_url_inside(os.path.join(DL, 'app.apk'))
    if host:
        print(f'the app looks for updates at: {host}  (matches version.json)')
    else:
        print('WARNING: the update host in version.json was not found inside the APK. '
              'Check lib/features/update/update_config.dart before publishing.')

    if args.deploy and shutil.which('netlify'):
        run(['netlify', 'deploy', '--prod', '--dir', os.path.join('netlify', 'public')], 'publish to Netlify')
        print(f'\nDone. Users on older builds will see {name} ({code}) within seconds of opening the app.')
    else:
        if args.deploy:
            print('\nnetlify CLI not found (npm install -g netlify-cli). Publish by hand instead:')
        print(f"""
Ready to publish {name} ({code}).
Last step: upload the folder  netlify/public  to Netlify
(Deploys tab -> drag the folder in, or: netlify deploy --prod --dir=netlify/public)

Users on an older build get the prompt within seconds of opening the app.""")


if __name__ == '__main__':
    main()
