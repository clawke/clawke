#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

APP_ID="ai.clawke.app"
APP_NAME="Clawke"
ICON_SIZES=(512 256 128 64 48)
HICOLOR_DIR="$HOME/.local/share/icons/hicolor"

SOURCE="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  RESOLVED="$(readlink -f "$SOURCE" 2>/dev/null || true)"
  if [[ -n "$RESOLVED" ]]; then
    SOURCE="$RESOLVED"
  fi
fi

APP_DIR="$(cd -- "$(dirname -- "$SOURCE")" && pwd -P)"
APP_EXE="$APP_DIR/Clawke"
ICON_SRC="$APP_DIR/data/app_icon.png"

if [[ ! -x "$APP_EXE" ]]; then
  echo "Clawke executable not found or not executable: $APP_EXE" >&2
  exit 1
fi

if [[ ! -f "$ICON_SRC" ]]; then
  echo "Clawke icon not found: $ICON_SRC" >&2
  exit 1
fi

escape_desktop_exec_path() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//%/%%}"
  printf '"%s"' "$value"
}

DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/$APP_ID.desktop"

install_icon() {
  local size="$1"
  local target="$2"

  if command -v gdk-pixbuf-thumbnailer >/dev/null 2>&1; then
    if gdk-pixbuf-thumbnailer -s "$size" "$ICON_SRC" "$target" >/dev/null 2>&1; then
      chmod 0644 "$target"
      return
    fi
  fi

  install -m 0644 "$ICON_SRC" "$target"
}

mkdir -p "$DESKTOP_DIR"
for size in "${ICON_SIZES[@]}"; do
  icon_dir="$HICOLOR_DIR/${size}x${size}/apps"
  mkdir -p "$icon_dir"
  install_icon "$size" "$icon_dir/$APP_ID.png"
done
rm -f "$HICOLOR_DIR/1024x1024/apps/$APP_ID.png"

if [[ ! -f "$HICOLOR_DIR/index.theme" && -f /usr/share/icons/hicolor/index.theme ]]; then
  install -m 0644 /usr/share/icons/hicolor/index.theme "$HICOLOR_DIR/index.theme"
fi

ESCAPED_APP_EXE="$(escape_desktop_exec_path "$APP_EXE")"
cat >"$DESKTOP_FILE" <<DESKTOP
[Desktop Entry]
Type=Application
Version=1.0
Name=$APP_NAME
GenericName=AI Workspace
Comment=Your AI workspace, anywhere.
Exec=$ESCAPED_APP_EXE
Icon=$APP_ID
Terminal=false
Categories=Utility;Development;
StartupNotify=true
StartupWMClass=$APP_ID
DESKTOP

chmod 0644 "$DESKTOP_FILE"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -f -t "$HICOLOR_DIR" >/dev/null 2>&1 || true
fi

if command -v xdg-desktop-menu >/dev/null 2>&1; then
  xdg-desktop-menu forceupdate --mode user >/dev/null 2>&1 || true
fi

echo "Clawke desktop entry installed:"
echo "  $DESKTOP_FILE"
for size in "${ICON_SIZES[@]}"; do
  echo "  $HICOLOR_DIR/${size}x${size}/apps/$APP_ID.png"
done

if ! command -v fc-match >/dev/null 2>&1; then
  echo
  echo "Chinese font check skipped: fc-match is not installed."
  echo "If Chinese text appears as boxes, install a CJK font:"
  echo "  sudo apt install fonts-noto-cjk"
  echo "  fc-cache -fv"
  exit 0
fi

ZH_FONT_MATCH="$(fc-match -f '%{family}\n%{file}\n' ':lang=zh' 2>/dev/null || true)"
if [[ -z "$ZH_FONT_MATCH" ]] ||
  ! printf '%s\n' "$ZH_FONT_MATCH" |
    grep -Eiq 'Noto Sans CJK|Noto Serif CJK|Source Han|WenQuanYi|Droid Sans Fallback|AR PL|uming|ukai|Noto Sans SC|Noto Serif SC'; then
  echo
  echo "Chinese font may be missing. If Chinese text appears as boxes, run:"
  echo "  sudo apt install fonts-noto-cjk"
  echo "  fc-cache -fv"
else
  echo "Chinese font detected: $(printf '%s\n' "$ZH_FONT_MATCH" | head -n 1)"
fi
