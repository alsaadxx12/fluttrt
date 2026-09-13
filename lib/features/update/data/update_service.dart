import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../update_config.dart';
import 'app_update_info.dart';

/// The build that is installed right now.
class InstalledVersion {
  final int versionCode;
  final String versionName;
  final String packageName;
  const InstalledVersion({required this.versionCode, required this.versionName, required this.packageName});
}

/// Why an update step failed; the UI turns these into messages.
enum UpdateFailure {
  noInternet,
  manifestUnavailable,
  manifestInvalid,
  downloadFailed,
  notEnoughSpace,
  checksumMismatch,
  installPermissionDenied,
  installerFailed,
}

class UpdateException implements Exception {
  final UpdateFailure failure;
  final Object? cause;
  const UpdateException(this.failure, [this.cause]);
  @override
  String toString() => 'UpdateException($failure${cause == null ? '' : ': $cause'})';
}

/// Self-update outside Google Play: reads version.json, downloads the APK
/// (with progress, resume and a checksum), and hands it to Android's
/// package installer through a small native channel.
class UpdateService {
  UpdateService({Dio? dio, MethodChannel? channel})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 30),
              headers: const {'User-Agent': 'CINEBALL-updater'},
            )),
        _channel = channel ?? const MethodChannel('cineball/updater');

  final Dio _dio;
  final MethodChannel _channel;

  /// Self-update only makes sense where APKs can be installed.
  bool get isSupported => Platform.isAndroid;

  // ------------------------------------------------------------ version

  Future<InstalledVersion> getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return InstalledVersion(
      versionCode: int.tryParse(info.buildNumber) ?? 0,
      versionName: info.version,
      packageName: info.packageName,
    );
  }

  // -------------------------------------------------------------- check

  /// The manifest, when it describes a newer build that the server wants
  /// shown and whose APK link is allowed; null when the app is up to date
  /// or updates are switched off. Throws [UpdateException] when the check
  /// itself could not be done.
  Future<AppUpdateInfo?> checkForUpdate({int? currentVersionCode}) async {
    final current = currentVersionCode ?? (await getCurrentVersion()).versionCode;
    final url = Uri.parse(UpdateConfig.versionUrl);
    if (url.scheme != 'https') throw const UpdateException(UpdateFailure.manifestInvalid, 'version url must be https');

    Response<String> res;
    try {
      res = await _dio.get<String>(
        // A cache-buster on top of the server's no-store header.
        url.replace(queryParameters: {...url.queryParameters, 't': '${DateTime.now().millisecondsSinceEpoch}'}).toString(),
        options: Options(
          responseType: ResponseType.plain,
          headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      throw UpdateException(_isOffline(e) ? UpdateFailure.noInternet : UpdateFailure.manifestUnavailable, e);
    }
    if (res.statusCode != 200 || (res.data ?? '').isEmpty) {
      throw UpdateException(UpdateFailure.manifestUnavailable, 'HTTP ${res.statusCode}');
    }

    final AppUpdateInfo info;
    try {
      final decoded = jsonDecode(res.data!);
      if (decoded is! Map<String, dynamic>) throw const FormatException('not an object');
      info = AppUpdateInfo.fromJson(decoded);
    } on FormatException catch (e) {
      throw UpdateException(UpdateFailure.manifestInvalid, e);
    }

    if (!info.apkUrlAllowed(UpdateConfig.allowedHosts)) {
      throw UpdateException(UpdateFailure.manifestInvalid, 'apkUrl not on an allowed host: ${info.apkUrl}');
    }
    return info.isNewerThan(current) ? info : null;
  }

  static bool _isOffline(DioException e) =>
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.error is SocketException;

  // ----------------------------------------------------------- download

  Future<Directory> _updatesDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}updates');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Where the APK for [info] is kept (one file per versionCode).
  Future<File> apkFileFor(AppUpdateInfo info) async =>
      File('${(await _updatesDir()).path}${Platform.pathSeparator}update-${info.versionCode}.apk');

  /// The APK for [info] when it is already downloaded and verified, else
  /// null. Keeps disk access out of the controller.
  Future<File?> downloadedApk(AppUpdateInfo info) async {
    final f = await apkFileFor(info);
    return await f.exists() ? f : null;
  }

  /// Downloads the APK, reporting [onProgress] from 0.0 to 1.0. A partial
  /// file from an earlier attempt is resumed with a Range request. Older
  /// downloads are removed first. When [info.sha256] is set the finished
  /// file is verified and deleted on mismatch. Returns the verified file.
  Future<File> downloadUpdate(
    AppUpdateInfo info, {
    void Function(double progress, int received, int? total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!info.apkUrlAllowed(UpdateConfig.allowedHosts)) {
      throw const UpdateException(UpdateFailure.downloadFailed, 'apkUrl not allowed');
    }
    final dir = await _updatesDir();
    final file = await apkFileFor(info);
    final part = File('${file.path}.part');

    // Room to spare: the old copies of other versions go first.
    await for (final f in dir.list()) {
      if (f is File && f.path != file.path && f.path != part.path) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }

    // Already there and good.
    if (await file.exists()) {
      if (info.sha256 == null || await _sha256Of(file) == info.sha256) {
        onProgress?.call(1, await file.length(), await file.length());
        return file;
      }
      await file.delete();
    }

    var start = await part.exists() ? await part.length() : 0;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final res = await _dio.get<ResponseBody>(
          info.apkUrl,
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: const Duration(minutes: 5),
            headers: start > 0 ? {'Range': 'bytes=$start-'} : null,
            validateStatus: (s) => s != null && s >= 200 && s < 300,
          ),
        );
        final resumed = res.statusCode == 206 && start > 0;
        if (!resumed) start = 0; // server sent the whole file again
        final total = _totalLength(res, start);
        if (total != null) await _ensureSpace(dir, total - start);

        final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
        var received = start;
        try {
          await for (final chunk in res.data!.stream) {
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(total == null ? 0 : (received / total).clamp(0.0, 1.0), received, total);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (total != null && received != total) {
          start = received; // connection dropped mid-way: resume
          throw const UpdateException(UpdateFailure.downloadFailed, 'incomplete');
        }

        if (info.sha256 != null) {
          final got = await _sha256Of(part);
          if (got != info.sha256) {
            await part.delete();
            throw UpdateException(UpdateFailure.checksumMismatch, 'expected ${info.sha256}, got $got');
          }
        }
        await part.rename(file.path);
        onProgress?.call(1, received, received);
        return file;
      } on UpdateException catch (e) {
        if (e.failure != UpdateFailure.downloadFailed || attempt == 2) rethrow;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        if (attempt == 2) {
          throw UpdateException(_isOffline(e) ? UpdateFailure.noInternet : UpdateFailure.downloadFailed, e);
        }
        start = await part.exists() ? await part.length() : 0;
      } on FileSystemException catch (e) {
        throw UpdateException(UpdateFailure.notEnoughSpace, e);
      }
      await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
    }
    throw const UpdateException(UpdateFailure.downloadFailed);
  }

  static int? _totalLength(Response<ResponseBody> res, int start) {
    final range = res.headers.value('content-range'); // bytes a-b/total
    if (range != null) {
      final total = int.tryParse(range.split('/').last.trim());
      if (total != null) return total;
    }
    final len = int.tryParse(res.headers.value(Headers.contentLengthHeader) ?? '');
    return len == null ? null : len + start;
  }

  Future<void> _ensureSpace(Directory dir, int needed) async {
    try {
      final free = await _channel.invokeMethod<int>('freeSpace', {'path': dir.path});
      if (free != null && free < needed + 20 * 1024 * 1024) {
        throw const UpdateException(UpdateFailure.notEnoughSpace);
      }
    } on MissingPluginException {
      // not Android: no check
    } on PlatformException {
      // can't tell: try anyway
    }
  }

  static Future<String> _sha256Of(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  // ------------------------------------------------------------ install

  /// Whether Android lets this app start installs ("install unknown apps").
  Future<bool> canInstallPackages() async {
    try {
      return await _channel.invokeMethod<bool>('canRequestPackageInstalls') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the system page where the user allows this app to install
  /// packages. Returns once the page is opened; call [canInstallPackages]
  /// again when the app comes back.
  Future<void> requestInstallPermission() async {
    try {
      await _channel.invokeMethod<void>('openInstallPermissionSettings');
    } on MissingPluginException {
      throw const UpdateException(UpdateFailure.installPermissionDenied, 'not Android');
    }
  }

  /// Hands the verified APK to the package installer.
  Future<void> installApk(File apk) async {
    if (!await apk.exists()) throw const UpdateException(UpdateFailure.installerFailed, 'file missing');
    if (!await canInstallPackages()) throw const UpdateException(UpdateFailure.installPermissionDenied);
    try {
      await _channel.invokeMethod<void>('installApk', {'path': apk.path});
    } on PlatformException catch (e) {
      throw UpdateException(UpdateFailure.installerFailed, e);
    } on MissingPluginException catch (e) {
      throw UpdateException(UpdateFailure.installerFailed, e);
    }
  }
}
