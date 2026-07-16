#!/bin/zsh
set -euo pipefail

APP="电源快捷按钮.app"
CONTENTS="$APP/Contents"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
/usr/bin/clang PowerButtons.m -o "$CONTENTS/MacOS/PowerButtons" -framework Cocoa -framework QuartzCore -framework Security -fobjc-arc
/bin/cp Info.plist "$CONTENTS/Info.plist"
/usr/bin/xattr -cr "$APP"
/usr/bin/codesign --force --sign - "$APP"

echo "已构建：$APP"
