#!/usr/bin/env bash
# ==============================================================================
# build-multiarch.sh — Build multi-arch embedding-server image
#
# TEI publishes separate per-arch tags (no unified manifest), so each arch
# must be built individually, then merged into a single multi-arch manifest.
#
# The Dockerfile pins the model-downloader stage to $BUILDPLATFORM (the build
# host), so the ~2 GB model download always runs natively. Only the lightweight
# final COPY stage runs per target arch — no QEMU emulation on the heavy step.
#
# Prerequisites:
#   docker buildx create --use --name multiarch  (one-time setup)
#
# Usage:
#   ./build-multiarch.sh                    # build locally, keep in Docker daemon
#   ./build-multiarch.sh --push             # build + push to a registry
#   REGISTRY=ghcr.io/myuser ./build-multiarch.sh --push
# ==============================================================================

set -euo pipefail

# --- Configuration ---
REGISTRY="${REGISTRY:-}"                           # e.g., "ghcr.io/myuser"
IMAGE_NAME="${IMAGE_NAME:-embedding-server}"
TAG="${TAG:-latest}"
PUSH="${1:-}"

if [ -n "$REGISTRY" ]; then
  FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}"
else
  FULL_IMAGE="${IMAGE_NAME}"
fi

# Per-architecture TEI base tags
#   amd64: cpu-1.9 (versioned)
#   arm64: cpu-arm64-latest (rolling; the only ARM64 CPU tag)
AMD64_BASE="cpu-1.9"
ARM64_BASE="cpu-arm64-latest"

# Temporary arch-specific tags (merged into the final multi-arch manifest)
TAG_AMD64="${TAG}-amd64"
TAG_ARM64="${TAG}-arm64"

echo "==> Building multi-arch image: ${FULL_IMAGE}:${TAG}"
echo "    amd64 base: ${AMD64_BASE}"
echo "    arm64 base: ${ARM64_BASE}"
echo ""
echo "    Stage 1 (model download) runs on BUILDPLATFORM — native speed,"
echo "    no emulation overhead on the ~2 GB model pull."
echo ""

# --- Build amd64 ---
echo "==> [1/2] Building linux/amd64 ..."
docker buildx build \
  --platform linux/amd64 \
  --build-arg BASE_TAG="${AMD64_BASE}" \
  --tag "${FULL_IMAGE}:${TAG_AMD64}" \
  --load \
  .

# --- Build arm64 ---
echo ""
echo "==> [2/2] Building linux/arm64 ..."
docker buildx build \
  --platform linux/arm64 \
  --build-arg BASE_TAG="${ARM64_BASE}" \
  --tag "${FULL_IMAGE}:${TAG_ARM64}" \
  --load \
  .

# --- Merge into multi-arch manifest ---
echo ""
echo "==> Merging into multi-arch manifest: ${FULL_IMAGE}:${TAG} ..."
docker buildx imagetools create \
  --tag "${FULL_IMAGE}:${TAG}" \
  "${FULL_IMAGE}:${TAG_AMD64}" \
  "${FULL_IMAGE}:${TAG_ARM64}"

echo ""
echo "==> Done: ${FULL_IMAGE}:${TAG}"
echo ""
echo "Inspect:"
echo "  docker buildx imagetools inspect ${FULL_IMAGE}:${TAG}"

if [ "$PUSH" = "--push" ]; then
  echo ""
  echo "==> Pushing ${FULL_IMAGE}:${TAG} ..."
  docker push "${FULL_IMAGE}:${TAG}"
  docker push "${FULL_IMAGE}:${TAG_AMD64}"
  docker push "${FULL_IMAGE}:${TAG_ARM64}"
  echo "==> Push complete."
else
  echo ""
  echo "Tip: add --push to push to a registry."
fi
