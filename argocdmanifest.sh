#!/usr/bin/env bash

set -euo pipefail

# Argo CD install manifest
BASE_URL="https://raw.githubusercontent.com/argoproj/argo-cd"

# Directory where manifests will be stored
OUTPUT_DIR="./argocd"

# Optional version argument
VERSION="${1:-}"

if [[ -n "$VERSION" ]]; then
    # A version was provided, e.g. ./get-argocd.sh v3.1.8
    TAG="$VERSION"
else
    # No version provided, use the stable branch
    TAG="stable"
fi

MANIFEST_URL="${BASE_URL}/${TAG}/manifests/install.yaml"

echo "Downloading Argo CD manifest from:"
echo "  $MANIFEST_URL"

# Temporary file so we can inspect the manifest before deciding
# what version directory to put it in.
TMP_FILE=$(mktemp)

trap 'rm -f "$TMP_FILE"' EXIT

curl -fsSL "$MANIFEST_URL" -o "$TMP_FILE"

if [[ -z "$VERSION" ]]; then
    # Extract the image tag from the argocd-server Deployment.
    VERSION=$(
        awk '
            /kind: Deployment/ { in_deployment=0 }
            /name: argocd-server/ { in_deployment=1 }
            in_deployment && /image: quay.io\/argoproj\/argocd:/ {
                sub(/^.*argocd:/, "")
                print
                exit
            }
        ' "$TMP_FILE"
    )

    if [[ -z "$VERSION" ]]; then
        echo "ERROR: Could not determine Argo CD version from manifest" >&2
        exit 1
    fi
fi

OUTPUT_PATH="${OUTPUT_DIR}/${VERSION}"

mkdir -p "$OUTPUT_PATH"

mv "$TMP_FILE" "${OUTPUT_PATH}/install.yaml"

cat > "${OUTPUT_PATH}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
metadata:
  name: kustomize

resources:
  - ./install.yaml
EOF

echo "Argo CD ${VERSION} manifest saved to:"
echo "  ${OUTPUT_PATH}/install.yaml"
echo "  ${OUTPUT_PATH}/kustomization.yaml"