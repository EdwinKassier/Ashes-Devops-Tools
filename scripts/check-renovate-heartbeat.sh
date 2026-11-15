#!/usr/bin/env bash
# Renovate heartbeat: Renovate has touched an issue or a pull request in this
# repository (its Dependency Dashboard issue, a lockfile-maintenance PR, a
# toolchain PR) within the last MAX_AGE_DAYS days. "Renovate never ran" must
# show as a red check, not as silence. Read-only: one GET call, changes nothing.
#
#   scripts/check-renovate-heartbeat.sh [--required] [--max-age-days N] [owner/repo]
#
# Needs `gh` with a token that can read issues and pull requests, and jq.
# Without --required a missing or stale heartbeat is a warning and the script
# exits 0, so a fork that does not use Renovate does not fail. With --required
# it is an error (exit 1). The Dependency heartbeat workflow passes --required
# on the upstream repository and on any repository that sets the
# RENOVATE_HEARTBEAT_REQUIRED variable to true.
set -euo pipefail

required=0
max_age_days=8
while [ "$#" -gt 0 ]; do
  case "$1" in
    --required) required=1; shift ;;
    --max-age-days)
      max_age_days="${2:?--max-age-days needs a number}"
      shift 2
      ;;
    -*) echo "usage: $0 [--required] [--max-age-days N] [owner/repo]" >&2; exit 2 ;;
    *) break ;;
  esac
done
case "${max_age_days}" in
  '' | *[!0-9]*) echo "--max-age-days must be a whole number of days" >&2; exit 2 ;;
esac

repo="${1:-${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}}"

problem() {
  if [ "${required}" -eq 1 ]; then
    echo "::error::$1"
    exit 1
  fi
  echo "::warning::$1 (not required here: pass --required or set the RENOVATE_HEARTBEAT_REQUIRED repository variable to true to fail instead)"
  exit 0
}

# The issues endpoint lists pull requests too, so one call covers the
# Dependency Dashboard issue and every Renovate PR. Newest update first.
items="$(gh api "repos/${repo}/issues?state=all&creator=renovate%5Bbot%5D&sort=updated&direction=desc&per_page=1")"
latest="$(jq -r '.[0] // empty | "\(.updated_at) \(((now - (.updated_at | fromdateiso8601)) / 86400) | floor) \(.html_url)"' <<<"${items}")"

if [ -z "${latest}" ]; then
  problem "No issue or pull request from renovate[bot] in ${repo}: the Renovate GitHub App is not installed or has never run."
fi

read -r updated age_days url <<<"${latest}"
echo "Renovate last updated ${url} at ${updated} (${age_days} days ago; limit ${max_age_days})."
if [ "${age_days}" -gt "${max_age_days}" ]; then
  problem "Renovate has not updated an issue or pull request in ${repo} for ${age_days} days (limit ${max_age_days})."
fi
echo "check-renovate-heartbeat: OK"
