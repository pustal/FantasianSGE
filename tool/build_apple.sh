#!/usr/bin/env bash
#
# Builds every Apple artifact in one go: the macOS app, the iOS Simulator app
# and, with --device, the unsigned iOS .ipa as well. Checks (analyze + tests)
# run once, up front, instead of once per build.
#
# Usage:
#   tool/build_apple.sh [--device] [--skip-checks] [extra flutter build arguments]
#
# A failing platform does not stop the others; the summary lists what failed
# and the exit status is non-zero if anything did. Artifacts land in
# build/dist/, each with a READ ME FIRST.

# Not `set -e` here: each platform's failure is recorded rather than fatal.
# build_common.sh turns it on, so it is switched back off after sourcing.
# shellcheck source=tool/build_common.sh
source "$(dirname "$0")/build_common.sh"
set +e
trap - ERR

require_macos "The Apple apps"

DEVICE=0
SKIP_CHECKS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE=1; shift ;;
    --skip-checks) SKIP_CHECKS=1; shift ;;
    *) break ;;
  esac
done

# Checks once here; the per-platform scripts then skip them.
run_checks "$SKIP_CHECKS" || die "Analysis or tests failed; nothing was built."

succeeded=()
failed=()

# Runs one build script, recording the outcome instead of aborting.
run() {
  local name="$1"
  shift
  printf '\n\033[1;35m════ %s ════\033[0m\n' "$name"
  if "$@"; then
    succeeded+=("$name")
  else
    failed+=("$name")
    echo "!! $name failed; carrying on with the rest" >&2
  fi
}

run "macOS" tool/build_macos_unsigned.sh --skip-checks "$@"
run "iOS Simulator" tool/build_ios_test.sh --skip-checks "$@"
if [[ "$DEVICE" -eq 1 ]]; then
  run "iOS device (unsigned)" tool/build_ios_test.sh --device --skip-checks "$@"
fi

step "Summary"
for name in "${succeeded[@]:-}"; do
  [[ -n "$name" ]] && echo "  built    $name"
done
for name in "${failed[@]:-}"; do
  [[ -n "$name" ]] && echo "  FAILED   $name"
done
echo
echo "In $OUT:"
for entry in "$OUT"/*; do
  echo "  ${entry##*/}"
done

[[ ${#failed[@]} -eq 0 ]] || exit 1
