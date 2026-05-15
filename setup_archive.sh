#!/bin/bash
set -euo pipefail
MCDIR="$HOME/Documents/MCSEHS"
LAUNCHER_DIR="$MCDIR/ATLauncher"

install_java() {
  [[ "$(uname -m)" == "arm64" ]] && ARCH="aarch64" || ARCH="x64"
  # The line below makes it so Java 8 is always x64, because MC doesnt support ARM with Java 8 on older versions. It automatically installs rosetta on ARM macs for compatibility with x64 Java 8
  [[ "$1" == "8" ]] && { ARCH="x64"; softwareupdate --install-rosetta --agree-to-license 2>/dev/null || true; }
  local JAVA_DIR="$MCDIR/Java$1"
  [ -d "$JAVA_DIR" ] && return
  osascript -e "display dialog \"Installing Java $1...\nThis one-time process may take a few minutes.\" buttons {\"OK\"} default button \"OK\" with title \"Java Installer\"" &
  local DIALOG=$!
  mkdir -p "$JAVA_DIR" #Also creates MCDIR if it doesn't exist
  curl -fsSL -o /tmp/java-corretto.tar.gz "https://corretto.aws/downloads/latest/amazon-corretto-${1}-${ARCH}-macos-jdk.tar.gz"
  tar -xzf /tmp/java-corretto.tar.gz -C "$JAVA_DIR" --strip-components=1
  rm /tmp/java-corretto.tar.gz
  kill $DIALOG 2>/dev/null
}

install_launcher() {
  [[ -f "$LAUNCHER_DIR/ATLauncher.jar" ]] && return
  mkdir -p "$LAUNCHER_DIR/configs" #Also creates LAUNCHER_DIR if it doesn't exist
  curl -fsSL -o "$LAUNCHER_DIR/ATLauncher.jar" "$(curl -s https://api.github.com/repos/ATLauncher/ATLauncher/releases/latest | grep -o 'https://[^"]*\.jar')"
  cat >"$LAUNCHER_DIR/configs/ATLauncher.json" <<EOF
{
  "firstTimeRun": false,
  "selectedTabOnStartup": 2,
  "useJavaProvidedByMinecraft": false,
  "usingCustomJavaPath": true,
  "javaPath": "$MCDIR/JavaWrapper/Contents/Home",
  "keepLauncherOpen": true,
  "enableConsole": false,
  "useRecycleBin": true,
  "maximumMemory": 4096,
  "enableAnalytics": false,
  "enableAutomaticBackupAfterLaunch": true,
  "backupMode": "NORMAL",
  "defaultInstanceSorting": "BY_NAME"
}
EOF
}

# Writes a thin Java shim that ATLauncher calls for every instance launch.
# The shim reads instance.json to find the required Java version, then exec's
# into the correct Corretto — leaving zero memory/CPU overhead while playing.
create_wrapper() {
  local bin="$MCDIR/JavaWrapper/Contents/Home/bin"
  mkdir -p "$bin"

  cat >"$bin/java" <<'WRAPPER'
#!/bin/bash
MCDIR="$HOME/Documents/MCSEHS"
JAVA_VER=21  # default: ATLauncher UI calls java for itself, 21 is fine

for arg in "$@"; do
  [[ "$arg" != *"/ATLauncher/instances/"* ]] && continue
  instance="${arg#*/ATLauncher/instances/}"
  json="$MCDIR/ATLauncher/instances/${instance%%/*}/instance.json"
  # Default to Java 8 for legacy instances with no majorVersion (pre-1.17)
  JAVA_VER=8
  [[ -f "$json" ]] && [[ $(< "$json") =~ \"majorVersion\"[[:space:]]*:[[:space:]]*([0-9]+) ]] && JAVA_VER="${BASH_REMATCH[1]}"
  break
done

real="$MCDIR/Java${JAVA_VER}/Contents/Home/bin/java"
[[ -f "$real" ]] || real="$MCDIR/Java21/Contents/Home/bin/java"
exec "$real" "$@"
WRAPPER

  chmod +x "$bin/java"
}

while true; do
  ACTION=$(osascript -e 'button returned of (display dialog "Welcome to Minecraft @ SEHS\nClick Launch to launch ATLauncher for minecraft." buttons {"Info", "Troubleshooting", "Launch"} default button "Launch" with title "SEHS Minecraft")')
  case "$ACTION" in
  "Info")
    osascript -e 'display dialog "ATLauncher lets you create and manage Minecraft instances.\n\nGetting started:\n• Sign in via Accounts tab with your Microsoft account\n• Go to Instances and click Add Instance\n• Pick a version or modpack and click Install\n• Hit Play when done\n\nEach instance is separate, great for different modpacks or versions. When using a version, you can install individual mods to it, depending on the modloader/version" buttons {"Back"} with title "Info"'
    ;;
  "Troubleshooting")
    osascript -e 'display dialog "Common fixes:\n• Re-run this script if Java errors appear\n• Go to Finder->Documents->MCSEHS and delete all "Java#" folders (DO NOT DELETE ATLauncher folder YOU WILL LOSE DATA)" buttons {"Back"} with title "Troubleshooting"'
    ;;
  "Launch") break ;;
  esac
done

for java_version in 8 17 21 25; do install_java $java_version; done
create_wrapper
install_launcher
# Always ensure the config points to the wrapper — fixes pre-existing installs
# that were set up before the wrapper existed, without touching any other settings
sed -i '' "s|\"javaPath\":.*|\"javaPath\": \"$MCDIR/JavaWrapper/Contents/Home\",|" \
  "$LAUNCHER_DIR/configs/ATLauncher.json" 2>/dev/null || true

pkill -f "ATLauncher.jar" 2>/dev/null || true
cd "$LAUNCHER_DIR"
"$MCDIR/Java21/Contents/Home/bin/java" -jar "$LAUNCHER_DIR/ATLauncher.jar" || osascript -e 'display dialog "ATLauncher failed to start.\nTry re-running the script." buttons {"OK"} with title "SEHS Minecraft"'
# Using Java LTS versions for launcher bootup, this is the latest as of now.
