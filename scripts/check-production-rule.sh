#!/usr/bin/env bash
# Fail when Terraform code compares a string with an environment name for
# production. The rule: an environment is production when its is_production is
# true. config/landing-zone.schema.json requires the flag on every environment,
# and each root that reads it rejects a config entry without it.
#
# Blocked, in *.tf files, for the whole words prod, production, nonprod and
# preprod (optionally followed by a separator and more text, e.g. "prod-eu"):
#   x == "prod" / "prod" != x          (equality in either order)
#   contains([..., "prod", ...], x)
#   startswith / endswith / strcontains(x, "prod")
#   regex / regexall("...prod...", x)
# Words that only start with prod (producer, product) do not match.
#
# Allowed, removed from a hit before it is checked again (so a line that holds
# an allowed comparison and a blocked one still fails):
#   - the cost/assurance profile: profile == "production" and the profile
#     validation contains(["production", "starter"], coalesce(var.profile, ...));
#   - the Vercel deployment target (modules/vercel, modules/saas only):
#     d.environment == "production" and contains(["qa", "uat", "production"], d.environment);
#   - the AWS Transit Gateway segment: contains(["prod", "nonprod"], s.segment).
#
#   scripts/check-production-rule.sh [DIR...]   (default: envs modules; CI via check-consistency.sh)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -eq 0 ]]; then set -- "${REPO_ROOT}/envs" "${REPO_ROOT}/modules"; fi

name='"[^"a-z]*(non|pre)?prod(uction)?([^"a-z][^"]*)?"'
rx='"[^"]*(non|pre)?prod(uction)?([^"a-z][^"]*)?"'
pattern="[!=]=[[:space:]]*${name}|${name}[[:space:]]*[!=]=|contains\\(\\[[^]]*${name}|(startswith|endswith|strcontains)\\([^)]*${name}|regex(all)?\\(${rx}"

hits="$(grep -rnE --include='*.tf' "${pattern}" "$@" | grep -v '/\.terraform/' |
  sed -E \
    -e 's/(var|local)\.profile[[:space:]]*[!=]=[[:space:]]*"production"//g' \
    -e 's/contains\(\["production", "starter"\], coalesce\(var\.profile, "production"\)\)//g' \
    -e '\%(^|/)modules/(vercel|saas)/%s/d\.environment[[:space:]]*==[[:space:]]*"production"//g' \
    -e '\%(^|/)modules/(vercel|saas)/%s/contains\(\["qa", "uat", "production"\], d\.environment\)//g' \
    -e 's/contains\(\["prod", "nonprod"\], s\.segment\)//g' |
  grep -E "${pattern}" || true)"
if [[ -n "${hits}" ]]; then
  echo "Production is decided from an environment name; use is_production only:" >&2
  printf '%s\n' "${hits}" >&2
  exit 1
fi
echo "check-production-rule: no name-based production checks"
