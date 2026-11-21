#!/bin/bash
# Signs a built GupWorks3.app ad hoc with the push entitlement (a233), so the TestFlight export keeps it: the archive
# is built unsigned (CODE_SIGNING_ALLOWED=NO, see the testflight job), and an unsigned app carries no entitlements
# for the export's re-signing to keep. Then checks that the signature carries aps-environment.
#   push-entitlements.sh <path to GupWorks3.app> <production|development>
set -euo pipefail
app="$1" env="${2:-production}"
ent="$(mktemp -t gw3-push-XXXXXX).entitlements"
cat > "$ent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>aps-environment</key><string>$env</string>
</dict></plist>
PLIST
# a234: the watch app inside is signed first (ad hoc, no push of its own: the iPhone's notifications reach the watch),
# else the outer signature refuses the unsigned code nested in it; the export re-signs both
for nested in "$app"/Watch/*.app "$app"/PlugIns/*.app; do
  if [ -d "$nested" ]; then codesign --force --sign - --generate-entitlement-der "$nested"; fi
done
codesign --force --sign - --entitlements "$ent" --generate-entitlement-der "$app"
got=$(codesign -d --entitlements - --xml "$app" 2>/dev/null || codesign -d --entitlements - "$app" 2>/dev/null)
rm -f "$ent"
if ! printf '%s' "$got" | grep -q "aps-environment"; then
  echo "::error title=Push entitlement::$app has no aps-environment after signing"
  exit 1
fi
echo "push entitlement ($env) on $(basename "$app")"
