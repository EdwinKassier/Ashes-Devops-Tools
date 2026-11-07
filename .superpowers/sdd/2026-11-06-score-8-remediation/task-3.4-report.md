# Task 3.4 report
Deleted modules/gcp/stages/host and modules/gcp/network/dns-records (no root/module callers; grep clean).
scripts/check-module-usage.py now prints `experimental:` / `unreferenced:`; `--check` fails on unmarked unreferenced. Wired into `make count-check` and the terraform-plan.yml CI step.
Marked `> Status: experimental`: aws api-gateway, aws dns-records, gcp private-ca, aws vpn (wired Task 4.4), gcp slo (wired Task 5.3).
Counts: 122 -> 120 modules (GCP 60), suites 312 -> 308; README/CLAUDE.md updated. Docs fixed: README, ARCHITECTURE, saas-integration, QUICK_START, TROUBLESHOOTING (removed host precondition section), known-gaps, stage READMEs. UPGRADING.md entry added; CHANGELOG untouched (release-please), BREAKING CHANGE footer in commit.
Verified: make count-check links docs-check fmt-check consistency all pass. No validate needed (no root referenced the deleted modules; dns-anchor change is a comment).
Concerns: brief said ignore examples/ for callers, but the existing script treats 11 example-only modules as library-only (non-failing); following the brief literally would flag them. Kept existing semantics. saas-integration.md claim of GCP DNS records now points to network/dns.

## Fix round 1
- check-module-usage.py: `MODULE_USAGE_ROOT` env override; docstring fixed; marker matched via `line.strip()`; missing README = unmarked with stderr message; warns (no fail) when a wired/example-called module still carries the marker.
- New scripts/tests/test-check-module-usage.sh (auto-run by `make test-scripts` glob): unmarked fails, marked passes, CRLF, trailing whitespace, missing README, stale-marker warning.
- Verified: new test, make count-check, make shellcheck pass.
