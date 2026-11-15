#!/usr/bin/env bash
# Print the SHA-256 line for a CI tool download that is checked against a pinned
# digest, so a reviewer refreshes the digest in the same Renovate toolchain PR
# that bumps the version. Downloads the exact release asset CI downloads.
#
#   scripts/tool-checksums.sh <tool> <version>
#
# Tools and the env names they refresh in .github/workflows/terraform-plan.yml:
#   - opa: OPA_SHA256 for opa_linux_amd64_static (job: OPA Policy Tests)
#   - shellcheck: SC_SHA256 for shellcheck-v<version>.linux.x86_64.tar.xz (job: ShellCheck)
# terraform-docs needs no entry: CI checks it against the upstream checksum file.
set -euo pipefail

usage() { echo "usage: $0 <opa|shellcheck> <version, for example 1.22.2>" >&2; exit 2; }
[ "$#" -eq 2 ] || usage
tool="$1"
version="${2#v}"
case "${version}" in
  '' | *[!0-9.]*) echo "version must look like 1.22.2, got '$2'" >&2; exit 2 ;;
esac

case "${tool}" in
  opa)
    env_name=OPA_SHA256
    url="https://github.com/open-policy-agent/opa/releases/download/v${version}/opa_linux_amd64_static"
    ;;
  shellcheck)
    env_name=SC_SHA256
    url="https://github.com/koalaman/shellcheck/releases/download/v${version}/shellcheck-v${version}.linux.x86_64.tar.xz"
    ;;
  *) echo "unknown tool '${tool}' (supported: opa, shellcheck)" >&2; usage ;;
esac

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'; else shasum -a 256 | awk '{print $1}'; fi
}

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT
curl -sSfL -o "${tmp}" "${url}"
digest="$(sha256 <"${tmp}")"
echo "# ${url}"
echo "${env_name}: \"${digest}\""
