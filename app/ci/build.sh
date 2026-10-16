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

# Обычная (не адаптивная) иконка: на Xiaomi/MIUI показывается как есть, во всю площадь, без обрезки слоёв
R0=android/app/src/main/res
rm -f "$R0"/mipmap-anydpi-v26/ic_launcher.xml "$R0"/mipmap-anydpi-v26/ic_launcher_round.xml
rm -f "$R0"/mipmap-*/ic_launcher_foreground.png "$R0"/mipmap-*/ic_launcher_background.png
for D in ci/icons/*/; do
  N=$(basename "$D")
  mkdir -p "$R0/$N"
  cp "$D/ic_launcher.png" "$D/ic_launcher_round.png" "$R0/$N/"
done

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

# --- версия приложения растёт с каждой сборкой ---
BN="${GITHUB_RUN_NUMBER:-1}"
sed -i "s/versionCode [0-9]*/versionCode $BN/; s/versionName \"[^\"]*\"/versionName \"1.0.$BN\"/" android/app/build.gradle
grep -n "versionCode\|versionName" android/app/build.gradle || true

# --- явно прописываем постоянный ключ подписи в gradle (путь относительно android/app) ---
python3 - <<'PY'
import re,sys
p='android/app/build.gradle'
t=open(p).read()
if 'ci/debug.keystore' in t:
    sys.exit(0)
cfg="""    signingConfigs {
        debug {
            storeFile file('../../ci/debug.keystore')
            storePassword 'android'
            keyAlias 'androiddebugkey'
            keyPassword 'android'
        }
    }
"""
m=re.search(r'^android \{\n',t,re.M)
if not m: sys.exit('build.gradle: блок android не найден')
t=t[:m.end()]+cfg+t[m.end():]
m2=re.search(r'^    buildTypes \{\n',t,re.M)
if not m2: sys.exit('build.gradle: блок buildTypes не найден')
t=t[:m2.end()]+"        debug {\n            signingConfig signingConfigs.debug\n        }\n"+t[m2.end():]
open(p,'w').write(t)
PY
grep -n "debug.keystore\|signingConfig" android/app/build.gradle

if [ "${SKIP_GRADLE:-}" != "1" ]; then
  (cd android && ./gradlew assembleDebug)
  # --- отпечаток подписи: у всех сборок он должен быть одинаковым ---
  echo "Key file in repo:"; keytool -list -keystore ci/debug.keystore -storepass android 2>/dev/null | grep -i "SHA-256\|SHA256" || true
  echo "APK signature:"; keytool -printcert -jarfile android/app/build/outputs/apk/debug/app-debug.apk | grep -i "SHA256\|Owner" || true
fi
