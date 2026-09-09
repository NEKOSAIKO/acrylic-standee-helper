#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?用法: zsh scripts/release.sh 版本号 更新说明.md}"
NOTES="${2:?请提供更新说明文件}"
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo '版本应为 0.2.8 格式'; exit 1; }
[[ -f "$NOTES" ]] || { echo '更新说明文件不存在'; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo '请先提交所有修改'; exit 1; }
[[ "$(git branch --show-current)" == main ]] || { echo '请在 main 分支发布'; exit 1; }
git fetch origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo '请先同步并推送 main'; exit 1; }
if git ls-remote --exit-code --tags origin "refs/tags/v$VERSION" >/dev/null 2>&1; then echo '该版本标签已存在，请检查对应 Release'; exit 1; fi
zsh scripts/build-app.sh
APP='dist/亚克力立牌助手 0.2.app'
ACTUAL=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
[[ "$ACTUAL" == "$VERSION" ]] || { echo "应用版本 $ACTUAL 与请求版本 $VERSION 不一致"; exit 1; }
codesign --verify --deep --strict "$APP"
STAGE=$(mktemp -d "$PWD/dist/release.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/AcrylicStandee-Mac"
ditto "$APP" "$STAGE/AcrylicStandee-Mac/亚克力立牌助手 0.2.app"
cp docs/使用说明.md "$STAGE/AcrylicStandee-Mac/使用说明.md"
ZIP="AcrylicStandee-$VERSION-Mac.zip"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/AcrylicStandee-Mac" "dist/$ZIP"
(cd dist && shasum -a 256 "$ZIP" > SHA256SUMS.txt)
git tag "v$VERSION"
git push origin "v$VERSION"
gh release create "v$VERSION" "dist/$ZIP" dist/SHA256SUMS.txt --verify-tag --draft --title "亚克力立牌助手 $VERSION" --notes-file "$NOTES"
gh release edit "v$VERSION" --draft=false --latest
