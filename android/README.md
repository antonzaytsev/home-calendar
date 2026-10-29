# Home Calendar for Android

A small APK that opens `http://192.168.0.30:9000/` full-screen: no tabs, address
bar, or app toolbar. The screen stays awake while the app is visible. Calendar
settings and automatic updates work as they do in the browser. Supports Android
6 and newer, including Android 11. The tablet must be able to reach the server.

## Install

1. Copy `.work/android/home-calendar.apk` from this project to the tablet.
2. Open the APK in the tablet's Files app. If prompted, allow that app to
   **Install unknown apps**, then install.
3. Open **Home Calendar** from the launcher.

With USB debugging enabled, you can instead run from this project:

```bash
adb install -r .work/android/home-calendar.apk
```

Swipe from a screen edge to temporarily reveal Android's Home/Back controls.
If the server cannot be reached when opening the page, check Wi-Fi and tap Retry.
This app does not start automatically after reboot or lock the tablet into kiosk
mode. Web content continues to come from the existing server.

## Rebuild

Requires a JDK (17 or newer recommended), Android SDK platform 35, Android build
tools 35.0.0, and `zip`. No Gradle or external app libraries are needed.

On this Mac, Android command-line tools were installed with Homebrew:

```bash
brew install --cask android-commandlinetools
export JAVA_HOME=/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home
sdkmanager 'platforms;android-35' 'build-tools;35.0.0'
bash android/build.sh
```

The script detects the installed Homebrew JDK and SDK on this Mac. Elsewhere,
set `JAVA_HOME` and `ANDROID_HOME` to your JDK and SDK directories before building.
It compiles against API 35 and targets API 32 for this privately installed app.

All app sources and icon assets are in `android/`. Generated build files, the
installable APK, and the local signing key stay under `.work/android/` in this
project. Each build gets its own intermediate directory. Keep
`.work/android/home-calendar.keystore` to sign future updates with the same key;
back it up if you want to rebuild on another machine. Its password is `android`:
this is a local installation key, not a Play Store publishing credential.

To change the server, update `CALENDAR_URL` and the URL check in
`src/local/homecalendar/MainActivity.java`, and the permitted host in
`res/xml/network_security_config.xml`, then rebuild.
