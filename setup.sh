#!/bin/bash
set -euo pipefail
MCDIR="$HOME/Documents/MCSEHS"
LAUNCHER_DIR="$MCDIR/ATLauncher"

install_java() {
  local JAVA_DIR="$MCDIR/Java$1"
  [ -d "$JAVA_DIR" ] && return
  osascript -e "display dialog \"Installing Java $1...\nPlease wait, this may take a few minutes.\" buttons {} giving up after 300 with title \"SEHS Minecraft\"" &
  local DIALOG=$!
  mkdir -p "$JAVA_DIR"
  curl -L -o /tmp/java-corretto.tar.gz "https://corretto.aws/downloads/latest/amazon-corretto-${1}-aarch64-macos-jdk.tar.gz"
  tar -xzf /tmp/java-corretto.tar.gz -C "$JAVA_DIR" --strip-components=1
  rm /tmp/java-corretto.tar.gz
  kill $DIALOG 2>/dev/null
}
mkdir -p "$MCDIR"
osascript -e 'display dialog "Setting up Minecraft...\nThis will take a few minutes while Java is installed.\nClick OK to begin." buttons {"OK"} with title "Minecraft Setup"'
for java_version in 8 17 21 26; do install_java $java_version; done

if [[ ! -f "$LAUNCHER_DIR/ATLauncher.jar" ]]; then
  mkdir -p "$LAUNCHER_DIR"
  curl -L -o "$LAUNCHER_DIR/ATLauncher.jar" "$(curl -s https://api.github.com/repos/ATLauncher/ATLauncher/releases/latest | grep -o 'https://[^"]*\.jar')"
  mkdir -p "$LAUNCHER_DIR/configs"
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
  "enableAnalytics": false
}
EOF
fi

while true; do
  ACTION=$(osascript -e 'button returned of (display dialog "Welcome to Minecraft @ SEHS" buttons {"Troubleshooting", "Info", "Launch Minecraft"} default button "Launch Minecraft" with title "SEHS Minecraft")')
  case "$ACTION" in
  "Troubleshooting")
    osascript -e 'display dialog "Common fixes:\n• Re-run this script if Java errors appear\n• Delete ~/Documents/MCSEHS and re-run if launcher is blank\n• Try a lower Java version if Minecraft crashes" buttons {"Back"} with title "Troubleshooting"'
    ;;
  "Info")
    osascript -e 'display dialog "This script boots up ATLauncher, which is a custom minecraft launcher, allowing you to setup separate modpack instances and browse mods/resourcepacks. It is recommended to use this script if you have tried custom launchers before like Curseforge Launcher, Prism Launcher, etc.," buttons {"Back"} with title "Info"'
    ;;
  "Launch Minecraft")
    JAVA_CHOICE=$(osascript -e 'choose from list {"Java 26 (1.21+)", "Java 21 (1.20.5+)", "Java 17 (1.17-1.20.4)", "Java 8 (1.16.5 and below)"} with title "SEHS Minecraft" with prompt "Which Minecraft version are you playing today?" OK button name "Continue" cancel button name "Cancel"')
    [[ "$JAVA_CHOICE" == "false" ]] && continue
    for v in 26 21 17 8; do
      [[ "$JAVA_CHOICE" == *"Java $v"* ]] && JAVA_HOME="$MCDIR/Java$v/Contents/Home" && break
    done
    sed -i '' "s|\"javaPath\":.*|\"javaPath\": \"$JAVA_HOME\",|" "$LAUNCHER_DIR/configs/ATLauncher.json"
    break
    ;;
  esac
done
cd "$LAUNCHER_DIR"
"$MCDIR/Java21/Contents/Home/bin/java" -jar "$LAUNCHER_DIR/ATLauncher.jar"
# Using Java LTS versions for launcher bootup, this is the latest as of now.
