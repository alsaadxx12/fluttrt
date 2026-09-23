package com.antigravity.yt.youtube_downloader

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.UiModeManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.provider.Settings
import android.speech.RecognizerIntent
import androidx.core.app.NotificationCompat
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

        /// The casting notification: one id, one channel, one broadcast
        /// action its buttons send back to the activity.
        private const val CAST_NOTIFICATION_ID = 7301
        private const val CAST_CHANNEL = "cast"
        private const val CAST_ACTION = "com.antigravity.yt.youtube_downloader.CAST_ACTION"
    }

    /// The channel to Dart for the casting notification, kept so a button
    /// press on the notification can be sent back over it.
    private var castChannel: MethodChannel? = null
    private var castReceiver: BroadcastReceiver? = null

    /// Puts up, or updates, the line in the shade for a film playing on
    /// another screen: its title, the screen's name, and play/pause and
    /// stop buttons. Ongoing, so it cannot be swiped away while the film
    /// plays; silent, so an update never buzzes.
    private fun showCastNotification(title: String, where: String, playing: Boolean) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CAST_CHANNEL, "البث إلى الشاشة", NotificationManager.IMPORTANCE_LOW)
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)

        fun button(name: String, icon: Int, label: String): NotificationCompat.Action {
            val intent = Intent(CAST_ACTION).setPackage(packageName).putExtra("action", name)
            val pending = PendingIntent.getBroadcast(this, name.hashCode(), intent, flags)
            return NotificationCompat.Action(icon, label, pending)
        }

        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            flags
        )
        val notification = NotificationCompat.Builder(this, CAST_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText("يُعرض على $where")
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(
                if (playing) button("pause", android.R.drawable.ic_media_pause, "إيقاف مؤقت")
                else button("play", android.R.drawable.ic_media_play, "تشغيل")
            )
            .addAction(button("stop", android.R.drawable.ic_menu_close_clear_cancel, "إيقاف البث"))
            .build()
        manager.notify(CAST_NOTIFICATION_ID, notification)
    }

    private fun hideCastNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(CAST_NOTIFICATION_ID)
    }

    /// Listens for the notification's buttons and hands each press to Dart.
    private fun listenForCastButtons() {
        if (castReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val action = intent?.getStringExtra("action") ?: return
                castChannel?.invokeMethod("action", action)
            }
        }
        val filter = IntentFilter(CAST_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
        castReceiver = receiver
    }

    override fun onDestroy() {
        // The app is gone: so is the film's line in the shade, and the ear
        // for its buttons.
        try { hideCastNotification() } catch (_: Exception) {}
        castReceiver?.let { try { unregisterReceiver(it) } catch (_: Exception) {} }
        castReceiver = null
        super.onDestroy()
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

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        useHighestRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        // The window can be handed back at the system's own rate after the
        // app has been away, so the choice is made again here.
        useHighestRefreshRate()
    }

    /// Asks the display for its fastest mode at the resolution already in use.
    ///
    /// A 90 Hz or 120 Hz phone does not give an app those frames by default:
    /// the window stays at 60 Hz unless it names a display mode, and Flutter
    /// does not name one. Every scroll on this app was therefore drawn at 60
    /// frames a second on a screen capable of twice that, which is exactly
    /// what reads as "not smooth" however cheap each frame is to build.
    ///
    /// Only modes of the same size are considered, so this never changes the
    /// resolution; if the display has a single mode the call does nothing.
    private fun useHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val screen = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                getDisplay()
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            } ?: return

            val current = screen.mode
            val best = screen.supportedModes
                .filter {
                    it.physicalWidth == current.physicalWidth &&
                        it.physicalHeight == current.physicalHeight
                }
                .maxByOrNull { it.refreshRate } ?: return

            if (best.modeId == current.modeId) return
            if (best.refreshRate <= current.refreshRate + 0.1f) return
            window.attributes = window.attributes.apply { preferredDisplayModeId = best.modeId }
        } catch (_: Exception) {
            // Decoration only: a display that will not answer keeps its rate.
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The notification for a film playing on another screen.
        val cast = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cineball/cast_notification")
        castChannel = cast
        cast.setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    try {
                        listenForCastButtons()
                        showCastNotification(
                            call.argument<String>("title") ?: "",
                            call.argument<String>("where") ?: "",
                            call.argument<Boolean>("playing") ?: true
                        )
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("notification", e.message, null)
                    }
                }
                "hide" -> {
                    try { hideCastNotification() } catch (_: Exception) {}
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
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
