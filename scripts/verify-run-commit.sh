#!/usr/bin/env bash
# Compare the source commit of the latest HCP Terraform run with the tagged
# commit (the release-metadata workflow, .github/workflows/terraform-apply.yml).
#
# stdin: a runs API response fetched with
#   ?page[size]=1&include=configuration_version.ingress_attributes
# The run's commit is the `commit-sha` of the ingress attributes that its
# configuration version names. `include=configuration_version` alone does not
# return them.
#
# stdout: commit_match=true (same commit) or commit_match=false (another
# commit; the workflow holds the release). Exits 1, printing nothing to stdout,
# when the run has no source commit (a CLI or API run, or a response without
# the ingress attributes): a release must point at a VCS run of the tag.
#
#   TAG_COMMIT=<sha> scripts/verify-run-commit.sh < response.json
set -euo pipefail

if [ -z "${TAG_COMMIT:-}" ]; then
  echo "::error::TAG_COMMIT must be set to the tagged commit SHA." >&2
  exit 1
fi

response="$(cat)"
if ! jq -e '(.data | type == "array") and (.data | length > 0)' <<<"${response}" >/dev/null 2>&1; then
  echo "::error::The runs API response has no run." >&2
  exit 1
fi

run_commit="$(jq -r '
  (.data[0].relationships["configuration-version"].data.id // "") as $cv
  | ([.included[]? | select(.type == "configuration-versions" and .id == $cv)
      | .relationships["ingress-attributes"].data.id // empty] | .[0] // "") as $ia
  | ([.included[]? | select(.type == "ingress-attributes" and .id == $ia)
      | .attributes["commit-sha"] // empty] | .[0] // "")
' <<<"${response}")"

if [ -z "${run_commit}" ]; then
  echo "::error::The latest run has no source commit (a CLI or API run, or no ingress attributes in the response);" \
    "a release must point at a VCS run of ${TAG_COMMIT}. No release is published." >&2
  exit 1
fi

if [ "${run_commit}" = "${TAG_COMMIT}" ]; then
  echo "commit_match=true"
else
  echo "commit_match=false"
  echo "::warning::Run commit ${run_commit} != tag commit ${TAG_COMMIT}; release held." >&2
fi
