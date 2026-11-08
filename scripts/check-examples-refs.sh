#!/usr/bin/env bash
# Verify that repo references in the system-design examples are real.
#   bash scripts/check-examples-refs.sh [dir]     (default: examples/system-design)
#
# Checks every ```hcl and ```yaml fence in *.md under <dir>:
#   - module `source` paths resolve to a directory under modules/
#   - top-level module arguments are declared as variables in that module
#   - yaml key paths (first two levels) exist in config/landing-zone.schema.json
# and every backticked `envs/<path>` (prose or fence) resolves to a directory.
# Raw `resource` blocks are not checked. Prints `file:line: <kind> <ref> not
# found` per problem; exit 0 when clean, 1 otherwise.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${1:-${REPO_ROOT}/examples/system-design}"
SCHEMA="${REPO_ROOT}/config/landing-zone.schema.json"

[[ -d "${DIR}" ]] || exit 0

problems=0
report() { # file line kind ref
  printf '%s:%s: %s %s not found\n' "$1" "$2" "$3" "$4"
  problems=$((problems + 1))
}

META_ARGS=" source count for_each providers depends_on "

# ---- module block state (per hcl fence) ----
in_mod=0 depth=0 mod_src="" mod_src_line=0 mod_name="" mod_line=0 heredoc=""
args=()

reset_mod() { in_mod=0; depth=0; mod_src=""; mod_src_line=0; mod_name=""; mod_line=0; args=(); }

finish_mod() { # file
  local f="$1" norm a name ln
  if [[ -z "${mod_src}" ]]; then reset_mod; return; fi
  # Registry / git / other non-local sources are out of scope.
  if [[ "${mod_src}" != ./* && "${mod_src}" != ../* && "${mod_src}" != modules/* ]]; then
    reset_mod
    return
  fi
  norm="${mod_src}"
  while [[ "${norm}" == ./* || "${norm}" == ../* ]]; do
    norm="${norm#./}"
    norm="${norm#../}"
  done
  if [[ "${norm}" != modules/* || ! -d "${REPO_ROOT}/${norm}" ]]; then
    report "${f}" "${mod_src_line}" "module-source" "${mod_src}"
    reset_mod
    return
  fi
  for a in "${args[@]+"${args[@]}"}"; do
    ln="${a%%:*}"
    name="${a#*:}"
    [[ "${META_ARGS}" == *" ${name} "* ]] && continue
    if ! grep -qsE "^[[:space:]]*variable[[:space:]]+\"${name}\"" "${REPO_ROOT}/${norm}"/*.tf; then
      report "${f}" "${ln}" "module-input[${norm}]" "${name}"
    fi
  done
  reset_mod
}

# ---- yaml state ----
y_top="" y_child_indent=-1
schema_has() { jq -e --arg p "$1" 'getpath(($p|split(".")|map(["properties",.])|add)) != null' "${SCHEMA}" >/dev/null 2>&1; }
schema_parent_free() { # parent has no explicit properties -> children unconstrained
  jq -e --arg p "$1" 'getpath(($p|split(".")|map(["properties",.])|add)) as $n | ($n|type=="object") and ($n|has("properties")|not)' "${SCHEMA}" >/dev/null 2>&1
}

check_yaml_line() { # file line text
  local f="$1" ln="$2" t="$3" indent key
  [[ "${t}" =~ ^[[:space:]]*(#|$) ]] && return
  [[ "${t}" =~ ^[[:space:]]*- ]] && return
  indent="${t%%[! ]*}"
  indent=${#indent}
  if [[ ${indent} -eq 0 ]]; then
    if [[ "${t}" =~ ^([A-Za-z0-9_-]+): ]]; then
      key="${BASH_REMATCH[1]}"
      y_top="${key}"; y_child_indent=-1
      schema_has "${key}" || { report "${f}" "${ln}" "yaml-key" "${key}"; y_top=""; }
    fi
    return
  fi
  [[ -z "${y_top}" ]] && return
  if [[ ${y_child_indent} -lt 0 ]]; then y_child_indent=${indent}; fi
  [[ ${indent} -ne ${y_child_indent} ]] && return
  if [[ "${t}" =~ ^[[:space:]]+([A-Za-z0-9_-]+): ]]; then
    key="${BASH_REMATCH[1]}"
    schema_parent_free "${y_top}" && return
    schema_has "${y_top}.${key}" || report "${f}" "${ln}" "yaml-key" "${y_top}.${key}"
  fi
}

check_file() {
  local f="$1" rel="$2" lang ln text stripped o c
  # awk emits: line<TAB>lang<TAB>text for every line inside an hcl/yaml fence.
  while IFS=$'\t' read -r ln lang text; do
    if [[ "${lang}" == "hcl" ]]; then
      if [[ ${in_mod} -eq 0 ]]; then
        if [[ "${text}" =~ ^[[:space:]]*module[[:space:]]+\"([^\"]+)\"[[:space:]]*\{ ]]; then
          in_mod=1; depth=0; mod_name="${BASH_REMATCH[1]}"; mod_line="${ln}"
          # single-line block: capture an inline source
          if [[ "${text}" =~ \{[[:space:]]*source[[:space:]]*=[[:space:]]*\"([^\"]*)\" ]]; then
            mod_src="${BASH_REMATCH[1]}"; mod_src_line="${ln}"
          fi
        else
          continue
        fi
      fi
      if [[ -n "${heredoc}" ]]; then
        [[ "${text//[[:space:]]/}" == "${heredoc}" ]] && heredoc=""
        continue
      fi
      [[ "${text}" =~ ^[[:space:]]*(#|//) ]] && continue
      if [[ ${depth} -eq 1 ]]; then
        if [[ "${text}" =~ ^[[:space:]]*source[[:space:]]*=[[:space:]]*\"([^\"]*)\" ]]; then
          mod_src="${BASH_REMATCH[1]}"; mod_src_line="${ln}"
        elif [[ "${text}" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_-]*)[[:space:]]*= ]]; then
          args+=("${ln}:${BASH_REMATCH[1]}")
        fi
      fi
      stripped="$(sed -E 's/"[^"]*"//g' <<<"${text}")"
      o="${stripped//[^\{]/}"; c="${stripped//[^\}]/}"
      depth=$((depth + ${#o} - ${#c}))
      if [[ "${text}" =~ \<\<-?[[:space:]]*\"?([A-Za-z_][A-Za-z0-9_]*)\"? ]]; then
        heredoc="${BASH_REMATCH[1]}"
      fi
      if [[ ${depth} -le 0 ]]; then finish_mod "${rel}"; fi
    elif [[ "${lang}" == "yaml" ]]; then
      check_yaml_line "${rel}" "${ln}" "${text}"
    elif [[ "${lang}" == "END" ]]; then
      if [[ ${in_mod} -eq 1 ]]; then
        printf '%s:%s: unclosed module "%s" block at end of fence (checks skipped)\n' "${rel}" "${mod_line}" "${mod_name}"
        problems=$((problems + 1))
        reset_mod
      fi
      heredoc=""
      y_top=""; y_child_indent=-1
    fi
  done < <(awk '
    /^[[:space:]]*```/ {
      if (inf) { print NR "\tEND\t"; inf = 0; lang = ""; next }
      l = $0; sub(/^[[:space:]]*```/, "", l); sub(/[[:space:]].*$/, "", l)
      if (l == "hcl" || l == "terraform" || l == "tf") { inf = 1; lang = "hcl" }
      else if (l == "yaml" || l == "yml") { inf = 1; lang = "yaml" }
      else if (0) { } else { inf = 2 }
      next
    }
    inf == 1 { printf "%d\t%s\t%s\n", NR, lang, $0 }
    inf == 2 { }
  ' "${f}")

  # backticked envs/ paths anywhere in the file
  while IFS=: read -r ln ref; do
    ref="${ref#\`}"; ref="${ref%\`}"
    ref="${ref%/}"
    [[ -e "${REPO_ROOT}/${ref}" ]] || report "${rel}" "${ln}" "envs-path" "${ref}"
  done < <(grep -noE '`envs/[A-Za-z0-9_./-]+`' "${f}" || true)
}

while IFS= read -r f; do
  rel="${f#"${DIR}/"}"
  check_file "${f}" "${rel}"
done < <(find "${DIR}" -type f -name '*.md' | LC_ALL=C sort)

[[ ${problems} -eq 0 ]]
