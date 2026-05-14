#!/bin/bash
set -euo pipefail

MCDIR="$HOME/Documents/MCSEHS"
LAUNCHER_DIR="$MCDIR/ATLauncher"

# Apple Silicon = aarch64, Intel = x86_64 — Corretto ships separate tarballs for each
[[ "$(uname -m)" == "arm64" ]] && ARCH="aarch64" || ARCH="x86_64"

# Downloads the correct Corretto tarball. Skips silently if already installed.
install_java() {
  local ver="$1" dir="$MCDIR/Java${1}"
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
    | grep -o 'https://[^"]*\.jar' | head -1) || {
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

  # Note: single-quoted heredoc — no variable expansion, $HOME resolves at runtime
  cat > "$bin/java" << 'WRAPPER'
#!/bin/bash
MCDIR="$HOME/Documents/MCSEHS"
JAVA_VER="21"  # safe default for ATLauncher UI and unknown instances

# 1. Find the instance directory from ATLauncher's launch arguments
for arg in "$@"; do
  if [[ "$arg" == *"/ATLauncher/instances/"* ]]; then
    tmp="${arg#*/ATLauncher/instances/}"
    dir="$MCDIR/ATLauncher/instances/${tmp%%/*}"
    [[ -f "$dir/instance.json" ]] && INSTANCE_JSON="$dir/instance.json" && break
  fi
done

# 2. Pick the right Corretto using instance.json (ATLauncher's MinecraftVersion data)
#    Strategy: read javaVersion.majorVersion (Mojang's own spec, present for MC 1.17+)
#              and fall back to the "id" version string for older instances (pre-1.17 = Java 8)
if [[ -n "${INSTANCE_JSON:-}" ]]; then
  json=$(< "$INSTANCE_JSON")

  if [[ "$json" =~ \"majorVersion\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
    # Modern MC (1.17+): Mojang tells us exactly which Java major version is required.
    # Round up to the nearest Corretto we have installed (8, 17, 21, 25).
    req="${BASH_REMATCH[1]}"
    case "$req" in
      8|[1-9])   JAVA_VER="8"  ;;
      1[0-6])    JAVA_VER="8"  ;;
      17|1[89])  JAVA_VER="17" ;;
      2[01])     JAVA_VER="21" ;;
      *)         JAVA_VER="25" ;;
    esac
  elif [[ "$json" =~ \"id\"[[:space:]]*:[[:space:]]*\"1\.([0-9]+) ]]; then
    # Pre-1.17: no javaVersion field — use the "id" minor version to determine Java 8
    minor="${BASH_REMATCH[1]}"
    (( minor < 17 )) && JAVA_VER="8" || JAVA_VER="17"
  fi
fi

# 3. Resolve and exec — replace this process entirely (zero overhead while playing)
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
create_wrapper   # always re-written to pick up any script updates
install_launcher

# ── Launch ─────────────────────────────────────────────────────────────────────
pkill -f "ATLauncher.jar" 2>/dev/null || true
cd "$LAUNCHER_DIR"
"$MCDIR/Java21/Contents/Home/bin/java" -jar ATLauncher.jar \
  || osascript -e 'display dialog "ATLauncher failed to start.\nTry re-running the script." \
      buttons {"OK"} with title "SEHS Minecraft"' &>/dev/null
