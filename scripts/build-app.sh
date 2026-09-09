#!/bin/zsh
set -euo pipefail
BASE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$BASE/src"
APP="$BASE/dist/亚克力立牌助手 0.2.app"
SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
SWIFT_EXTRA_FLAGS=()
# Optional local toolchain workaround; ordinary Xcode installations do not need this.
if [[ -n "${SWIFT_VFS_OVERLAY:-}" ]]; then SWIFT_EXTRA_FLAGS=(-vfsoverlay "$SWIFT_VFS_OVERLAY"); fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BASE/build"
cp "$SRC/acrylic-geometry.js" "$SRC/curve-fit.js" "$SRC/illustrator-helper.jsx" "$APP/Contents/Resources/"
cp "$BASE/assets/sample.png" "$APP/Contents/Resources/"
cp "$BASE/assets/AppIcon.icns" "$APP/Contents/Resources/"
cp "$BASE/vendor/Clipper2/LICENSE" "$APP/Contents/Resources/Clipper2-LICENSE.txt"
for source in clipper.engine clipper.offset clipper.rectclip; do
 clang++ -std=c++17 -O3 -isysroot "$SDK" -target arm64-apple-macosx14.0 -I "$BASE/vendor/Clipper2/CPP/Clipper2Lib/include" -c "$BASE/vendor/Clipper2/CPP/Clipper2Lib/src/$source.cpp" -o "$BASE/build/$source.o"
done
clang++ -std=c++17 -O3 -isysroot "$SDK" -target arm64-apple-macosx14.0 -I "$BASE/vendor/Clipper2/CPP/Clipper2Lib/include" -c "$SRC/NativeGeometry.cpp" -o "$BASE/build/NativeGeometry.o"
python3 - "$APP" <<'PY'
import plistlib,sys
from pathlib import Path
info={'CFBundleIdentifier':'cn.neko.acrylicstandee.v02','CFBundleName':'亚克力立牌助手 0.2','CFBundleDisplayName':'亚克力立牌助手 0.2','CFBundleExecutable':'AcrylicStandee','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.2.7','CFBundleVersion':'9','CFBundleIconFile':'AppIcon.icns','LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True,'NSAppleEventsUsageDescription':'用于新建并另存 CMYK 立牌与工厂说明，不修改当前文档。','NSPrincipalClass':'NSApplication'}
(Path(sys.argv[1])/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
swiftc -O -swift-version 5 -sdk "$SDK" -target arm64-apple-macosx14.0 -module-cache-path "$BASE/build/module-cache" ${SWIFT_EXTRA_FLAGS[@]} -import-objc-header "$SRC/NativeGeometry.h" "$SRC/GeometryEngine.swift" "$SRC/WhiteInk.swift" "$SRC/PreviewCanvas.swift" "$SRC/ExportLayout.swift" "$SRC/ExportPackage.swift" "$SRC/FactorySheet.swift" "$SRC/CMYKPDF.swift" "$SRC/Tutorial.swift" "$SRC/main.swift" "$BASE/build/NativeGeometry.o" "$BASE/build/clipper.engine.o" "$BASE/build/clipper.offset.o" "$BASE/build/clipper.rectclip.o" -o "$APP/Contents/MacOS/AcrylicStandee" -framework AppKit -framework JavaScriptCore -framework ImageIO -framework UniformTypeIdentifiers -framework Accelerate -lc++
codesign --force --sign - "$APP"
echo "Built: $APP"
