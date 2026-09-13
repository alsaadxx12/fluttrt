"""Fills netlify/public/download/version.json from the built release APK.

Run from the project root after `flutter build apk --release`:

    python tool/release_manifest.py [--force] [--min 1] [--notes "..."]

It copies the APK to netlify/public/download/app.apk, computes its SHA-256
and size, and reads versionCode/versionName from pubspec.yaml.
"""
import argparse
import hashlib
import json
import os
import re
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APK_SRC = os.path.join(ROOT, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk')
DL = os.path.join(ROOT, 'netlify', 'public', 'download')
APK_DST = os.path.join(DL, 'app.apk')
MANIFEST = os.path.join(DL, 'version.json')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--force', action='store_true', help='forceUpdate = true')
    ap.add_argument('--min', type=int, default=None, help='minSupportedVersion')
    ap.add_argument('--notes', default=None)
    ap.add_argument('--disable', action='store_true', help='updateEnabled = false')
    args = ap.parse_args()

    pub = open(os.path.join(ROOT, 'pubspec.yaml'), encoding='utf-8').read()
    m = re.search(r'^version:\s*([\d.]+)\+(\d+)', pub, re.M)
    if not m:
        raise SystemExit('pubspec.yaml: version must look like 1.2.0+12')
    version_name, version_code = m.group(1), int(m.group(2))

    if not os.path.exists(APK_SRC):
        raise SystemExit(f'APK not found: {APK_SRC} (run: flutter build apk --release)')
    os.makedirs(DL, exist_ok=True)
    shutil.copyfile(APK_SRC, APK_DST)

    h = hashlib.sha256()
    with open(APK_DST, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    sha, size = h.hexdigest(), os.path.getsize(APK_DST)

    old = {}
    if os.path.exists(MANIFEST):
        try:
            old = json.load(open(MANIFEST, encoding='utf-8'))
        except Exception:
            old = {}
    if old.get('versionCode') == version_code and old.get('sha256') != sha:
        print(f'WARNING: versionCode {version_code} was already published with a different APK. '
              'Raise the version in pubspec.yaml (an update needs a bigger versionCode).')

    base = old.get('apkUrl', 'https://cineball.netlify.app/download/app.apk').split('?')[0]
    manifest = {
        'updateEnabled': not args.disable,
        'versionCode': version_code,
        'versionName': version_name,
        'apkUrl': f'{base}?v={version_code}',
        'sha256': sha,
        'sizeBytes': size,
        'forceUpdate': bool(args.force),
        'minSupportedVersion': args.min if args.min is not None else old.get('minSupportedVersion', 1),
        'notes': args.notes if args.notes is not None else old.get('notes', ''),
    }
    with open(MANIFEST, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    print(f'\nAPK copied to {APK_DST} ({size / 1048576:.1f} MB). Now deploy netlify/public.')


if __name__ == '__main__':
    main()
