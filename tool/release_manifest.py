"""Fills netlify/public/download/version.json from the built release APKs (with ABI split support).

Run from the project root after `flutter build apk --split-per-abi --release`:

    python tool/release_manifest.py [--force] [--min 1] [--notes "..."]
"""
import argparse
import hashlib
import json
import os
import re
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APK_DIR = os.path.join(ROOT, 'build', 'app', 'outputs', 'flutter-apk')
APK_ARM64_SRC = os.path.join(APK_DIR, 'app-arm64-v8a-release.apk')
APK_ARM32_SRC = os.path.join(APK_DIR, 'app-armeabi-v7a-release.apk')
APK_FAT_SRC = os.path.join(APK_DIR, 'app-release.apk')

DL = os.path.join(ROOT, 'netlify', 'public', 'download')
APK_MAIN_DST = os.path.join(DL, 'app.apk')
APK_ARM64_DST = os.path.join(DL, 'app-arm64-v8a-release.apk')
APK_ARM32_DST = os.path.join(DL, 'app-armeabi-v7a-release.apk')
MANIFEST = os.path.join(DL, 'version.json')


def file_sha256_and_size(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest(), os.path.getsize(path)


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
    version_name, base_code = m.group(1), int(m.group(2))

    os.makedirs(DL, exist_ok=True)

    has_split = os.path.exists(APK_ARM64_SRC)
    if not has_split and not os.path.exists(APK_FAT_SRC):
        raise SystemExit(f'APK not found in {APK_DIR} (run: flutter build apk --split-per-abi --release)')

    old = {}
    if os.path.exists(MANIFEST):
        try:
            old = json.load(open(MANIFEST, encoding='utf-8'))
        except Exception:
            old = {}

    if has_split:
        # arm64 is the primary download. app.apk is NOT a second copy any
        # more: netlify/public/_redirects serves it from the arm64 file, so
        # a deploy uploads 25 MB less - the upload was timing out.
        shutil.copyfile(APK_ARM64_SRC, APK_ARM64_DST)
        if os.path.exists(APK_MAIN_DST):
            os.remove(APK_MAIN_DST)
        sha_arm64, size_arm64 = file_sha256_and_size(APK_ARM64_DST)

        sha_arm32 = None
        if os.path.exists(APK_ARM32_SRC):
            shutil.copyfile(APK_ARM32_SRC, APK_ARM32_DST)
            sha_arm32, _ = file_sha256_and_size(APK_ARM32_DST)

        # arm64-v8a in Gradle split gets 2000 + base_code
        server_code = 2000 + base_code

        manifest = {
            'updateEnabled': not args.disable,
            'versionCode': server_code,
            'versionName': version_name,
            'apkUrl': f'https://cineball.netlify.app/download/app.apk?v={base_code}',
            'apkUrlArm64': f'https://cineball.netlify.app/download/app-arm64-v8a-release.apk?v={base_code}',
            'apkUrlArm32': f'https://cineball.netlify.app/download/app-armeabi-v7a-release.apk?v={base_code}',
            'sha256': sha_arm64,
            'sha256Arm64': sha_arm64,
            'sha256Arm32': sha_arm32 if sha_arm32 else sha_arm64,
            'sizeBytes': size_arm64,
            'forceUpdate': bool(args.force),
            'minSupportedVersion': args.min if args.min is not None else old.get('minSupportedVersion', 1),
            'notes': args.notes if args.notes is not None else old.get('notes', ''),
        }
    else:
        shutil.copyfile(APK_FAT_SRC, APK_MAIN_DST)
        sha, size = file_sha256_and_size(APK_MAIN_DST)
        manifest = {
            'updateEnabled': not args.disable,
            'versionCode': base_code,
            'versionName': version_name,
            'apkUrl': f'https://cineball.netlify.app/download/app.apk?v={base_code}',
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
    print(f"\nAPKs copied successfully. Primary APK size: {manifest['sizeBytes'] / 1048576:.1f} MB.")


if __name__ == '__main__':
    main()
