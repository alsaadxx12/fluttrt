import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_downloader/features/update/data/app_update_info.dart';
import 'package:youtube_downloader/features/update/data/update_service.dart';
import 'package:youtube_downloader/features/update/presentation/update_controller.dart';
import 'package:youtube_downloader/features/update/update_config.dart';

void main() {
  final sample = <String, dynamic>{
    'versionCode': 12,
    'versionName': '1.2.0',
    'apkUrl': 'https://cineball.netlify.app/download/app.apk?v=12',
    'forceUpdate': false,
    'minSupportedVersion': 10,
    'notes': 'تحسين الأداء',
    'sha256': 'ab' * 32,
    'updateEnabled': true,
    'sizeBytes': 41943040,
  };

  test('manifest parses, with string numbers and booleans too', () {
    final info = AppUpdateInfo.fromJson(sample);
    expect(info.versionCode, 12);
    expect(info.minSupportedVersion, 10);
    expect(info.sha256, 'ab' * 32);
    expect(info.sizeBytes, 41943040);
    final loose = AppUpdateInfo.fromJson({'versionCode': '13', 'apkUrl': 'https://cineball.netlify.app/a.apk', 'forceUpdate': 'true'});
    expect(loose.versionCode, 13);
    expect(loose.forceUpdate, isTrue);
    expect(loose.minSupportedVersion, 0);
    expect(loose.updateEnabled, isTrue);
  });

  test('invalid manifests are rejected', () {
    expect(() => AppUpdateInfo.fromJson({'apkUrl': 'https://x/a.apk'}), throwsFormatException);
    expect(() => AppUpdateInfo.fromJson({'versionCode': 1}), throwsFormatException);
    expect(() => AppUpdateInfo.fromJson({'versionCode': 1, 'apkUrl': 'https://x/a.apk', 'sha256': 'nothex'}), throwsFormatException);
  });

  test('newer / forced / disabled decisions', () {
    final info = AppUpdateInfo.fromJson(sample);
    expect(info.isNewerThan(11), isTrue);
    expect(info.isNewerThan(12), isFalse);
    expect(info.mustUpdate(11), isFalse);
    expect(info.mustUpdate(9), isTrue, reason: 'below minSupportedVersion');
    expect(AppUpdateInfo.fromJson({...sample, 'forceUpdate': true}).mustUpdate(11), isTrue);
    expect(AppUpdateInfo.fromJson({...sample, 'updateEnabled': false}).isNewerThan(1), isFalse, reason: 'server switched prompts off');
  });

  test('only https links on the allowed host are accepted', () {
    const hosts = ['cineball.netlify.app'];
    expect(AppUpdateInfo.fromJson(sample).apkUrlAllowed(hosts), isTrue);
    expect(AppUpdateInfo.fromJson({...sample, 'apkUrl': 'http://cineball.netlify.app/app.apk'}).apkUrlAllowed(hosts), isFalse);
    expect(AppUpdateInfo.fromJson({...sample, 'apkUrl': 'https://evil.com/app.apk'}).apkUrlAllowed(hosts), isFalse);
    expect(AppUpdateInfo.fromJson({...sample, 'apkUrl': 'https://cineball.netlify.app.evil.com/app.apk'}).apkUrlAllowed(hosts), isFalse);
  });

  test('state: prompt and forced flags', () {
    final info = AppUpdateInfo.fromJson({...sample, 'minSupportedVersion': 12});
    const current = InstalledVersion(versionCode: 11, versionName: '1.1.0', packageName: 'com.antigravity.yt.youtube_downloader');
    final s = UpdateState(status: UpdateStatus.updateAvailable, info: info, current: current);
    expect(s.shouldPrompt, isTrue);
    expect(s.isForced, isTrue, reason: '11 < minSupportedVersion 12');
    expect(s.copyWith(dismissed: true).shouldPrompt, isTrue, reason: 'a forced update cannot be put off');
    final optional = UpdateState(status: UpdateStatus.updateAvailable, info: AppUpdateInfo.fromJson(sample), current: current);
    expect(optional.isForced, isFalse);
    expect(optional.copyWith(dismissed: true).shouldPrompt, isFalse);
    expect(const UpdateState(status: UpdateStatus.noUpdate).shouldPrompt, isFalse);
  });

  test('the configured update URL and allowed hosts agree', () {
    // Guards the mistake of moving the site without updating both: an APK
    // link on a host that is not allowed would be refused after download.
    final url = Uri.parse(UpdateConfig.versionUrl);
    expect(url.scheme, 'https', reason: 'updates must be fetched over https');
    expect(UpdateConfig.allowedHosts, contains(url.host),
        reason: 'version.json host must also be allowed to serve the APK');
    expect(UpdateConfig.allowedHosts, isNotEmpty);
    expect(UpdateConfig.packageName, 'com.antigravity.yt.youtube_downloader',
        reason: 'the package name must never change, or updates install as a new app');
  });
}
