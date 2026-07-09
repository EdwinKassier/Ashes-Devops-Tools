#!/usr/bin/env bash
set -euo pipefail

# active-providers.sh
#
# Lists, for each deployable root under envs/*, which cloud/SaaS provider(s)
# it declares in its required_providers block. Answers "what can I deploy /
# what's active here" without having to open every root's versions.tf.
#
# Provider source strings are mapped to friendly names:
#   hashicorp/aws                          -> aws
#   hashicorp/google (+ google-beta)       -> gcp
#   supabase/supabase                      -> supabase
#   vercel/vercel                          -> vercel
#
# A root is any envs/*/ directory that contains at least one .tf file.
# Providers are parsed from all .tf files in the root (typically versions.tf).
#
# Usage: scripts/active-providers.sh

cd "$(dirname "$0")/.."

# Map a root directory's .tf source strings to a sorted, comma-separated
# list of friendly provider names. Prints nothing if no known provider found.
providers_for_root() {
  local dir="$1"
  local sources
  # Concatenate all .tf in the root and pull out provider source strings.
  sources="$(cat "$dir"/*.tf 2>/dev/null || true)"

  local names=()
  if grep -Eq '"hashicorp/aws"' <<<"$sources"; then
    names+=("aws")
  fi
  if grep -Eq '"hashicorp/google(-beta)?"' <<<"$sources"; then
    names+=("gcp")
  fi
  if grep -Eq '"supabase/supabase"' <<<"$sources"; then
    names+=("supabase")
  fi
  if grep -Eq '"vercel/vercel"' <<<"$sources"; then
    names+=("vercel")
  fi

  if [ ${#names[@]} -eq 0 ]; then
    return
  fi

  # De-dup (gcp maps from two sources) and sort for stable output.
  printf '%s\n' "${names[@]}" | sort -u | paste -sd, -
}

# Collect envs/* roots (dirs containing at least one .tf), sorted by name.
collect_roots() {
  find envs -mindepth 1 -maxdepth 1 -type d ! -name '.terraform' | while read -r dir; do
    if find "$dir" -maxdepth 1 -name '*.tf' | grep -q .; then
      echo "$dir"
    fi
  done | sort
}

main() {
  local roots=()
  while IFS= read -r line; do roots+=("$line"); done < <(collect_roots)

  if [ ${#roots[@]} -eq 0 ]; then
    echo "No deployable roots found under envs/ (no directory contains a .tf file)." >&2
    exit 0
  fi

  printf '%-24s %s\n' "ROOT" "PROVIDERS"
  printf '%-24s %s\n' "----" "---------"

  local dir name provs
  for dir in "${roots[@]}"; do
    name="$(basename "$dir")"
    provs="$(providers_for_root "$dir")"
    if [ -z "$provs" ]; then
      provs="(none detected)"
    fi
    printf '%-24s %s\n' "$name" "$provs"
  done

  echo
  echo "Legend: aws=hashicorp/aws  gcp=hashicorp/google(+google-beta)  supabase=supabase/supabase  vercel=vercel/vercel"
}

main "$@"
