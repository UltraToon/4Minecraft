#!/bin/bash
set -euo pipefail
MCDIR="$HOME/Documents/MCSEHS"
LAUNCHER_DIR="$MCDIR/ATLauncher"

install_java() {
  local JAVA_DIR="$MCDIR/Java$1"
  [ -d "$JAVA_DIR" ] && return
  osascript -e "display dialog \"Installing Java $1...\nThis one-time process may take a few minutes.\" buttons {\"OK\"} default button \"OK\" with title \"Java Installer\"" &
  local DIALOG=$!
  mkdir -p "$JAVA_DIR" #Also creates MCDIR if it doesn't exist
  curl -L -o /tmp/java-corretto.tar.gz "https://corretto.aws/downloads/latest/amazon-corretto-${1}-aarch64-macos-jdk.tar.gz"
  tar -xzf /tmp/java-corretto.tar.gz -C "$JAVA_DIR" --strip-components=1
  rm /tmp/java-corretto.tar.gz
  kill $DIALOG 2>/dev/null
}
while true; do
  ACTION=$(osascript -e 'button returned of (display dialog "Welcome to Minecraft @ SEHS\nClick Launch to launch ATLauncher for minecraft." buttons {"Info", "Troubleshooting", "Exit", "Launch"} default button "Launch" with title "SEHS Minecraft")')
  case "$ACTION" in
  "Info")
    osascript -e 'display dialog "ATLauncher lets you create and manage Minecraft instances.\n\nGetting started:\n• Sign in via Accounts tab with your Microsoft account\n• Go to Instances and click Add Instance\n• Pick a version or modpack and click Install\n• Hit Play when done\n\nEach instance is separate, great for different modpacks or versions. When using a version, you can install individual mods to it, depending on the modloader/version" buttons {"Back"} with title "Info"'
    ;;
  "Troubleshooting")
    osascript -e 'display dialog "Common fixes:\n• Re-run this script if Java errors appear\n• Go to Finder->Documents->MCSEHS and delete all Java folders\n• Certain Minecraft versions require certain Java versions, make sure your selecting the right minecraft version you want to play when booting up. You need to close ATLauncher and choose another java version if your trying a different instance on a different minecraft version." buttons {"Back"} with title "Troubleshooting"'
    ;;
  "Exit") exit 0 ;;
  "Launch") break ;;
  esac
done
for java_version in 8 17 21 25; do install_java $java_version; done

if [[ ! -f "$LAUNCHER_DIR/ATLauncher.jar" ]]; then
  mkdir -p "$LAUNCHER_DIR/configs" #Also creates LAUNCHER_DIR if it doesn't exist
  curl -L -o "$LAUNCHER_DIR/ATLauncher.jar" "$(curl -s https://api.github.com/repos/ATLauncher/ATLauncher/releases/latest | grep -o 'https://[^"]*\.jar')"
  cat >"$LAUNCHER_DIR/configs/ATLauncher.json" <<EOF
{
  "firstTimeRun": false,
  "selectedTabOnStartup": 2,
  "useJavaProvidedByMinecraft": false,
  "usingCustomJavaPath": true,
  "javaPath": "$MCDIR/Java21/Contents/Home",
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
fi

JAVA_CHOICE=$(osascript -e 'choose from list {"Minecraft 26.1+ (Java 25)", "Minecraft 1.20.5+ (Java 21)", "Minecraft 1.17–1.20.4 (Java 17)", "Minecraft 1.16.5 and below (Java 8)"} with title "SEHS Minecraft" with prompt "Which Minecraft version are you playing?" OK button name "Continue" cancel button name "Cancel"')
[[ "$JAVA_CHOICE" == "false" ]] && exit 0
for java_version in 25 21 17 8; do
  [[ "$JAVA_CHOICE" == *"Java $java_version"* ]] && JAVA_HOME="$MCDIR/Java$java_version/Contents/Home" && break
done
sed -i '' "s|\"javaPath\":.*|\"javaPath\": \"$JAVA_HOME\",|" "$LAUNCHER_DIR/configs/ATLauncher.json"

pkill -f "ATLauncher.jar" 2>/dev/null || true
cd "$LAUNCHER_DIR"
"$MCDIR/Java21/Contents/Home/bin/java" -jar "$LAUNCHER_DIR/ATLauncher.jar" || osascript -e 'display dialog "ATLauncher failed to start.\nTry re-running the script." buttons {"OK"} with title "SEHS Minecraft"'
# Using Java LTS versions for launcher bootup, this is the latest as of now.
