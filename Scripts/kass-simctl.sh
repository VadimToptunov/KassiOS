#!/usr/bin/env bash
#
# kass-simctl — host-side helpers KassiOS tests can't do from inside the
# simulator (permissions, location, push, a clean status bar, appearance,
# deep links, reset). Run it from your CI job *around* `xcodebuild test`.
#
# Usage:
#   kass-simctl <command> [args...]
#
# Commands (DEVICE defaults to "booted"):
#   boot            [DEVICE]                         Boot the device
#   shutdown        [DEVICE]                         Shut it down
#   erase           [DEVICE]                         Erase all content & settings
#   status-bar      [DEVICE] override|clear          Clean 9:41 bar for screenshots
#   appearance      [DEVICE] light|dark              Set UI appearance
#   permission      <BUNDLE_ID> grant|revoke|reset <SERVICE> [DEVICE]
#                                                    e.g. photos, camera, location, contacts, notifications, all
#   location        <LAT> <LON> [DEVICE]             Set simulated GPS
#   push            <BUNDLE_ID> <PAYLOAD.json> [DEVICE]  Deliver a push
#   openurl         <URL> [DEVICE]                   Open a URL / deep link
#
set -euo pipefail

die() { echo "kass-simctl: $*" >&2; exit 1; }
have_xcrun() { command -v xcrun >/dev/null 2>&1 || die "xcrun not found (install Xcode)"; }

cmd="${1:-}"; shift || true
have_xcrun

case "$cmd" in
  boot)
    device="${1:-booted}"
    xcrun simctl bootstatus "$device" -b >/dev/null 2>&1 || xcrun simctl boot "$device"
    ;;

  shutdown)
    xcrun simctl shutdown "${1:-booted}"
    ;;

  erase)
    xcrun simctl erase "${1:-booted}"
    ;;

  status-bar)
    device="booted"; action="${1:-}"
    if [ "$1" = "override" ] || [ "$1" = "clear" ]; then action="$1"; else device="$1"; action="${2:-}"; fi
    case "$action" in
      override)
        xcrun simctl status_bar "$device" override \
          --time "9:41" \
          --dataNetwork wifi --wifiMode active --wifiBars 3 \
          --cellularMode active --cellularBars 4 \
          --batteryState charged --batteryLevel 100
        ;;
      clear) xcrun simctl status_bar "$device" clear ;;
      *) die "status-bar expects: override | clear" ;;
    esac
    ;;

  appearance)
    device="booted"; mode="${1:-}"
    if [ "$1" = "light" ] || [ "$1" = "dark" ]; then mode="$1"; else device="$1"; mode="${2:-}"; fi
    [ "$mode" = "light" ] || [ "$mode" = "dark" ] || die "appearance expects: light | dark"
    xcrun simctl ui "$device" appearance "$mode"
    ;;

  permission)
    bundle="${1:?bundle id required}"; op="${2:?grant|revoke|reset required}"; service="${3:?service required}"
    device="${4:-booted}"
    xcrun simctl privacy "$device" "$op" "$service" "$bundle"
    ;;

  location)
    lat="${1:?latitude required}"; lon="${2:?longitude required}"; device="${3:-booted}"
    xcrun simctl location "$device" set "$lat","$lon"
    ;;

  push)
    bundle="${1:?bundle id required}"; payload="${2:?payload.json required}"; device="${3:-booted}"
    [ -f "$payload" ] || die "payload file not found: $payload"
    xcrun simctl push "$device" "$bundle" "$payload"
    ;;

  openurl)
    url="${1:?url required}"; device="${2:-booted}"
    xcrun simctl openurl "$device" "$url"
    ;;

  ""|-h|--help|help)
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    ;;

  *)
    die "unknown command '$cmd' (try: kass-simctl help)"
    ;;
esac
