# R8/ProGuard keep rules for the release build.
#
# Without these, R8 broke androidx FileProvider: it obfuscated the XML pull
# parser away, so FileProvider.getUriForFile threw
#   java.lang.IncompatibleClassChangeError:
#   Class 'android.content.res.XmlBlock$Parser' does not implement
#   interface '...' ... declaration of androidx.core.content.FileProvider
# which crashed the app the moment the self-updater tried to install the
# downloaded APK. Keeping FileProvider, every ContentProvider, and the
# XmlPull interfaces fixes it.

# FileProvider and any content provider must survive shrinking untouched.
-keep class androidx.core.content.FileProvider { *; }
-keep public class * extends android.content.ContentProvider { *; }

# The XML pull parser hierarchy FileProvider parses file_paths.xml with.
-keep interface org.xmlpull.v1.** { *; }
-keep class org.xmlpull.** { *; }
-keep class android.content.res.XmlResourceParser { *; }
-dontwarn org.xmlpull.v1.**

# Flutter's own engine and plugins.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# media_kit / mpv native bindings loaded by name.
-keep class com.alexmercerind.** { *; }
-keep class media.kit.** { *; }
-dontwarn media.kit.**
