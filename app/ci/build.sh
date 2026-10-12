#!/usr/bin/env bash
# Сборка debug-APK. Запускается из GitHub Actions. Правьте здесь, а не в build-apk.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

npm install
npx cap add android

# Разрешения (камера, вибрация) и только вертикальная ориентация
M=android/app/src/main/AndroidManifest.xml
sed -i 's#<application#<uses-permission android:name="android.permission.CAMERA" />\n    <uses-permission android:name="android.permission.VIBRATE" />\n    <application#' "$M"
sed -i 's#<activity#<activity android:screenOrientation="portrait"#' "$M"
sed -i 's#<application#<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />\n    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />\n    <application#' "$M"
grep -n "screenOrientation\|CAMERA\|VIBRATE\|NOTIFICATIONS\|EXACT_ALARM" "$M"

# Иконка и заставка из папки assets
BG='#0C5026'
npx capacitor-assets generate --android --assetPath assets \
  --iconBackgroundColor "$BG" --iconBackgroundColorDark "$BG" \
  --splashBackgroundColor "$BG" --splashBackgroundColorDark "$BG"

# Системная заставка Android без логотипа: остаётся только анимированная
R=android/app/src/main/res
cat > "$R/drawable/splash_icon_empty.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#00000000" />
    <size android:width="1dp" android:height="1dp" />
</shape>
XML
sed -i "s|<item name=\"android:background\">@drawable/splash</item>|<item name=\"android:background\">@drawable/splash</item>\n        <item name=\"windowSplashScreenBackground\">$BG</item>\n        <item name=\"windowSplashScreenAnimatedIcon\">@drawable/splash_icon_empty</item>|" "$R/values/styles.xml"

# --- номер сборки и репозиторий для проверки обновлений ---
sed -i "s|var FT_BUILD=0;|var FT_BUILD=${GITHUB_RUN_NUMBER:-0};|; s|var FT_REPO='';|var FT_REPO='${GITHUB_REPOSITORY:-}';|" www/index.html

# --- постоянный ключ подписи: без него обновление поверх установленного приложения не встанет ---
mkdir -p "$HOME/.android"
cp ci/debug.keystore "$HOME/.android/debug.keystore"

npx cap sync android

if [ "${SKIP_GRADLE:-}" != "1" ]; then
  (cd android && ./gradlew assembleDebug)
fi
