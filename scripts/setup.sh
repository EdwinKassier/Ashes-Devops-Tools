#!/usr/bin/env bash
set -euo pipefail

# Required tool versions — all derived from .tool-versions (single source of truth,
# shared with CI via terraform-plan.yml) so this script can never drift from the pins.
# The second argument is a fallback used only if .tool-versions can't be read/parsed.
_TOOL_VERSIONS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.tool-versions"
_tool_version() {
  local v
  v="$(awk -v t="$1" '$1 == t {print $2; exit}' "${_TOOL_VERSIONS_FILE}" 2>/dev/null || true)"
  printf '%s' "${v:-$2}"
}
REQUIRED_TERRAFORM_VERSION="$(_tool_version terraform 1.14.3)"
REQUIRED_TFLINT_VERSION="$(_tool_version tflint 0.62.0)"
REQUIRED_TRIVY_VERSION="$(_tool_version trivy 0.70.0)"
REQUIRED_TERRAFORM_DOCS_VERSION="$(_tool_version terraform-docs 0.19.0)"
REQUIRED_CHECKOV_VERSION="$(_tool_version checkov 3.2.0)"

install_with_brew() { brew install "$1"; }
install_with_apt() { sudo apt-get update && sudo apt-get install -y "$1"; }
install_with_dnf() { sudo dnf install -y "$1"; }
install_with_pacman() { sudo pacman -S --noconfirm "$1"; }

install_package() {
  local package="$1"
  if command -v brew >/dev/null 2>&1; then
    install_with_brew "$package"
  elif command -v apt-get >/dev/null 2>&1; then
    install_with_apt "$package"
  elif command -v dnf >/dev/null 2>&1; then
    install_with_dnf "$package"
  elif command -v pacman >/dev/null 2>&1; then
    install_with_pacman "$package"
  else
    echo "ERROR: No supported package manager found. Install $package manually." >&2
    exit 1
  fi
}

install_pip_package() { python3 -m pip install --user "$1==$2"; }

# Returns the installed version of a binary, or empty string if not installed.
installed_version() {
  local bin="$1" flag="${2:---version}"
  command -v "$bin" >/dev/null 2>&1 || { echo ""; return; }
  "$bin" "$flag" 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true
}

check_or_install() {
  local tool="$1" required="$2"
  local installed
  installed=$(installed_version "$tool")
  if [[ -z "$installed" ]]; then
    echo "Installing $tool $required ..."
    return 1  # caller handles installation
  elif [[ "$installed" != "$required" ]]; then
    echo "WARNING: $tool $installed is installed but $required is required (matches CI/.tool-versions)."
    echo "         Run 'mise install' or update manually to avoid plan drift."
    return 1  # version mismatch — caller can reinstall if it has a versioned installer
  else
    echo "$tool $installed OK"
    return 0
  fi
}

# Terraform — must be installed manually (or via mise/tfenv) to guarantee exact version.
# Package managers resolve to latest, which may differ from CI. Always instruct explicitly.
terraform_installed=$(installed_version terraform)
if [[ -z "$terraform_installed" ]]; then
  echo "Terraform not found. Install $REQUIRED_TERRAFORM_VERSION from https://developer.hashicorp.com/terraform/downloads"
  echo "Tip: use 'mise install terraform' or 'tfenv install $REQUIRED_TERRAFORM_VERSION'"
elif [[ "$terraform_installed" != "$REQUIRED_TERRAFORM_VERSION" ]]; then
  echo "WARNING: terraform $terraform_installed is installed but $REQUIRED_TERRAFORM_VERSION is required."
  echo "         Run 'mise install terraform' or 'tfenv install $REQUIRED_TERRAFORM_VERSION' to align with CI."
else
  echo "terraform $terraform_installed OK"
fi

# TFLint — package manager install may resolve to a different minor/patch version.
# Version mismatch is treated as a warning; only absent installations trigger auto-install.
tflint_installed=$(installed_version tflint)
if [[ -z "$tflint_installed" ]]; then
  echo "Installing tflint (version may differ from $REQUIRED_TFLINT_VERSION; pin with mise for exact match) ..."
  install_package tflint
elif [[ "$tflint_installed" != "$REQUIRED_TFLINT_VERSION" ]]; then
  echo "WARNING: tflint $tflint_installed is installed but $REQUIRED_TFLINT_VERSION is required."
  echo "         Run 'mise install tflint' to align with CI."
else
  echo "tflint $tflint_installed OK"
fi

# Trivy — the IaC misconfiguration scanner behind `make security` and the CI gate.
# (tfsec is end-of-life — Aqua folded it into Trivy — and is no longer installed.)
# `make security` refuses a version other than .tool-versions, so a mismatch here is
# reported loudly; install the exact version with mise/asdf if the package manager
# resolves to a different one.
trivy_installed=$(installed_version trivy)
if [[ -z "$trivy_installed" ]]; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing trivy (version may differ from $REQUIRED_TRIVY_VERSION; pin with mise for exact match) ..."
    brew install trivy
  else
    echo "trivy not found. Install $REQUIRED_TRIVY_VERSION: 'mise install trivy@$REQUIRED_TRIVY_VERSION'"
    echo "or see https://trivy.dev/latest/getting-started/installation/"
  fi
elif [[ "$trivy_installed" != "$REQUIRED_TRIVY_VERSION" ]]; then
  echo "WARNING: trivy $trivy_installed is installed but $REQUIRED_TRIVY_VERSION is required (make security will refuse)."
  echo "         Run 'mise install trivy@$REQUIRED_TRIVY_VERSION' to align with CI."
else
  echo "trivy $trivy_installed OK"
fi

# terraform-docs
tfdocs_installed=$(installed_version terraform-docs)
if [[ -z "$tfdocs_installed" ]]; then
  echo "Installing terraform-docs (version may differ from $REQUIRED_TERRAFORM_DOCS_VERSION; pin with mise for exact match) ..."
  install_package terraform-docs
elif [[ "$tfdocs_installed" != "$REQUIRED_TERRAFORM_DOCS_VERSION" ]]; then
  echo "WARNING: terraform-docs $tfdocs_installed is installed but $REQUIRED_TERRAFORM_DOCS_VERSION is required."
  echo "         Run 'mise install terraform-docs' to align with CI."
else
  echo "terraform-docs $tfdocs_installed OK"
fi

# pre-commit
if ! command -v pre-commit >/dev/null 2>&1; then
  echo "Installing pre-commit ..."
  python3 -m pip install --user pre-commit
else
  echo "pre-commit $(installed_version pre-commit) OK"
fi

# Checkov
checkov_installed=$(installed_version checkov -V 2>/dev/null || installed_version checkov --version 2>/dev/null || echo "")
if [[ -z "$checkov_installed" ]]; then
  echo "Installing checkov $REQUIRED_CHECKOV_VERSION ..."
  install_pip_package checkov "$REQUIRED_CHECKOV_VERSION"
elif [[ "$checkov_installed" != "$REQUIRED_CHECKOV_VERSION" ]]; then
  echo "WARNING: checkov $checkov_installed is installed but $REQUIRED_CHECKOV_VERSION is required."
else
  echo "checkov $checkov_installed OK"
fi

echo ""
echo "Setup complete. All version warnings above indicate CI/local drift — address with 'mise install'."
