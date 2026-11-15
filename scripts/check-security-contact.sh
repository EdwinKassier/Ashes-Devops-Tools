#!/usr/bin/env bash
# Live check: the reporting channel SECURITY.md names (GitHub private vulnerability
# reporting) is switched on. Read-only: it calls GET only and changes nothing.
#
#   scripts/check-security-contact.sh [--warn-only] [owner/repo]   (make security-contact-live)
#
# Needs `gh` with a token that can read the repository settings. This is an opt-in
# maintainer check; it is not part of `make ci`, because the setting is per repository
# and a fork that has not enabled it must not fail CI. --warn-only reports the problem
# and exits 0.
set -euo pipefail

warn_only=0
if [[ "${1:-}" == "--warn-only" ]]; then
  warn_only=1
  shift
fi

repo="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
enabled="$(gh api "repos/${repo}/private-vulnerability-reporting" --jq .enabled)"
if [[ "${enabled}" != "true" ]]; then
  echo "SECURITY.md names GitHub private vulnerability reporting, but it is OFF on ${repo}." >&2
  echo "A repository admin can enable it: Settings > Code security > Private vulnerability reporting." >&2
  [[ "${warn_only}" -eq 1 ]] && exit 0
  exit 1
fi
echo "check-security-contact: private vulnerability reporting is on for ${repo}"
