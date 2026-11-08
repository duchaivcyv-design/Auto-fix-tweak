#!/usr/bin/env bash
# Build Auto Fix Tweak inside WSL/Linux with Theos installed.
set -euo pipefail
cd "$(dirname "$0")"

export THEOS="${THEOS:-$HOME/theos}"
SCHEME="${1:-all}"

if [[ ! -d "$THEOS" ]]; then
    echo "ERROR: Theos not found at $THEOS" >&2
    exit 1
fi

# Files copied from a Windows mount can be 0777; dpkg-deb rejects that.
find layout -type d -exec chmod 0755 {} +
find layout -type f -exec chmod 0644 {} +
chmod 0755 layout/DEBIAN/postinst layout/DEBIAN/prerm layout/DEBIAN/postrm build.sh
chmod 0644 control control.rootless control.rootful AutoFixTweak.plist Makefile 2>/dev/null || true
mkdir -p dist

build_one() {
    local scheme="$1"
    cp "control.$scheme" control
    make clean >/dev/null 2>&1 || true
    rm -rf .theos obj packages
    make package FINALPACKAGE=1 PACKAGE_SCHEME="$scheme"
    cp packages/*.deb dist/
}

if [[ "$SCHEME" == "rootless" || "$SCHEME" == "all" ]]; then
    build_one rootless
fi

if [[ "$SCHEME" == "rootful" || "$SCHEME" == "all" ]]; then
    build_one rootful
fi

cp control.rootless control

echo
echo "=== Artifacts ==="
ls -l dist
