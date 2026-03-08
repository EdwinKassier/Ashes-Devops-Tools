#!/usr/bin/env bash
set -euo pipefail

install_with_brew() {
  brew install "$1"
}

install_with_apt() {
  sudo apt-get update
  sudo apt-get install -y "$1"
}

install_with_dnf() {
  sudo dnf install -y "$1"
}

install_with_pacman() {
  sudo pacman -S --noconfirm "$1"
}

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
    echo "No supported package manager found for $package" >&2
    exit 1
  fi
}

install_pip_package() {
  python3 -m pip install --user "$1"
}

command -v terraform >/dev/null 2>&1 || echo "Terraform must be installed separately from https://developer.hashicorp.com/terraform/downloads"
command -v tflint >/dev/null 2>&1 || install_package tflint
command -v tfsec >/dev/null 2>&1 || install_package tfsec
command -v terraform-docs >/dev/null 2>&1 || install_package terraform-docs
command -v pre-commit >/dev/null 2>&1 || install_pip_package pre-commit
command -v checkov >/dev/null 2>&1 || install_pip_package checkov

echo "Tool installation complete."
