#!/bin/bash
# ==========================================
# CINEBALL - Quick macOS Installer Script
# ==========================================

echo "🚀 بدء تثبيت CINEBALL على جهاز الماك..."

# 1. الانتقال إلى مجلد المشروع
cd "$(dirname "$0")"

# 2. التأكد من توفر Flutter
if ! command -v flutter &> /dev/null; then
    echo "❌ تنبيه: Flutter غير مثبت على هذا الجهاز."
    echo "يرجى تثبيت Flutter أولاً أو استخدام نسخة الـ DMG الجاهزة."
    exit 1
fi

echo "📦 جلب الحزم والمكتبات..."
flutter pub get

echo "🔨 بناء التطبيق لنسخة الماك (Release)..."
flutter build macos --release

APP_PATH="build/macos/Build/Products/Release/CINEBALL.app"

if [ -d "$APP_PATH" ]; then
    echo "📂 نقل التطبيق إلى مجلد التطبيقات (/Applications)..."
    rm -rf /Applications/CINEBALL.app
    cp -R "$APP_PATH" /Applications/
    
    echo "✅ تم تثبيت التطبيق بنجاح داخل /Applications!"
    echo "🎉 جارٍ تشغيل CINEBALL..."
    open /Applications/CINEBALL.app
else
    echo "❌ حدث خطأ أثناء البناء، تحقق من مخرجات Flutter."
fi
