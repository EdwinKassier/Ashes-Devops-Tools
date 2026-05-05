#!/usr/bin/env bash
set -euo pipefail

# Required tool versions — kept in sync with .tool-versions and CI (terraform-plan.yml).
REQUIRED_TERRAFORM_VERSION="1.9.8"
REQUIRED_TFLINT_VERSION="0.62.0"
REQUIRED_TFSEC_VERSION="1.28.6"
REQUIRED_TERRAFORM_DOCS_VERSION="0.19.0"
REQUIRED_CHECKOV_VERSION="3.2.0"

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
  "$bin" "$flag" 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
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
  else
    echo "$tool $installed OK"
  fi
  return 0
}

# Terraform
if ! check_or_install "terraform" "$REQUIRED_TERRAFORM_VERSION"; then
  echo "Install Terraform $REQUIRED_TERRAFORM_VERSION from https://developer.hashicorp.com/terraform/downloads"
  echo "Tip: use 'mise install terraform' or 'tfenv install $REQUIRED_TERRAFORM_VERSION'"
fi

# TFLint
if ! check_or_install "tflint" "$REQUIRED_TFLINT_VERSION"; then
  install_package tflint
fi

# TFSec
if ! check_or_install "tfsec" "$REQUIRED_TFSEC_VERSION"; then
  install_package tfsec
fi

# terraform-docs
if ! check_or_install "terraform-docs" "$REQUIRED_TERRAFORM_DOCS_VERSION"; then
  install_package terraform-docs
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
