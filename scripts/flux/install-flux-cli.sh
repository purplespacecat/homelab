#!/bin/bash
#
# Install Flux CLI
# Downloads and installs the latest version of Flux CLI to user's local bin directory
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "FluxCD CLI Installation"
echo "======================================"
echo ""

# Check if flux is already installed
if command -v flux &> /dev/null; then
    CURRENT_VERSION=$(flux --version | head -1)
    echo "Flux CLI is already installed: $CURRENT_VERSION"
    read -p "Do you want to reinstall/upgrade? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
fi

# Determine installation directory
if [ -w "/usr/local/bin" ]; then
    INSTALL_DIR="/usr/local/bin"
    echo "Installing to: $INSTALL_DIR (system-wide)"
else
    INSTALL_DIR="$HOME/.local/bin"
    echo "Installing to: $INSTALL_DIR (user-only, no sudo required)"
    mkdir -p "$INSTALL_DIR"
fi

# Download and install
echo ""
echo "Downloading Flux CLI..."
echo ""

curl -s https://fluxcd.io/install.sh | bash -s -- "$INSTALL_DIR"

# Verify installation
echo ""
echo "Verifying installation..."

if [ "$INSTALL_DIR" = "$HOME/.local/bin" ]; then
    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo ""
        echo "Adding $HOME/.local/bin to PATH..."
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
        export PATH="$HOME/.local/bin:$PATH"
        echo "Added to ~/.bashrc (reload your shell or run: source ~/.bashrc)"
    fi
    FLUX_BIN="$HOME/.local/bin/flux"
else
    FLUX_BIN="flux"
fi

if [ -x "$INSTALL_DIR/flux" ] || command -v flux &> /dev/null; then
    VERSION=$($FLUX_BIN --version 2>/dev/null || echo "unknown")
    echo ""
    echo "✅ Flux CLI installed successfully!"
    echo "Version: $VERSION"
    echo ""
    echo "Verify installation:"
    echo "  $FLUX_BIN --version"
    echo ""
    echo "Check cluster prerequisites (requires kubectl access):"
    echo "  $FLUX_BIN check --pre"
    echo ""
else
    echo ""
    echo "❌ Installation may have failed. Please check the output above."
    exit 1
fi

echo "Next steps:"
echo "1. Ensure kubectl is configured and connected to your cluster"
echo "2. Run: $FLUX_BIN check --pre"
echo "3. Bootstrap Flux: ./scripts/flux/bootstrap-flux.sh"
echo ""
