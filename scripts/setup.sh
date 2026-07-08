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

# TFSec — download specific binary release from GitHub to guarantee exact version.
# Package managers (brew, apt) may resolve to a different minor version at install time.
# Picks a checksum-verification command that works on both macOS (no sha256sum by
# default) and Linux. Prints the command (as a string to eval) to stdout.
checksum_check_cmd() {
  local checksum_file="$1" binary="$2"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    # macOS ships `shasum`, not GNU coreutils' `sha256sum`.
    echo "grep '${binary}' '${checksum_file}' | shasum -a 256 -c --status"
  else
    echo "grep '${binary}' '${checksum_file}' | sha256sum -c --status"
  fi
}

# Chooses a writable install prefix without hardcoding /usr/local/bin — respects the
# Homebrew prefix (e.g. /opt/homebrew on Apple Silicon) and falls back to a
# user-writable bin directory on PATH.
choose_install_dir() {
  if command -v brew >/dev/null 2>&1; then
    local brew_prefix
    brew_prefix=$(brew --prefix)
    if [[ -w "${brew_prefix}/bin" ]]; then
      echo "${brew_prefix}/bin"
      return
    fi
  fi
  if [[ -w "/usr/local/bin" ]]; then
    echo "/usr/local/bin"
    return
  fi
  # Fall back to a per-user bin directory; ensure it exists and is on PATH.
  local user_bin="${HOME}/.local/bin"
  mkdir -p "$user_bin"
  if [[ ":$PATH:" != *":${user_bin}:"* ]]; then
    echo "WARNING: ${user_bin} is not on PATH. Add 'export PATH=\"${user_bin}:\$PATH\"' to your shell profile." >&2
  fi
  echo "$user_bin"
}

install_tfsec_versioned() {
  local version="$1"
  local os arch install_dir
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)
  [[ "$arch" == "x86_64" ]]  && arch="amd64"
  [[ "$arch" == "aarch64" ]] && arch="arm64"
  install_dir=$(choose_install_dir)
  local base_url="https://github.com/aquasecurity/tfsec/releases/download/v${version}"
  local binary="tfsec-${os}-${arch}"
  local checksum_file="tfsec_checksums.txt"

  echo "Downloading tfsec v${version} from GitHub releases ..."
  curl -sSL "${base_url}/${binary}"          -o "/tmp/${binary}"
  curl -sSL "${base_url}/${checksum_file}"   -o /tmp/tfsec_checksums.txt

  # Verify SHA-256 integrity before installing — guards against compromised releases.
  # The checksum file contains lines like: "abc123...  tfsec-linux-amd64" — the
  # downloaded file must keep that exact name (not a generic "tfsec") for the
  # checksum tool to find it in the working directory.
  # Use shasum on macOS (no sha256sum by default) and sha256sum on Linux.
  if ! (cd /tmp && eval "$(checksum_check_cmd "tfsec_checksums.txt" "$binary")"); then
    echo "ERROR: tfsec checksum verification FAILED. Aborting installation." >&2
    rm -f "/tmp/${binary}" /tmp/tfsec_checksums.txt
    exit 1
  fi
  echo "tfsec v${version} checksum verified."

  chmod +x "/tmp/${binary}"
  if [[ -w "$install_dir" ]]; then
    mv "/tmp/${binary}" "${install_dir}/tfsec"
  else
    sudo mv "/tmp/${binary}" "${install_dir}/tfsec"
  fi
  rm -f /tmp/tfsec_checksums.txt
  echo "tfsec ${version} installed to ${install_dir}/tfsec"
}

if ! check_or_install "tfsec" "$REQUIRED_TFSEC_VERSION"; then
  install_tfsec_versioned "$REQUIRED_TFSEC_VERSION"
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
