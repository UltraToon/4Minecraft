#!/bin/bash
set -euo pipefail

MCDIR="$HOME/Documents/MCSEHS"
LAUNCHER_DIR="$MCDIR/ATLauncher"

# Apple Silicon = aarch64, Intel = x86_64 — Corretto ships separate tarballs for each
[[ "$(uname -m)" == "arm64" ]] && ARCH="aarch64" || ARCH="x86_64"

# Downloads the correct Corretto tarball. Skips silently if already installed.
install_java() {
  local ver="$1" dir="$MCDIR/Java${ver}"
  [[ -d "$dir" ]] && return

  osascript -e "display dialog \"Downloading Java ${ver}…\nThis one-time setup may take a minute.\" \
    buttons {\"OK\"} default button \"OK\" with title \"SEHS Minecraft\"" &>/dev/null &
  local dlg=$!

  mkdir -p "$dir"
  curl -fsSL -o /tmp/corretto.tar.gz \
    "https://corretto.aws/downloads/latest/amazon-corretto-${ver}-${ARCH}-macos-jdk.tar.gz" || {
      kill "$dlg" 2>/dev/null || true
      osascript -e "display dialog \"Failed to download Java ${ver}.\nCheck your connection and try again.\" \
        buttons {\"OK\"} with title \"SEHS Minecraft\"" &>/dev/null
      exit 1
  }
  tar -xzf /tmp/corretto.tar.gz -C "$dir" --strip-components=1
  rm /tmp/corretto.tar.gz
  kill "$dlg" 2>/dev/null || true
}

# Downloads ATLauncher and writes an initial config pointing to our Java wrapper.
# Skips silently if already installed.
install_launcher() {
  [[ -f "$LAUNCHER_DIR/ATLauncher.jar" ]] && return

  osascript -e 'display dialog "Downloading ATLauncher…\nThis is a one-time setup." \
    buttons {"OK"} default button "OK" with title "SEHS Minecraft"' &>/dev/null &
  local dlg=$!

  mkdir -p "$LAUNCHER_DIR/configs"
  local jar_url
  jar_url=$(curl -fsSL https://api.github.com/repos/ATLauncher/ATLauncher/releases/latest \
    | grep -o 'https://[^"]*ATLauncher[^"]*\.jar' | head -1) || {
      kill "$dlg" 2>/dev/null || true
      osascript -e 'display dialog "Could not fetch ATLauncher.\nCheck your connection." \
        buttons {"OK"} with title "SEHS Minecraft"' &>/dev/null
      exit 1
  }
  curl -fsSL -o "$LAUNCHER_DIR/ATLauncher.jar" "$jar_url" || {
    kill "$dlg" 2>/dev/null || true
    osascript -e 'display dialog "Failed to download ATLauncher.\nCheck your connection." \
      buttons {"OK"} with title "SEHS Minecraft"' &>/dev/null
    exit 1
  }

  # javaInstallLocation is a no-op on macOS (no JavaFinder branch in ATLauncher source).
  # Mojang bundled runtimes are blocked on managed school Macs.
  # javaPath points to our wrapper, which auto-routes per instance at launch time.
  cat > "$LAUNCHER_DIR/configs/ATLauncher.json" << EOF
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
  kill "$dlg" 2>/dev/null || true
}

# Writes a thin Java shim that ATLauncher calls for every instance launch.
# The shim reads instance.json to find the required Java version, then exec's
# into the correct Corretto — leaving zero memory/CPU overhead while playing.
create_wrapper() {
  local bin="$MCDIR/JavaWrapper/Contents/Home/bin"
  mkdir -p "$bin"


  cat > "$bin/java" << 'WRAPPER'
#!/bin/bash
MCDIR="$HOME/Documents/MCSEHS"
JAVA_VER="21"  # default: ATLauncher UI calls java too, 21 is correct for that

for arg in "$@"; do
  [[ "$arg" != *"/ATLauncher/instances/"* ]] && continue
  tmp="${arg#*/ATLauncher/instances/}"
  json_file="$MCDIR/ATLauncher/instances/${tmp%%/*}/instance.json"

  # No majorVersion = pre-1.17, always Java 8
  JAVA_VER="8"

  if [[ -f "$json_file" ]] && [[ $(< "$json_file") =~ \"majorVersion\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
    req="${BASH_REMATCH[1]}"
    if   (( req >= 25 )); then JAVA_VER="25"
    elif (( req >= 21 )); then JAVA_VER="21"
    elif (( req >= 17 )); then JAVA_VER="17"
    fi
  fi
  break
done

real="$MCDIR/Java${JAVA_VER}/Contents/Home/bin/java"
[[ -f "$real" ]] || real="$MCDIR/Java21/Contents/Home/bin/java"
exec "$real" "$@"
WRAPPER

  chmod +x "$bin/java"
}

# ── Welcome menu ───────────────────────────────────────────────────────────────
while true; do
  ACTION=$(osascript -e 'button returned of (display dialog "Welcome to Minecraft @ SEHS\n\nJava is managed automatically — just hit Launch." \
    buttons {"Info", "Troubleshooting", "Launch"} default button "Launch" with title "SEHS Minecraft")')
  case "$ACTION" in
    Info)
      osascript -e 'display dialog "ATLauncher lets you create and manage Minecraft instances.\n\nGetting started:\n• Sign in via the Accounts tab with your Microsoft account\n• Go to Instances → Add Instance\n• Pick a version or modpack and click Install\n• Hit Play!\n\nEach instance is isolated — perfect for different modpacks or versions.\nJava is selected automatically for each instance you launch." \
        buttons {"Back"} with title "Info"' &>/dev/null
      ;;
    Troubleshooting)
      osascript -e 'display dialog "Common fixes:\n• Re-run this script if Java errors appear\n• To reset Java, delete ~/Documents/MCSEHS/Java* folders and re-run\n• Java is chosen automatically per instance — no action needed\n• If ATLauncher warns about a Java mismatch, click Yes/Continue (the wrapper handles it)" \
        buttons {"Back"} with title "Troubleshooting"' &>/dev/null
      ;;
    Launch) break ;;
  esac
done

# ── Setup (all operations skip silently if already done) ──────────────────────
for ver in 8 17 21 25; do install_java "$ver"; done
create_wrapper
install_launcher
# Always ensure the config points to the wrapper — fixes pre-existing installs
# that were set up before the wrapper existed, without touching any other settings
sed -i '' "s|\"javaPath\":.*|\"javaPath\": \"$MCDIR/JavaWrapper/Contents/Home\",|" \
  "$LAUNCHER_DIR/configs/ATLauncher.json" 2>/dev/null || true

# ── Launch ─────────────────────────────────────────────────────────────────────
pkill -f "ATLauncher.jar" 2>/dev/null || true
cd "$LAUNCHER_DIR"
"$MCDIR/Java21/Contents/Home/bin/java" -jar ATLauncher.jar \
  || osascript -e 'display dialog "ATLauncher failed to start.\nTry re-running the script." \
      buttons {"OK"} with title "SEHS Minecraft"' &>/dev/null
