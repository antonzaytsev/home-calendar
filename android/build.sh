#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
    echo 'Usage: bash android/build.sh' >&2
    exit 1
fi

android_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$android_dir/.." && pwd)"
output_dir="$project_dir/.work/android"

if [[ -z "${JAVA_HOME:-}" && -d /opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home ]]; then
    export JAVA_HOME=/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home
fi
if [[ -n "${JAVA_HOME:-}" ]]; then
    export PATH="$JAVA_HOME/bin:$PATH"
fi

sdk_dir="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$sdk_dir" ]]; then
    for candidate in /opt/homebrew/share/android-commandlinetools "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
        if [[ -d "$candidate/platforms/android-35" ]]; then
            sdk_dir="$candidate"
            break
        fi
    done
fi
tools_dir="$sdk_dir/build-tools/35.0.0"
android_jar="$sdk_dir/platforms/android-35/android.jar"
for tool in aapt2 d8 zipalign apksigner; do
    if [[ ! -x "$tools_dir/$tool" ]]; then
        echo "Missing $tool. Install Android SDK build-tools;35.0.0 and platforms;android-35. See android/README.md." >&2
        exit 1
    fi
done
if [[ ! -f "$android_jar" ]]; then
    echo "Missing SDK platform: $android_jar" >&2
    exit 1
fi
for tool in javac java keytool jar zip; do
    command -v "$tool" >/dev/null || { echo "Missing build command: $tool" >&2; exit 1; }
done

mkdir -p "$output_dir"
build_dir="$(mktemp -d "$output_dir/build.XXXXXX")"
mkdir -p "$build_dir/generated" "$build_dir/classes" "$build_dir/dex"

"$tools_dir/aapt2" compile --dir "$android_dir/res" -o "$build_dir/resources.zip"
"$tools_dir/aapt2" link -o "$build_dir/unsigned.apk" \
    --manifest "$android_dir/AndroidManifest.xml" -I "$android_jar" \
    --java "$build_dir/generated" "$build_dir/resources.zip"
javac -encoding UTF-8 -source 8 -target 8 -Xlint:-options \
    -bootclasspath "$android_jar" -d "$build_dir/classes" \
    "$android_dir/src/local/homecalendar/MainActivity.java" \
    "$build_dir/generated/local/homecalendar/R.java"
jar cf "$build_dir/classes.jar" -C "$build_dir/classes" .
"$tools_dir/d8" --release --min-api 23 --lib "$android_jar" \
    --output "$build_dir/dex" "$build_dir/classes.jar"
(
    cd -- "$build_dir/dex"
    zip -q -j "$build_dir/unsigned.apk" classes.dex
)
"$tools_dir/zipalign" -f -p 4 "$build_dir/unsigned.apk" "$build_dir/aligned.apk"

keystore="$output_dir/home-calendar.keystore"
if [[ ! -f "$keystore" ]]; then
    (
        umask 077
        keytool -genkeypair -noprompt -keystore "$keystore" -storetype PKCS12 \
            -storepass android -keypass android -alias home-calendar \
            -keyalg RSA -keysize 2048 -validity 10000 \
            -dname 'CN=Home Calendar, O=Local, C=US'
    )
fi
"$tools_dir/apksigner" sign --ks "$keystore" --ks-key-alias home-calendar \
    --ks-pass pass:android --key-pass pass:android \
    --out "$build_dir/home-calendar.apk" "$build_dir/aligned.apk"
"$tools_dir/apksigner" verify --verbose "$build_dir/home-calendar.apk"
"$tools_dir/zipalign" -c -p 4 "$build_dir/home-calendar.apk"
cp "$build_dir/home-calendar.apk" "$output_dir/home-calendar.apk"
echo "APK ready: $output_dir/home-calendar.apk"
