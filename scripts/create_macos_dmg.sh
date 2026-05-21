#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?Usage: create_macos_dmg.sh <app-path> [output-dmg] [volume-name]}"
OUTPUT_DMG="${2:-Clawke-macOS.dmg}"
VOLUME_NAME="${3:-Clawke}"

APP_NAME="$(basename "$APP_PATH")"
SCRIPT_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clawke-dmg.XXXXXX")"
STAGE_DIR="$SCRIPT_TMP_DIR/stage"
RW_DMG="$SCRIPT_TMP_DIR/${VOLUME_NAME}-rw.dmg"
BACKGROUND_SWIFT="$SCRIPT_TMP_DIR/create_background.swift"
BACKGROUND_PATH="$STAGE_DIR/.background/background.png"
BACKGROUND_WIDTH=720
BACKGROUND_HEIGHT=460
FINDER_CHROME_HEIGHT=66
WINDOW_LEFT=160
WINDOW_TOP=120
WINDOW_RIGHT=$((WINDOW_LEFT + BACKGROUND_WIDTH))
WINDOW_BOTTOM=$((WINDOW_TOP + BACKGROUND_HEIGHT + FINDER_CHROME_HEIGHT))
MOUNT_POINT=""
DEVICE=""

cleanup() {
  if [ -n "${MOUNT_POINT:-}" ] && [ -d "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet || true
  elif [ -n "${DEVICE:-}" ]; then
    hdiutil detach "$DEVICE" -quiet || true
  fi
  rm -rf "$SCRIPT_TMP_DIR"
}
trap cleanup EXIT

if [ ! -d "$APP_PATH" ]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

mkdir -p "$STAGE_DIR/.background"
ditto "$APP_PATH" "$STAGE_DIR/$APP_NAME"
ln -s /Applications "$STAGE_DIR/Applications"

cat > "$BACKGROUND_SWIFT" <<'SWIFT'
import AppKit

let outputPath = CommandLine.arguments[1]
let backgroundWidth = Double(CommandLine.arguments[2])!
let backgroundHeight = Double(CommandLine.arguments[3])!
let size = NSSize(width: backgroundWidth, height: backgroundHeight)
let image = NSImage(size: size)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1.0) -> NSColor {
    NSColor(calibratedRed: red / 255.0, green: green / 255.0, blue: blue / 255.0, alpha: alpha)
}

func drawText(_ text: String, rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor, alignment: NSTextAlignment = .center) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    text.draw(in: rect, withAttributes: attrs)
}

image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

let fullRect = NSRect(origin: .zero, size: size)
color(14, 20, 18).setFill()
fullRect.fill()

NSGradient(colors: [
    color(11, 25, 23),
    color(20, 42, 36),
    color(8, 14, 13)
])?.draw(in: fullRect, angle: -28)

for (rect, alpha) in [
    (NSRect(x: -90, y: 260, width: 360, height: 260), CGFloat(0.34)),
    (NSRect(x: 450, y: -100, width: 360, height: 320), CGFloat(0.28)),
    (NSRect(x: 250, y: 170, width: 260, height: 180), CGFloat(0.14))
] {
    color(16, 199, 143, alpha).setFill()
    NSBezierPath(ovalIn: rect).fill()
}

let panel = NSBezierPath(roundedRect: NSRect(x: 44, y: 42, width: 632, height: 376), xRadius: 34, yRadius: 34)
color(255, 255, 255, 0.075).setFill()
panel.fill()
color(255, 255, 255, 0.16).setStroke()
panel.lineWidth = 1.0
panel.stroke()

drawText(
    "Clawke",
    rect: NSRect(x: 80, y: 300, width: 560, height: 46),
    size: 34,
    weight: .bold,
    color: color(248, 255, 252)
)
drawText(
    "Drag Clawke to Applications",
    rect: NSRect(x: 80, y: 266, width: 560, height: 28),
    size: 16,
    weight: .medium,
    color: color(205, 224, 216)
)

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 290, y: 178))
arrow.curve(to: NSPoint(x: 430, y: 178), controlPoint1: NSPoint(x: 330, y: 205), controlPoint2: NSPoint(x: 390, y: 205))
color(21, 214, 157).setStroke()
arrow.lineWidth = 4
arrow.lineCapStyle = .round
arrow.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 430, y: 178))
head.line(to: NSPoint(x: 412, y: 192))
head.move(to: NSPoint(x: 430, y: 178))
head.line(to: NSPoint(x: 412, y: 164))
head.lineWidth = 4
head.lineCapStyle = .round
head.stroke()

let badge = NSBezierPath(roundedRect: NSRect(x: 235, y: 78, width: 250, height: 42), xRadius: 21, yRadius: 21)
color(21, 214, 157, 0.18).setFill()
badge.fill()
color(21, 214, 157, 0.55).setStroke()
badge.lineWidth = 1
badge.stroke()
drawText(
    "Open, drag, and install",
    rect: NSRect(x: 248, y: 88, width: 224, height: 22),
    size: 14,
    weight: .semibold,
    color: color(226, 255, 245)
)

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Failed to render DMG background")
}

try pngData.write(to: URL(fileURLWithPath: outputPath))
SWIFT

swift "$BACKGROUND_SWIFT" "$BACKGROUND_PATH" "$BACKGROUND_WIDTH" "$BACKGROUND_HEIGHT"

APP_SIZE_MB="$(du -sm "$STAGE_DIR" | awk '{print $1}')"
DMG_SIZE_MB="$((APP_SIZE_MB + 180))"

rm -f "$OUTPUT_DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -ov \
  -fs APFS \
  -size "${DMG_SIZE_MB}m" \
  "$RW_DMG" >/dev/null

ATTACH_LOG="$SCRIPT_TMP_DIR/attach.log"
hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -owners off | tee "$ATTACH_LOG"
DEVICE="$(awk '/\/Volumes\// {print $1; exit}' "$ATTACH_LOG")"
MOUNT_POINT="$(awk '/\/Volumes\// {for (i=3; i<=NF; i++) printf "%s%s", (i == 3 ? "" : " "), $i; print ""; exit}' "$ATTACH_LOG")"
if [ -z "$MOUNT_POINT" ]; then
  MOUNT_POINT="/Volumes/$VOLUME_NAME"
fi
FINDER_VOLUME_NAME="$(basename "$MOUNT_POINT")"

mkdir -p "$MOUNT_POINT/$APP_NAME"
rsync -a "$STAGE_DIR/$APP_NAME/" "$MOUNT_POINT/$APP_NAME/"
ditto "$STAGE_DIR/.background" "$MOUNT_POINT/.background"
ln -s /Applications "$MOUNT_POINT/Applications"

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$FINDER_VOLUME_NAME"
    open
    set current view of container window to icon view
    set bounds of container window to {$WINDOW_LEFT, $WINDOW_TOP, $WINDOW_RIGHT, $WINDOW_BOTTOM}
    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 104
    set background picture of viewOptions to (POSIX file "$MOUNT_POINT/.background/background.png")
    set position of item "$APP_NAME" of container window to {180, 248}
    set position of item "Applications" of container window to {540, 248}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

rm -rf "$MOUNT_POINT/.fseventsd"
sync
sleep 2
hdiutil detach "$MOUNT_POINT" -quiet
MOUNT_POINT=""

hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$OUTPUT_DMG" >/dev/null

echo "Created DMG: $OUTPUT_DMG"
