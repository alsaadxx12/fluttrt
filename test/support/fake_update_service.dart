import 'dart:io';

import 'package:youtube_downloader/features/update/data/app_update_info.dart';
import 'package:youtube_downloader/features/update/data/update_service.dart';

/// Stands in for the network and the platform channel in tests.
class FakeUpdateService extends UpdateService {
  FakeUpdateService(this.info, {this.current = 3});

  /// What the server would report; null means "no manifest / no update".
  final AppUpdateInfo? info;

  /// The versionCode pretending to be installed.
  final int current;

  @override
  bool get isSupported => true;

  @override
  Future<InstalledVersion> getCurrentVersion() async => InstalledVersion(
        versionCode: current,
        versionName: '1.0.1',
        packageName: 'com.antigravity.yt.youtube_downloader',
      );

  @override
  Future<AppUpdateInfo?> checkForUpdate({int? currentVersionCode}) async =>
      (info != null && info!.isNewerThan(currentVersionCode ?? current)) ? info : null;

  @override
  Future<File?> downloadedApk(AppUpdateInfo info) async => null; // nothing downloaded yet

  @override
  Future<bool> canInstallPackages() async => true;
}

AppUpdateInfo updateInfo({int code = 4, bool force = false, int min = 0}) => AppUpdateInfo(
      versionCode: code,
      versionName: '1.0.2',
      apkUrl: 'https://cineball.netlify.app/download/app.apk?v=$code',
      forceUpdate: force,
      minSupportedVersion: min,
      notes: 'تجربة التحديث',
      sizeBytes: 30039571,
    );
