#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo_error "Please run as root or with sudo"
    exit 1
fi

echo_info "Starting worker node join process..."

# ========================================
# Configuration
# ========================================
CONTROL_PLANE_HOST="${CONTROL_PLANE_HOST:-}"
CONTROL_PLANE_PORT="${CONTROL_PLANE_PORT:-6443}"
TOKEN="${TOKEN:-}"
CA_CERT_HASH="${CA_CERT_HASH:-}"

# ========================================
# Validate Prerequisites
# ========================================
echo_info "Validating prerequisites..."

# Check if kubelet is installed
if ! command -v kubelet &> /dev/null; then
    echo_error "kubelet is not installed. Please run prepare-worker-node.sh first"
    exit 1
fi

# Check if kubeadm is installed
if ! command -v kubeadm &> /dev/null; then
    echo_error "kubeadm is not installed. Please run prepare-worker-node.sh first"
    exit 1
fi

# Check if containerd is running
if ! systemctl is-active --quiet containerd; then
    echo_error "containerd is not running. Please check your installation"
    exit 1
fi

# ========================================
# Get Join Information
# ========================================

# If all parameters are provided via environment variables
if [ -n "$CONTROL_PLANE_HOST" ] && [ -n "$TOKEN" ] && [ -n "$CA_CERT_HASH" ]; then
    echo_info "Using environment variables for join configuration"
else
    # Interactive mode - prompt for join command or parameters
    echo_info "Please provide the join information from your control plane"
    echo_info ""
    echo_info "Option 1: Paste the complete 'kubeadm join' command from the control plane"
    echo_info "Option 2: Provide individual parameters (control plane host, token, hash)"
    echo_info ""
    read -p "Enter the full kubeadm join command (or press Enter to provide parameters separately): " JOIN_COMMAND

    if [ -n "$JOIN_COMMAND" ]; then
        # Extract from full command
        echo_info "Parsing join command..."

        # Execute the provided join command
        echo_info "Joining cluster..."
        eval "$JOIN_COMMAND"

        echo_info ""
        echo_info "Worker node successfully joined the cluster! ✓"
        echo_info ""
        echo_info "Verify the node status from the control plane:"
        echo_info "  kubectl get nodes"
        exit 0
    else
        # Prompt for individual parameters
        read -p "Control plane host (IP or hostname): " CONTROL_PLANE_HOST
        read -p "Control plane port [6443]: " CONTROL_PLANE_PORT_INPUT
        CONTROL_PLANE_PORT="${CONTROL_PLANE_PORT_INPUT:-6443}"
        read -p "Token: " TOKEN
        read -p "CA cert hash (sha256:xxxxx): " CA_CERT_HASH
    fi
fi

# ========================================
# Validate Parameters
# ========================================
if [ -z "$CONTROL_PLANE_HOST" ]; then
    echo_error "Control plane host is required"
    exit 1
fi

if [ -z "$TOKEN" ]; then
    echo_error "Token is required"
    exit 1
fi

if [ -z "$CA_CERT_HASH" ]; then
    echo_error "CA cert hash is required"
    exit 1
fi

# Ensure CA cert hash has sha256: prefix
if [[ ! "$CA_CERT_HASH" =~ ^sha256: ]]; then
    CA_CERT_HASH="sha256:$CA_CERT_HASH"
fi

# ========================================
# Join the Cluster
# ========================================
echo_info "Joining cluster at ${CONTROL_PLANE_HOST}:${CONTROL_PLANE_PORT}..."
echo_info "This may take a minute..."

kubeadm join "${CONTROL_PLANE_HOST}:${CONTROL_PLANE_PORT}" \
    --token "${TOKEN}" \
    --discovery-token-ca-cert-hash "${CA_CERT_HASH}" \
    --v=5

# ========================================
# Verify Join
# ========================================
echo_info ""
echo_info "Worker node successfully joined the cluster! ✓"
echo_info ""
echo_info "The kubelet service should now be running on this node."
echo_info "Verify the service status:"
echo_info "  systemctl status kubelet"
echo_info ""
echo_info "From the control plane, verify the node status:"
echo_info "  kubectl get nodes"
echo_info ""
echo_info "It may take a minute for the node to appear as 'Ready'"
echo_info ""
