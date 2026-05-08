#!/bin/bash
set -euo pipefail
LAUNCHER_DIR="$HOME/Documents/ATLauncher"
JAVA_BASE="$HOME/Documents"
#FLAG="$HOME/.geometrysetup"

install_java() {
  local JAVA_VER=$1
  local JAVA_DIR="$JAVA_BASE/Java$JAVA_VER"

  if [ ! -d "$JAVA_DIR" ]; then
    mkdir -p "$JAVA_DIR"
    curl -L -o /tmp/java-corretto.tar.gz "https://corretto.aws/downloads/latest/amazon-corretto-${JAVA_VER}-aarch64-macos-jdk.tar.gz"
    tar -xzf /tmp/java-corretto.tar.gz -C "$JAVA_DIR" --strip-components=1
    rm /tmp/java-corretto.tar.gz
  fi
}

#if [ ! -f "$FLAG" ]; then
#    osascript -e 'display dialog "This tool will get you set up with Minecraft in just a few steps\nATLauncher is used, being a launcher for modpacks/instances that you can customize.\nYou need to sign in with your minecraft account on it, and select the custom Java version." buttons {"Continue"} default button "Continue" with title "Intro to Setup"'
#    touch "$FLAG"
#fi

INSTALL_JAVA=$(osascript -e 'button returned of (display dialog "Do you want to install Java?\nNOTE: Required atleast one for first time!" buttons {"No", "Yes"} default button "Yes")')
if [[ "$INSTALL_JAVA" = "Yes" ]]; then
CHOICES=$(osascript -e 'choose from list {"Java 8","Java 17","Java 21","Java 26"} with title "Java Installer" with prompt "Select versions to install:" with multiple selections allowed OK button name "Install" cancel button name "Cancel"')
[[ "$CHOICES" == "false" ]] && exit 0
for v in 8 17 21 26; do
  [[ "$CHOICES" == *"Java $v"* ]] && install_java $v
done
fi

if [[ ! -d "$LAUNCHER_DIR" ]]; then
  mkdir -p "$LAUNCHER_DIR"
  curl -L -o "$LAUNCHER_DIR/ATLauncher.jar" "$(curl -s https://api.github.com/repos/ATLauncher/ATLauncher/releases/latest | grep -o 'https://[^"]*\.jar')"
fi


for VER in 26 21 17 8; do
  JAVA_BIN="$JAVA_BASE/Java$VER/Contents/Home/bin/java"
  if [ -f "$JAVA_BIN" ]; then
    cd "$LAUNCHER_DIR"
    "$JAVA_BIN" -jar "$LAUNCHER_DIR/ATLauncher.jar"
    break
  fi
done
