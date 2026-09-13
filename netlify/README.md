# نشر التطبيق والتحديثات (Netlify)

```
netlify/
  netlify.toml
  public/
    _headers
    download/
      index.html      صفحة التحميل
      version.json    بيانات آخر إصدار (يقرأها التطبيق عند كل تشغيل)
      app.apk         ملف التطبيق (لا يُرفع إلى git)
      logo.png        شعار التطبيق (انسخ assets/images/app_logo.png)
```

## نشر إصدار جديد (أمر واحد)

بعد أي تعديل على التطبيق:

```
python tool/release.py --notes "وصف التحديث الذي يراه المستخدم"
```

يرفع رقم الإصدار، ويبني النسخة الموقّعة، ويتحقق من أن الـAPK يحمل الرقم الجديد
والمفتاح الصحيح والرابط الصحيح، وينسخه ويكتب `version.json`.

المشروع مربوط بموقع `cineball` على Netlify، فأضف `--deploy` لينشر تلقائياً
بلا أي رفع يدوي:

```
python tool/release.py --notes "وصف التحديث" --deploy
```

لو أردت الرفع يدوياً بدلاً من ذلك: افتح تبويب Deploys في لوحة Netlify واسحب
مجلد `netlify/public` إليه.

خيارات:

| الخيار | الأثر |
|---|---|
| `--minor` / `--major` | 1.0.2 تصبح 1.1.0 أو 2.0.0 بدل 1.0.3 |
| `--version 1.4.0` | تحديد اسم الإصدار يدوياً |
| `--force` | تحديث إجباري، لا يمكن استخدام التطبيق قبله |
| `--min 5` | منع كل نسخة أقدم من 5 من العمل |
| `--disable` | إيقاف إشعار التحديث من السيرفر |
| `--dry-run` | عرض ما سيحدث دون تنفيذ |

## الخطوات يدوياً (إن أردت التحكم الكامل)

1. ارفع رقم الإصدار في `pubspec.yaml` (الرقم بعد `+` هو versionCode ويجب أن يزيد دائماً):
   `version: 1.0.1+2`
2. ابنِ التطبيق: `flutter build apk --release`
   (الناتج: `build/app/outputs/flutter-apk/app-release.apk`)
3. انسخه إلى `netlify/public/download/app.apk`.
4. احسب SHA-256 والحجم:
   - Windows: `certutil -hashfile app.apk SHA256`
   - أو من مجلد المشروع: `python tool/release_manifest.py`
5. حدّث `version.json`: `versionCode`, `versionName`, `apkUrl` (مع `?v=<versionCode>`), `sha256`, `sizeBytes`, `notes`.
6. انشر مجلد `public` على Netlify (Drag & drop، أو `netlify deploy --prod --dir=public`).

`version.json` يُرسل بترويسة `no-store` فلا يبقى مخزّناً، أما `app.apk` فيُخزّن بشكل طبيعي ورابطه ثابت مع `?v=` يتغيّر مع كل إصدار.
