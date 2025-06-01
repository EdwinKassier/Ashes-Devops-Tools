#!/bin/bash

# Function to install tflint
install_tflint() {
    echo "Installing tflint..."
    if command -v brew &> /dev/null; then
        brew install tflint
    elif command -v apt &> /dev/null; then
        sudo apt-get install -y tflint
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y tflint
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm tflint
    else
        echo "Package manager not found. Please install tflint manually."
        exit 1
    fi
}

# Function to install tfsec
install_tfsec() {
    echo "Installing tfsec..."
    if command -v brew &> /dev/null; then
        brew install tfsec
    elif command -v apt &> /dev/null; then
        sudo apt-get install -y tfsec
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y tfsec
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm tfsec
    else
        echo "Package manager not found. Please install tfsec manually."
        exit 1
    fi
}

# Detect OS and install tools
case "$(uname -s)" in
    Darwin)
        echo "Detected macOS"
        install_tflint
        install_tfsec
        ;;
    Linux)
        echo "Detected Linux"
        install_tflint
        install_tfsec
        ;;
    MINGW*|CYGWIN*|MSYS*)
        echo "Detected Windows (via WSL)"
        # You can add a command to install using WSL or another method if needed.
        echo "Please run this script in WSL or use a Linux environment to install tflint and tfsec."
        ;;
    *)
        echo "Unsupported OS. Please install tflint and tfsec manually."
        exit 1
        ;;
esac

echo "Installation complete!"
