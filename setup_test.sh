#!/bin/bash
set -euo pipefail
MCDIR="$HOME/Documents/MCSEHS"
LAUNCHER_DIR="$MCDIR/ATLauncher"
NATIVES_DIR="$MCDIR/lwjgl-arm64-natives"

install_java() {
  local JAVA_DIR="$MCDIR/Java$1"
  [ -d "$JAVA_DIR" ] && return
  local ARCH
  [[ "$(uname -m)" == "arm64" ]] && ARCH="aarch64" || ARCH="x64"
  # The line below makes it so Java 8 is always x64, because MC doesnt support ARM with Java 8 on older versions. It automatically installs rosetta on ARM macs for compatibility with x64 Java 8
  [[ "$1" == "8" ]] && {
    ARCH="x64"
    softwareupdate --install-rosetta --agree-to-license 2>/dev/null || true
  }
  osascript -e "display dialog \"Installing Java $1...\nThis one-time process takes a moment.\" buttons {\"OK\"} default button \"OK\" with title \"Java Installer\"" &
  local DIALOG=$!
  mkdir -p "$JAVA_DIR" #Also creates MCDIR if it doesn't exist
  curl -fsSL -o /tmp/java-corretto.tar.gz "https://corretto.aws/downloads/latest/amazon-corretto-${1}-${ARCH}-macos-jdk.tar.gz"
  tar -xzf /tmp/java-corretto.tar.gz -C "$JAVA_DIR" --strip-components=1
  rm /tmp/java-corretto.tar.gz
  kill $DIALOG 2>/dev/null
}

# ATLauncher doesn't bundle ARM natives for LWJGL 1.17-1.18.2, so we have to do it ourselves. Only do this on ARM Macs, x86 can use the bundled x64 natives just fine.
install_lwjgl_arm_natives() {
  [[ "$(uname -m)" != "arm64" || -f "$NATIVES_DIR/liblwjgl.dylib" ]] && return # check for x86 mac so leave, otherwise also check if missing liblwgjl
  rm -rf "$NATIVES_DIR"
  mkdir -p "$NATIVES_DIR"
  local BASE="https://repo1.maven.org/maven2/org/lwjgl"
  local VER="3.3.1" #3.3.3, but 3.3.1 is what prism has
  # These are the modules 1.18.2 actually loads. Each jar is a zip containing .dylib files. STB, JEMALLOC, TINYFD ARE OPTIONAL
  for module in lwjgl lwjgl-glfw lwjgl-openal lwjgl-opengl lwjgl-stb lwjgl-jemalloc lwjgl-tinyfd; do
    curl -fsSL -o /tmp/lwjgl-native.jar \
      "${BASE}/${module}/${VER}/${module}-${VER}-natives-macos-arm64.jar"
    unzip -q -o -j /tmp/lwjgl-native.jar "*.dylib" -d "$NATIVES_DIR"
    rm /tmp/lwjgl-native.jar
  done
}
##################################### DO NOT QUOTIZE CAT FILE INSERTIONS NO 'FOO', ONLY FOO
# Minecraft enforces LWJGL x86_64 binaries even with arm support + Java arm64 17 on 1.17-1.18.2, the LWJGL loader overrides this but its broken. Do not use rosetta for 1.17-1.18.2 as its emulated performance
install_launcher() {
  [[ -f "$LAUNCHER_DIR/ATLauncher.jar" && -f "$LAUNCHER_DIR/configs/ATLauncher.json" ]] && return
  mkdir -p "$LAUNCHER_DIR/configs" #Also creates LAUNCHER_DIR if it doesn't exist
  curl -fsSL -o "$LAUNCHER_DIR/ATLauncher.jar" "$(curl -s https://api.github.com/repos/ATLauncher/ATLauncher/releases/latest | grep -o 'https://[^"]*\.jar')"
  cat >"$LAUNCHER_DIR/configs/ATLauncher.json" <<SETTINGS
{
  "firstTimeRun": false,
  "selectedTabOnStartup": 2,
  "useJavaProvidedByMinecraft": false,
  "usingCustomJavaPath": true,
  "javaPath": "${MCDIR}/JavaWrapper/Contents/Home",
  "keepLauncherOpen": true,
  "enableConsole": false,
  "useRecycleBin": true,
  "maximumMemory": 4096,
  "enableAnalytics": false,
  "enableAutomaticBackupAfterLaunch": true,
  "backupMode": "NORMAL",
  "defaultInstanceSorting": "BY_LAST_PLAYED",
  "theme": "com.atlauncher.themes.OneDark",
  "enableArmSupport": true
}
SETTINGS
}

# Writes a thin Java shim that ATLauncher calls for every instance launch.
# The shim reads instance.json to find the required Java version, then exec's
# into the correct Corretto — leaving zero memory/CPU overhead while playing.
create_wrapper() {
  local bin="$MCDIR/JavaWrapper/Contents/Home/bin"
  mkdir -p "$bin"

  cat >"$bin/java" <<'WRAPPER' # quoted as of now
#!/bin/bash
JAVA_VER=8
# default version if nothing is found, 8 for older modpacks that might not have a updated instance.json with majorVersion field
for arg in "$@"; do
  [[ "$arg" == *"/ATLauncher/instances/"* ]] || continue
  instance="${arg#*/ATLauncher/instances/}"
  json="$MCDIR/ATLauncher/instances/${instance%%/*}/instance.json"
  JAVA_VER=$(grep '"majorVersion"' "$json" | tr -dc '0-9')
  break
done

# 1.17-1.18.x: LWJGL 3.2.1 ships only x86_64 macOS natives. On arm64, prepend our
# LWJGL 3.3.3 arm64 dylibs via java.library.path so the JVM finds them first.
# 1.19+ ships natives-macos-arm64 in its own jar, so no override needed there.
# You only need library path

EXTRA_ARGS=()
if [[ "$(uname -m)" == "arm64" && "$JAVA_VER" == "17" ]]; then
  NATIVES="$MCDIR/lwjgl-arm64-natives"
  if [[ -f "$NATIVES/liblwjgl.dylib" ]]; then
    # Only prepend java.library.path so JVM finds our ARM64 dylibs first
    EXTRA_ARGS=("-Djava.library.path=$NATIVES")
  fi
fi

exec "$MCDIR/Java${JAVA_VER}/Contents/Home/bin/java" "$@" "${EXTRA_ARGS[@]}"
WRAPPER

  chmod +x "$bin/java"
}

while true; do
  ACTION=$(osascript -e 'button returned of (display dialog "Welcome to Minecraft @ SEHS\nClick Launch to launch ATLauncher for minecraft.\nNEW UPDATE: Click Run Diagnostic ONCE." buttons {"Info", "Run Diagnostic", "Launch"} default button "Launch" with title "SEHS Minecraft")')
  case "$ACTION" in
  "Info")
    osascript -e 'display dialog "ATLauncher lets you create and manage Minecraft instances.\n\nGetting started:\n• Sign in via Accounts tab with your Microsoft account\n• Go to Instances and click Add Instance\n• Pick a version or modpack and click Install\n• Hit Play when done\n\nEach instance is separate, great for different modpacks or versions. When using a version, you can install individual mods to it, depending on the modloader/version" buttons {"Back"} with title "Info"'
    ;;
  "Run Diagnostic")
    rm -rf "$MCDIR/Java*"
    rm -rf "$LAUNCHER_DIR/configs/ATLauncher.json"
    rm -rf "$LAUNCHER_DIR/ATLauncher.jar"
    rm -rf "$MCDIR/lwjgl-arm64-natives"
    osascript -e 'display dialog "Diagnostic Completed.\nEmail xploczx@gmail.com about issues in detail if you encounter any." buttons {"OK"} default button "OK" with title "Diagnostic"'
    ;;
  "Launch") break ;;
  esac
done

for java_version in 8 17 21 25; do install_java $java_version; done
install_lwjgl_arm_natives
create_wrapper
install_launcher

pkill -f "ATLauncher.jar" 2>/dev/null || true
cd "$LAUNCHER_DIR"
"$MCDIR/Java21/Contents/Home/bin/java" -jar "$LAUNCHER_DIR/ATLauncher.jar" || osascript -e 'display dialog "ATLauncher failed to start.\nTry re-running the script." buttons {"OK"} with title "SEHS Minecraft"'
# Using Java LTS versions for launcher bootup, this is the latest as of now.
