#!/bin/bash
# Installs MiddleClick into ~/Applications and starts it now and at every login.
#
#   install.sh             install or update
#   install.sh uninstall   stop and remove everything
set -euo pipefail

name=MiddleClick
id=io.github.dimamingtrick.middleclick
app="$HOME/Applications/$name.app"
bin="$app/Contents/MacOS/$name"
agent="$HOME/Library/LaunchAgents/$id.plist"
domain="gui/$(id -u)"

[ "$(uname)" = Darwin ] || { echo "error: $name only runs on macOS" >&2; exit 1; }
[ "$(id -u)" != 0 ] || { echo "error: run this without sudo" >&2; exit 1; }

# npx runs this script through a symlink in node_modules/.bin; find the real directory.
self="${BASH_SOURCE[0]}"
while [ -L "$self" ]; do
    dir="$(cd -P "$(dirname "$self")" && pwd)"
    self="$(readlink "$self")"
    [[ "$self" == /* ]] || self="$dir/$self"
done
root="$(cd -P "$(dirname "$self")" && pwd)"

# Never touch a different app that happens to have the same name.
if [ -d "$app" ] && [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null)" != "$id" ]; then
    echo "error: $app is a different app; move it elsewhere and try again" >&2
    exit 1
fi

running() { pgrep -f "^$bin" >/dev/null; }

stop() {
    launchctl bootout "$domain/$id" 2>/dev/null || true
    pkill -f "^$bin" 2>/dev/null || true # a copy opened from Finder
    for _ in {1..50}; do
        running || launchctl print "$domain/$id" >/dev/null 2>&1 || return 0
        sleep 0.1
    done
    echo "error: could not stop the running $name" >&2
    exit 1
}

uninstall() {
    stop
    tccutil reset Accessibility "$id" >/dev/null 2>&1 || true
    rm -rf "$agent" "$app"
    echo "$name removed."
}

install() {
    local new="$root/dist/$name.app"
    codesign --verify --strict "$new" 2>/dev/null || { echo "error: $new is missing or damaged" >&2; exit 1; }

    stop
    # Accessibility access is tied to the exact binary. When it changes, drop the
    # stale grant so macOS asks again instead of listing the app as already allowed.
    cmp -s "$new/Contents/MacOS/$name" "$bin" || tccutil reset Accessibility "$id" >/dev/null 2>&1 || true

    mkdir -p "$(dirname "$app")" "$(dirname "$agent")"
    rm -rf "$app"
    ditto "$new" "$app"
    chmod +x "$bin" # in case the download dropped the executable bit
    xattr -dr com.apple.quarantine "$app" 2>/dev/null || true

    cat >"$agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$id</string>
	<key>ProgramArguments</key>
	<array>
		<string>$bin</string>
	</array>
	<key>AssociatedBundleIdentifiers</key>
	<array>
		<string>$id</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>ProcessType</key>
	<string>Interactive</string>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
</dict>
</plist>
EOF

    launchctl enable "$domain/$id"
    launchctl bootstrap "$domain" "$agent"
    for _ in {1..30}; do running && break; sleep 0.1; done
    if ! running; then
        echo "error: $name did not start; see: launchctl print $domain/$id" >&2
        exit 1
    fi
    echo "$name is running: look for the mouse icon in the menu bar."
    echo "If the icon is dimmed, allow $name in System Settings → Privacy & Security → Accessibility."
}

case "${1:-install}" in
    install) install ;;
    uninstall) uninstall ;;
    *) echo "usage: $(basename "$0") [install|uninstall]" >&2; exit 1 ;;
esac
