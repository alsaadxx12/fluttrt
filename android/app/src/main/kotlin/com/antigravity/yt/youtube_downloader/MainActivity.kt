package com.antigravity.yt.youtube_downloader

import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.provider.Settings
import android.speech.RecognizerIntent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    /// The pending voice-search call, answered when the recogniser returns.
    private var voiceResult: MethodChannel.Result? = null

    companion object {
        private const val VOICE_REQUEST = 4210
    }

    /// Hands back whatever the system's speech recogniser heard.
    ///
    /// Using the platform recogniser rather than recording audio ourselves
    /// means the app needs no microphone permission of its own, and a remote
    /// with a microphone button works the way its owner already expects.
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == VOICE_REQUEST) {
            val heard = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
            voiceResult?.success(heard)
            voiceResult = null
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Self-update outside Google Play: install permission, free space and
        // handing a downloaded APK to the system package installer.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cineball/updater").setMethodCallHandler { call, result ->
            when (call.method) {
                "startVoiceSearch" -> {
                    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                        .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                        .putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ar")
                        .putExtra(RecognizerIntent.EXTRA_PROMPT, call.argument<String>("prompt") ?: "تحدث الآن")
                    if (intent.resolveActivity(packageManager) == null) {
                        result.success(null) // no recogniser on this device
                    } else {
                        voiceResult?.success(null) // abandon any earlier call
                        voiceResult = result
                        try {
                            startActivityForResult(intent, VOICE_REQUEST)
                        } catch (e: Exception) {
                            voiceResult = null
                            result.success(null)
                        }
                    }
                }
                // A television, so the interface can suit a screen watched
                // from across a room and driven by a remote.
                "isTv" -> {
                    val ui = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                    val leanback = packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
                    val television = ui.currentModeType == android.content.res.Configuration.UI_MODE_TYPE_TELEVISION
                    result.success(leanback || television)
                }
                "canRequestPackageInstalls" -> result.success(
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()
                )
                "openInstallPermissionSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                        } catch (e: Exception) {
                            try {
                                startActivity(
                                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                            } catch (e2: Exception) {
                                startActivity(
                                    Intent(Settings.ACTION_SECURITY_SETTINGS)
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                            }
                        }
                    }
                    result.success(null)
                }
                "freeSpace" -> {
                    val path = call.argument<String>("path") ?: filesDir.absolutePath
                    result.success(try { StatFs(path).availableBytes } catch (e: Exception) { -1L })
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    val file = if (path != null) File(path) else null
                    if (file == null || !file.exists()) {
                        result.error("missing", "APK file not found", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        val resInfoList = packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
                        for (resolveInfo in resInfoList) {
                            try {
                                grantUriPermission(resolveInfo.activityInfo.packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            } catch (_: Exception) {}
                        }
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("installer", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
