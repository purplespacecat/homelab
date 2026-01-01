#!/bin/bash
#
# Bootstrap FluxCD to Kubernetes Cluster
# This script sets up FluxCD GitOps for automated infrastructure management
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "======================================"
echo "FluxCD Bootstrap"
echo "======================================"
echo ""

# Check if flux CLI is installed
if ! command -v flux &> /dev/null; then
    echo "❌ Flux CLI not found!"
    echo ""
    echo "Please install Flux CLI first:"
    echo "  ./scripts/flux/install-flux-cli.sh"
    echo ""
    exit 1
fi

FLUX_VERSION=$(flux --version 2>/dev/null || echo "unknown")
echo "Flux CLI version: $FLUX_VERSION"
echo ""

# Check kubectl access
echo "Checking Kubernetes cluster access..."
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster!"
    echo ""
    echo "Please ensure:"
    echo "1. Kubernetes cluster is running"
    echo "2. kubectl is configured (check: kubectl get nodes)"
    echo ""
    exit 1
fi

echo "✅ Cluster connection OK"
echo ""

# Check prerequisites
echo "Checking cluster prerequisites..."
if ! flux check --pre; then
    echo ""
    echo "❌ Prerequisites check failed!"
    echo "Please resolve the issues above before continuing."
    exit 1
fi

echo ""
echo "✅ Prerequisites OK"
echo ""

# Gather information
echo "======================================"
echo "Configuration"
echo "======================================"
echo ""

# GitHub owner
read -p "GitHub username/organization: " GITHUB_OWNER
if [ -z "$GITHUB_OWNER" ]; then
    echo "❌ GitHub owner is required"
    exit 1
fi

# Repository name
read -p "Repository name [homelab]: " GITHUB_REPO
GITHUB_REPO=${GITHUB_REPO:-homelab}

# Branch
read -p "Branch name [main]: " GITHUB_BRANCH
GITHUB_BRANCH=${GITHUB_BRANCH:-main}

# GitHub token
echo ""
echo "GitHub Personal Access Token is required with these permissions:"
echo "  - Contents: Read and write"
echo "  - Metadata: Read-only (automatically included)"
echo ""
echo "Create token at: https://github.com/settings/tokens/new"
echo ""
read -sp "GitHub Personal Access Token: " GITHUB_TOKEN
echo ""

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ GitHub token is required"
    exit 1
fi

echo ""
echo "======================================"
echo "Summary"
echo "======================================"
echo "GitHub: $GITHUB_OWNER/$GITHUB_REPO"
echo "Branch: $GITHUB_BRANCH"
echo "Path: ./clusters/homelab"
echo ""
read -p "Proceed with bootstrap? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Bootstrap cancelled."
    exit 0
fi

echo ""
echo "======================================"
echo "Bootstrapping Flux..."
echo "======================================"
echo ""

# Export token for flux
export GITHUB_TOKEN

# Bootstrap Flux
if flux bootstrap github \
    --owner="$GITHUB_OWNER" \
    --repository="$GITHUB_REPO" \
    --branch="$GITHUB_BRANCH" \
    --path=./clusters/homelab \
    --personal; then

    echo ""
    echo "======================================"
    echo "✅ Flux Bootstrap Successful!"
    echo "======================================"
    echo ""
    echo "Flux components installed in: flux-system namespace"
    echo "Git repository connected: $GITHUB_OWNER/$GITHUB_REPO"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Verify Flux installation:"
    echo "   flux check"
    echo ""
    echo "2. Watch Flux deploy infrastructure:"
    echo "   flux get kustomizations -w"
    echo ""
    echo "3. View Helm releases:"
    echo "   flux get helmreleases -A"
    echo ""
    echo "4. Check all resources:"
    echo "   flux get all"
    echo ""
    echo "Infrastructure will automatically deploy:"
    echo "  - NFS Provisioner"
    echo "  - MetalLB (LoadBalancer)"
    echo "  - NGINX Ingress Controller"
    echo "  - Cert-Manager (TLS)"
    echo "  - Prometheus Stack (Monitoring)"
    echo ""
    echo "Documentation:"
    echo "  - Managing with Flux: docs/managing-with-flux.md"
    echo "  - Cheat Sheet: docs/flux-cheatsheet.md"
    echo "  - Full Guide: docs/fluxcd-guide.md"
    echo ""
else
    echo ""
    echo "======================================"
    echo "❌ Flux Bootstrap Failed!"
    echo "======================================"
    echo ""
    echo "Common issues:"
    echo ""
    echo "1. GitHub token permissions:"
    echo "   - Needs 'Contents: Read and write'"
    echo "   - Create at: https://github.com/settings/tokens/new"
    echo ""
    echo "2. Repository access:"
    echo "   - Ensure repository exists: https://github.com/$GITHUB_OWNER/$GITHUB_REPO"
    echo "   - Token has access to this repository"
    echo ""
    echo "3. Branch protection:"
    echo "   - If you have branch protection, may need to disable temporarily"
    echo "   - Or give token bypass permissions"
    echo ""
    echo "4. Network issues:"
    echo "   - Check internet connectivity"
    echo "   - Check GitHub API access"
    echo ""
    echo "For manual bootstrap, see: docs/fluxcd-guide.md"
    echo ""
    exit 1
fi
