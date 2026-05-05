#!/bin/bash
set -e

# ============================================================
# build-app.sh — Build ContainerDesktop as a proper .app bundle
# 
# Usage:
#   cd /path/to/ContainerDesktop
#   chmod +x build-app.sh
#   ./build-app.sh            # incremental build (fast)
#   ./build-app.sh --clean    # full clean build (slower, guaranteed fresh)
#
# Output: ./build/Container Desktop.app
# ============================================================

CLEAN_BUILD=false
for arg in "$@"; do
    case "$arg" in
        --clean|-c)
            CLEAN_BUILD=true
            ;;
        --help|-h)
            echo "Usage: $0 [--clean|-c]"
            echo ""
            echo "  --clean, -c   Remove .build/ and build/ directories before building."
            echo "                Use this if incremental builds aren't picking up changes."
            exit 0
            ;;
    esac
done

APP_NAME="Container Desktop"
BUNDLE_ID="com.containerdesktop.app"
EXECUTABLE="ContainerDesktopApp"
VERSION="0.0.0"
BUILD_DIR="./build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"

echo "=== Building ${APP_NAME} ==="

if [ "$CLEAN_BUILD" = true ]; then
    echo "→ Clean build requested..."
    # Use SPM's own clean first — it knows how to release index locks
    swift package clean 2>/dev/null || true
    # Then force-remove any remaining artifacts
    rm -rf .build 2>/dev/null || true
    rm -rf "${BUILD_DIR}" 2>/dev/null || true
    # If .build still exists (Xcode index locks), warn but continue
    if [ -d ".build" ]; then
        echo "⚠ Could not fully remove .build/ (Xcode may have files locked)."
        echo "  Close Xcode and retry, or the build will still work — just not fully clean."
    fi
fi

# Step 1: Build the release binary with SPM
echo "→ Compiling release binary..."
swift build -c release 2>&1 | tail -5

# Find the built binary
BINARY_PATH=$(swift build -c release --show-bin-path)/${EXECUTABLE}
if [ ! -f "$BINARY_PATH" ]; then
    echo "ERROR: Binary not found at ${BINARY_PATH}"
    echo "Make sure 'swift build -c release' succeeds first."
    exit 1
fi
echo "→ Binary: ${BINARY_PATH}"

# Step 2: Create the .app bundle structure
echo "→ Creating app bundle..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Step 3: Copy the binary
cp "${BINARY_PATH}" "${APP_DIR}/Contents/MacOS/${EXECUTABLE}"

# Step 4: Create Info.plist
cat > "${APP_DIR}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key>
    <string>Container Desktop ${VERSION}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

# Step 5: Build app icon from Resources/AppIcon.iconset
echo "→ Building app icon..."
ICONSET_SRC="Resources/AppIcon.iconset"

if [ -f "${ICONSET_SRC}/icon_512x512@2x.png" ]; then
    # Real icons exist — build .icns from them
    iconutil -c icns "${ICONSET_SRC}" -o "${APP_DIR}/Contents/Resources/AppIcon.icns" 2>/dev/null || {
        echo "  (iconutil failed — copying PNGs as fallback)"
        cp "${ICONSET_SRC}"/icon_*.png "${APP_DIR}/Contents/Resources/" 2>/dev/null
    }
    echo "  Using custom icon from ${ICONSET_SRC}"
else
    # No real icons yet — generate a placeholder
    echo "  No icon PNGs found in ${ICONSET_SRC}/"
    echo "  Generating placeholder icon (see Resources/AppIcon.iconset/README.md)"
    ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"
    mkdir -p "${ICONSET_DIR}"

    python3 -c "
import struct, zlib, os

def create_png(width, height, color_rgb):
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    
    r, g, b = color_rgb
    rows = []
    for y in range(height):
        row = b'\x00'
        for x in range(width):
            margin = int(width * 0.15)
            if margin < x < width - margin and margin < y < height - margin:
                factor = 1.0 - (y - margin) / (height - 2 * margin) * 0.3
                row += struct.pack('BBBB', 
                    max(0, min(255, int(r * factor))),
                    max(0, min(255, int(g * factor))),
                    max(0, min(255, int(b * factor))),
                    255)
            elif margin - int(width*0.02) < x < width - margin + int(width*0.02) and margin - int(width*0.02) < y < height - margin + int(width*0.02):
                row += struct.pack('BBBB', 
                    max(0, int(r * 0.6)),
                    max(0, int(g * 0.6)),
                    max(0, int(b * 0.6)),
                    255)
            else:
                row += struct.pack('BBBB', 0, 0, 0, 0)
        rows.append(row)
    
    raw = b''.join(rows)
    compressed = zlib.compress(raw)
    
    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', compressed)
    png += chunk(b'IEND', b'')
    return png

color = (55, 138, 221)
sizes = [16, 32, 64, 128, 256, 512, 1024]
for s in sizes:
    png = create_png(s, s, color)
    with open(f'${ICONSET_DIR}/icon_{s}x{s}.png', 'wb') as f:
        f.write(png)
    if s <= 512:
        png2 = create_png(s*2, s*2, color)
        with open(f'${ICONSET_DIR}/icon_{s}x{s}@2x.png', 'wb') as f:
            f.write(png2)
"

    iconutil -c icns "${ICONSET_DIR}" -o "${APP_DIR}/Contents/Resources/AppIcon.icns" 2>/dev/null || {
        echo "  (iconutil not available, skipping icon)"
    }
    rm -rf "${ICONSET_DIR}"
fi

# Step 6: Ad-hoc code sign
echo "→ Signing app bundle..."
codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || {
    echo "  (codesign skipped — app will still work unsigned for local use)"
}

# Step 7: Summary
echo ""
echo "=== Build complete ==="
echo ""
echo "App bundle: ${APP_DIR}"
echo ""
echo "To install, run:"
echo "  cp -r \"${APP_DIR}\" /Applications/"
echo ""
echo "Or drag '${APP_DIR}' to your Applications folder in Finder."
echo ""
echo "To launch:"
echo "  open \"/Applications/${APP_NAME}.app\""
echo ""
