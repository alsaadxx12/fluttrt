import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_update_info.dart';
import '../data/update_service.dart';

enum UpdateStatus { loading, noUpdate, updateAvailable, downloading, downloadCompleted, installing, error }

class UpdateState {
  final UpdateStatus status;
  final InstalledVersion? current;
  final AppUpdateInfo? info;

  /// 0..1 while downloading.
  final double progress;
  final int received;
  final int? total;
  final File? apk;
  final UpdateFailure? failure;

  /// True while the user still needs to grant "install unknown apps".
  final bool needsInstallPermission;

  /// The user tapped "later" on an optional update this session.
  final bool dismissed;

  const UpdateState({
    this.status = UpdateStatus.loading,
    this.current,
    this.info,
    this.progress = 0,
    this.received = 0,
    this.total,
    this.apk,
    this.failure,
    this.needsInstallPermission = false,
    this.dismissed = false,
  });

  /// A newer build is waiting, whether or not the user put it off. This is
  /// what the drawer's update button and the about page read.
  bool get hasUpdate => info != null && status != UpdateStatus.noUpdate && status != UpdateStatus.loading;

  /// The user must update before using the app.
  bool get isForced => info != null && current != null && info!.mustUpdate(current!.versionCode);

  /// Something to show: a newer build the user hasn't put off.
  bool get shouldPrompt =>
      info != null && status != UpdateStatus.noUpdate && status != UpdateStatus.loading && (!dismissed || isForced);

  UpdateState copyWith({
    UpdateStatus? status,
    InstalledVersion? current,
    AppUpdateInfo? info,
    double? progress,
    int? received,
    int? total,
    File? apk,
    UpdateFailure? failure,
    bool clearFailure = false,
    bool? needsInstallPermission,
    bool? dismissed,
  }) =>
      UpdateState(
        status: status ?? this.status,
        current: current ?? this.current,
        info: info ?? this.info,
        progress: progress ?? this.progress,
        received: received ?? this.received,
        total: total ?? this.total,
        apk: apk ?? this.apk,
        failure: clearFailure ? null : (failure ?? this.failure),
        needsInstallPermission: needsInstallPermission ?? this.needsInstallPermission,
        dismissed: dismissed ?? this.dismissed,
      );
}

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

/// The build that is installed right now, read from the package itself, so
/// screens never show a hard-coded version.
final installedVersionProvider =
    FutureProvider<InstalledVersion>((ref) => ref.watch(updateServiceProvider).getCurrentVersion());

final updateControllerProvider = StateNotifierProvider<UpdateController, UpdateState>(
  (ref) => UpdateController(ref.watch(updateServiceProvider)),
);

/// Drives the whole flow: check -> prompt -> download -> permission ->
/// install. Only the failed step is retried; a check that fails never blocks
/// the app (a forced update can't be known without a manifest).
class UpdateController extends StateNotifier<UpdateState> {
  UpdateController(this._service) : super(const UpdateState());

  final UpdateService _service;
  CancelToken? _cancel;

  /// Runs in the background after start-up; the UI is never held up.
  Future<void> checkForUpdate() async {
    if (!_service.isSupported) {
      state = state.copyWith(status: UpdateStatus.noUpdate);
      return;
    }
    state = state.copyWith(status: UpdateStatus.loading, clearFailure: true);
    try {
      final current = await _service.getCurrentVersion();
      final info = await _service.checkForUpdate(currentVersionCode: current.versionCode);
      if (info == null) {
        state = state.copyWith(status: UpdateStatus.noUpdate, current: current);
        return;
      }
      // An APK already downloaded and verified for this build: straight to install.
      final apk = await _service.downloadedApk(info);
      state = state.copyWith(
        status: apk != null ? UpdateStatus.downloadCompleted : UpdateStatus.updateAvailable,
        current: current,
        info: info,
        apk: apk,
        progress: apk != null ? 1 : 0,
      );
    } on UpdateException catch (e) {
      debugPrint('[UPDATE] check failed: $e');
      // No manifest: the app carries on as it is.
      state = state.copyWith(status: UpdateStatus.noUpdate, failure: e.failure);
    } catch (e) {
      debugPrint('[UPDATE] check failed: $e');
      state = state.copyWith(status: UpdateStatus.noUpdate);
    }
  }

  /// "Later" on an optional update.
  void dismiss() {
    if (!state.isForced) state = state.copyWith(dismissed: true);
  }

  /// Bring the prompt back after the user put it off (the drawer's update
  /// button, or the about page).
  void showPrompt() => state = state.copyWith(dismissed: false);

  /// A check the user asked for: re-read the manifest, then show whatever
  /// it found.
  Future<void> checkNow() async {
    await checkForUpdate();
    showPrompt();
  }


  /// "Update now": download (or resume), verify, then install.
  Future<void> downloadAndInstall() async {
    final info = state.info;
    if (info == null) return;
    if (state.status == UpdateStatus.downloading) return;

    File apk;
    final ready = state.apk == null ? null : await _service.downloadedApk(info);
    if (ready != null) {
      apk = ready;
    } else {
      state = state.copyWith(status: UpdateStatus.downloading, progress: 0, received: 0, clearFailure: true);
      _cancel = CancelToken();
      try {
        apk = await _service.downloadUpdate(
          info,
          cancelToken: _cancel,
          onProgress: (p, received, total) {
            if (state.status == UpdateStatus.downloading) {
              state = state.copyWith(progress: p, received: received, total: total);
            }
          },
        );
      } on UpdateException catch (e) {
        state = state.copyWith(status: UpdateStatus.error, failure: e.failure);
        return;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          state = state.copyWith(status: UpdateStatus.updateAvailable);
        } else {
          state = state.copyWith(status: UpdateStatus.error, failure: UpdateFailure.downloadFailed);
        }
        return;
      } catch (e) {
        debugPrint('[UPDATE] download failed: $e');
        state = state.copyWith(status: UpdateStatus.error, failure: UpdateFailure.downloadFailed);
        return;
      }
      state = state.copyWith(status: UpdateStatus.downloadCompleted, apk: apk, progress: 1);
    }
    await install();
  }

  /// Starts the package installer for the downloaded APK, asking for the
  /// install permission first when needed.
  Future<void> install() async {
    final apk = state.apk;
    if (apk == null) return;
    if (!await _service.canInstallPackages()) {
      state = state.copyWith(status: UpdateStatus.downloadCompleted, needsInstallPermission: true);
      return;
    }
    state = state.copyWith(status: UpdateStatus.installing, needsInstallPermission: false, clearFailure: true);
    try {
      await _service.installApk(apk);
      // The installer takes over from here; if the user cancels it we are
      // still on the old build and the file is ready for another try.
      state = state.copyWith(status: UpdateStatus.downloadCompleted);
    } on UpdateException catch (e) {
      state = state.copyWith(
        status: e.failure == UpdateFailure.installPermissionDenied ? UpdateStatus.downloadCompleted : UpdateStatus.error,
        failure: e.failure,
        needsInstallPermission: e.failure == UpdateFailure.installPermissionDenied,
      );
    }
  }

  /// Opens the system page to allow installs; [install] is retried when the
  /// app returns (see UpdateGate).
  Future<void> requestInstallPermission() async {
    try {
      await _service.requestInstallPermission();
    } on UpdateException catch (e) {
      state = state.copyWith(status: UpdateStatus.error, failure: e.failure);
    }
  }

  /// Back from the settings page: carry on if the permission is there now.
  Future<void> onResumed() async {
    if (state.needsInstallPermission && state.apk != null && await _service.canInstallPackages()) {
      await install();
    }
  }

  /// After an error: try the failed step again.
  Future<void> retry() async {
    if (state.info == null) return;
    state = state.copyWith(status: state.apk == null ? UpdateStatus.updateAvailable : UpdateStatus.downloadCompleted, clearFailure: true);
    await downloadAndInstall();
  }

  void cancelDownload() => _cancel?.cancel();
}
