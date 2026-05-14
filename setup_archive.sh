#!/bin/bash
set -euo pipefail

MCDIR="$HOME/Documents/MCSEHS"
LAUNCHER_DIR="$MCDIR/ATLauncher"

# Detect CPU architecture so Corretto downloads the right build
[[ "$(uname -m)" == "arm64" ]] && CORRETTO_ARCH="aarch64" || CORRETTO_ARCH="x86_64"

# Downloads and installs Amazon Corretto for the given major version.
# Skips silently if already installed.
install_java() {
  local JAVA_DIR="$MCDIR/Java$1"
  [ -d "$JAVA_DIR" ] && return
  osascript -e "display dialog \"Downloading Java $1...\nThis one-time setup may take a few minutes.\" buttons {\"OK\"} default button \"OK\" with title \"SEHS Minecraft\"" &
  local DIALOG=$!
  mkdir -p "$JAVA_DIR"
  curl -L -o /tmp/java-corretto.tar.gz \
    "https://corretto.aws/downloads/latest/amazon-corretto-${1}-${CORRETTO_ARCH}-macos-jdk.tar.gz" \
    || { kill "$DIALOG" 2>/dev/null
         osascript -e "display dialog \"Failed to download Java $1.\nCheck your internet connection and try again.\" buttons {\"OK\"} with title \"SEHS Minecraft\""
         exit 1; }
  tar -xzf /tmp/java-corretto.tar.gz -C "$JAVA_DIR" --strip-components=1
  rm /tmp/java-corretto.tar.gz
  kill "$DIALOG" 2>/dev/null || true
}

# Downloads ATLauncher and writes the default config. Skips if already installed.
install_launcher() {
  [[ -f "$LAUNCHER_DIR/ATLauncher.jar" ]] && return
  osascript -e 'display dialog "Downloading ATLauncher...\nThis is a one-time setup." buttons {"OK"} default button "OK" with title "SEHS Minecraft"' &
  local DIALOG=$!
  mkdir -p "$LAUNCHER_DIR/configs"
  # Fetch the .jar download URL from the latest GitHub release
  local JAR_URL
  JAR_URL=$(curl -s https://api.github.com/repos/ATLauncher/ATLauncher/releases/latest \
    | grep -o 'https://[^"]*\.jar') \
    || { kill "$DIALOG" 2>/dev/null
         osascript -e 'display dialog "Could not fetch ATLauncher.\nCheck your internet connection." buttons {"OK"} with title "SEHS Minecraft"'
         exit 1; }
  curl -L -o "$LAUNCHER_DIR/ATLauncher.jar" "$JAR_URL" \
    || { kill "$DIALOG" 2>/dev/null
         osascript -e 'display dialog "Failed to download ATLauncher.\nCheck your internet and try again." buttons {"OK"} with title "SEHS Minecraft"'
         exit 1; }
  # Write default config (firstTimeRun:false skips ATLauncher's own setup wizard)
  cat >"$LAUNCHER_DIR/configs/ATLauncher.json" <<EOF
{
  "firstTimeRun": false,
  "selectedTabOnStartup": 2,
  "useJavaProvidedByMinecraft": false,
  "usingCustomJavaPath": false,
  "javaInstallLocation": "$MCDIR",
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
  kill "$DIALOG" 2>/dev/null || true
}

# ── Welcome menu ──────────────────────────────────────────────────────────────
while true; do
  ACTION=$(osascript -e 'button returned of (display dialog "Welcome to Minecraft @ SEHS\nClick Launch to launch ATLauncher for minecraft." buttons {"Info", "Troubleshooting", "Launch"} default button "Launch" with title "SEHS Minecraft")')
  case "$ACTION" in
  "Info")
    osascript -e 'display dialog "ATLauncher lets you create and manage Minecraft instances.\n\nGetting started:\n• Sign in via Accounts tab with your Microsoft account\n• Go to Instances and click Add Instance\n• Pick a version or modpack and click Install\n• Hit Play when done\n\nEach instance is separate, great for different modpacks or versions. When using a version, you can install individual mods to it, depending on the modloader/version" buttons {"Back"} with title "Info"'
    ;;
  "Troubleshooting")
    osascript -e 'display dialog "Common fixes:\n• Re-run this script if Java errors appear\n• Go to Finder->Documents->MCSEHS and delete all Java folders, then re-run\n• ATLauncher automatically picks the correct Java version for each instance — you do not need to choose manually" buttons {"Back"} with title "Troubleshooting"'
    ;;
  "Launch") break ;;
  esac
done

# ── Install all Java versions (each skips silently if already present) ────────
for java_version in 8 17 21 25; do
  install_java "$java_version"
done

# ── Download ATLauncher if not already present ────────────────────────────────
install_launcher

pkill -f "ATLauncher.jar" 2>/dev/null || true
cd "$LAUNCHER_DIR"
# ATLauncher boots on Java 21 (LTS). Per-instance Java is auto-selected by ATLauncher
# using the javaInstallLocation set in configs/ATLauncher.json, which points to $MCDIR.
"$MCDIR/Java21/Contents/Home/bin/java" -jar "$LAUNCHER_DIR/ATLauncher.jar" \
  || osascript -e 'display dialog "ATLauncher failed to start.\nTry re-running the script." buttons {"OK"} with title "SEHS Minecraft"'
