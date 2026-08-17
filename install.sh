#!/usr/bin/env bash
# Installs audio-follows-window into ~/.local/bin and sets up the user service.
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
UNIT_DIR="$HOME/.config/systemd/user"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Checking dependencies"
missing=()
for tool in xdotool xprop xrandr pactl; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done

if [ ${#missing[@]} -gt 0 ]; then
    echo "    Missing: ${missing[*]}"
    echo "    Install with:"
    echo "      sudo apt install xdotool x11-utils x11-xserver-utils"
    echo "      (Fedora: sudo dnf install xdotool xorg-x11-utils xrandr)"
    echo "      (Arch:   sudo pacman -S xdotool xorg-xprop xorg-xrandr)"
    exit 1
fi

if [ "${XDG_SESSION_TYPE:-}" = "wayland" ]; then
    echo "    Warning: this session is Wayland. The script needs X11 and will"
    echo "    not detect windows here. See README."
fi

echo "==> Installing to $BIN_DIR"
mkdir -p "$BIN_DIR"
install -m 755 "$SRC_DIR/audio-follows-window" "$BIN_DIR/audio-follows-window"

echo "==> Installing user service to $UNIT_DIR"
mkdir -p "$UNIT_DIR"
install -m 644 "$SRC_DIR/audio-follows-window.service" \
    "$UNIT_DIR/audio-follows-window.service"
systemctl --user daemon-reload

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "    Note: $BIN_DIR is not on PATH. Add this to ~/.bashrc:"
       echo "      export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

cat <<'EOF'

Installed. Next steps:

  1. audio-follows-window --setup      map each display to an audio sink
  2. audio-follows-window --watch -v   confirm it works, Ctrl-C to stop
  3. systemctl --user enable --now audio-follows-window

If you are using MATE or XFCE and step 3 doesn't start it, see the README section
"Autostart without systemd".
EOF
