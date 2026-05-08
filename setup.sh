#!/bin/bash
set -euo pipefail
LAUNCHER_DIR="$HOME/Documents/ATLauncher"
JAVA_BASE="$HOME/Documents"

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

any_java_installed() {
  for v in 8 17 21 26; do [ -f "$JAVA_BASE/Java$v/Contents/Home/bin/java" ] && return 0; done; return 1
}

if ! any_java_installed || [[ "$(osascript -e 'button returned of (display dialog "Install more Java versions (for different minecraft versions)?" buttons {"No","Yes"} default button "Yes")')" == "Yes" ]]; then
  JAVA_CHOICE=$(osascript -e 'choose from list {"Java 8 (Minecraft 1.16.5 and below)", "Java 17 (Minecraft 1.17 – 1.20.4)", "Java 21 (Minecraft 1.20.5+)", "Java 26 (Minecraft 26.1+)", "Install All"} with title "Java Installer" with prompt "Select a Java version for Minecraft:" OK button name "Install" cancel button name "Cancel"')
  case "$JAVA_CHOICE" in
    *"Java 8"*) install_java 8 ;;
    *"Java 17"*)  install_java 17 ;;
    *"Java 21"*)  install_java 21 ;;
    *"Java 26"*)  install_java 26 ;;
    *"Install All"*) install_java 8; install_java 17; install_java 21 ; install_java 26 ;;
    *) ;;
  esac

  [ "$JAVA_CHOICE" != "false" ] && osascript -e 'display notification "Java installation complete!" with title "Java Installer"'
fi

if [[ ! -f "$LAUNCHER_DIR/ATLauncher.jar" ]]; then
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
