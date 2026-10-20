#!/usr/bin/env bash
#
# Shared setup for the build scripts in tool/. Sourced, never run directly:
#
#     source "$(dirname "$0")/build_common.sh"
#
# After sourcing, the caller is in the project root and has:
#
#   VERSION      app version from pubspec.yaml, without the build number
#   BUILD_STAMP  e.g. "2026-10-20 16:13 UTC"; also compiled into the binary
#                (--dart-define=FSGE_BUILD_STAMP) and shown on the About screen
#   STAMP_SLUG   the same moment for file names, e.g. "20261020-1613"
#   OUT          where artifacts go (build/dist)
#   STAMP_DEFINE the --dart-define argument carrying BUILD_STAMP
#   step, die, require_macos, run_checks   helpers, documented below
#
# Written for the stock macOS bash 3.2 (no bash 4+ features).

# Refuse to be executed: a sourced file's `cd` and traps must affect the caller.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "build_common.sh is sourced by the other tool/ scripts, not run." >&2
  exit 1
fi

set -euo pipefail

# shellcheck disable=SC2154  # rc is assigned inside the trap string itself.
# Say where it died. `set -e` exits without a word, and a command that fails
# while printing nothing of its own (a `cd` into a missing directory, a grep
# used as a condition) is ordinary, so the bare exit status would be useless.
trap 'rc=$?; printf "\n!! %s line %s exited %s running: %s\n" \
  "${BASH_SOURCE[0]}" "$LINENO" "$rc" "$BASH_COMMAND" >&2' ERR

# Project root = the parent of tool/.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Prints a highlighted step title.
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# Prints an error and exits.
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

# Exits unless running on macOS, naming what needs it.
require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "$1 has to be built on macOS with Xcode."
}

command -v flutter >/dev/null 2>&1 || die "flutter not found in PATH"

# `|| true`, then checked: without it a pubspec with no version line makes grep
# fail, pipefail fails the pipeline, and set -e exits with no explanation.
VERSION="$(grep -m1 '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//' || true)"
[[ -n "$VERSION" ]] || die "No 'version:' line in pubspec.yaml; cannot name the artifact."
readonly VERSION

# One `date` call for both the stamp and the file names, so the READ ME and the
# archive beside it can never disagree by a minute.
BUILD_STAMP="$(date -u '+%Y-%m-%d %H:%M UTC')"
readonly BUILD_STAMP
STAMP_SLUG="$(printf '%s' "$BUILD_STAMP" | sed 's/[-:]//g; s/ \([0-9]\{4\}\) UTC/-\1/')"
# shellcheck disable=SC2034  # used by the scripts that source this file
readonly STAMP_SLUG
# shellcheck disable=SC2034
readonly STAMP_DEFINE="--dart-define=FSGE_BUILD_STAMP=$BUILD_STAMP"

readonly OUT="build/dist"
mkdir -p "$OUT"

# Fetches dependencies, then runs `flutter analyze` and `flutter test` unless
# the first argument is 1 (from --skip-checks). A build that fails its own
# tests is not worth handing to anyone.
#
# Each command checks its own status with `|| return 1`: bash ignores `set -e`
# inside a function called from an `if` or `||`, which is how build_apple.sh
# calls this, and an analyzer failure would otherwise be silently skipped.
run_checks() {
  local skip="$1"
  step "Fetching dependencies"
  flutter pub get || return 1
  if [[ "$skip" -eq 1 ]]; then
    echo "Skipping analyze and tests (--skip-checks)"
    return 0
  fi
  step "Static analysis"
  flutter analyze || return 1
  step "Tests"
  flutter test || return 1
}
