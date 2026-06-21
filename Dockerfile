# syntax=docker/dockerfile:1

# =============================================================================
# Multi-stage Dockerfile for TEI (Text Embeddings Inference) CPU
# with pre-downloaded BAAI/bge-large-en-v1.5 embedding model.
#
# Build (single arch — auto-detects host platform):
#   docker build -t embedding-server .
#
# Build (ARM64 on x86 host, e.g. Raspberry Pi cross-compile):
#   docker build --build-arg BASE_TAG=cpu-arm64-latest -t embedding-server .
#
# Multi-arch: use build-multiarch.sh — TEI publishes separate tags per arch
# (no unified manifest), so buildx --platform alone won't work.
#
# Architecture notes:
#   - x86_64 / Intel:  cpu-1.9 (default)
#   - ARM64 / RPi:     cpu-arm64-latest
# =============================================================================

# Global ARGs.
# BASE_TAG: which TEI base image to use (switches arch).
# BUILDPLATFORM: auto-set by buildx; ensures Stage 1 runs natively on build host.
ARG BASE_TAG=cpu-1.9
ARG BUILDPLATFORM

# ---------------------------------------------------------------------------
# Stage 1 — Model downloader
# Pinned to BUILDPLATFORM so it always runs natively on the build host.
# No QEMU emulation — saves minutes on cross-arch builds.
# Model weights are architecture-agnostic (safetensors, tokenizer JSON, etc.).
# ---------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM python:3.11-slim AS model-downloader

RUN pip install --no-cache-dir huggingface_hub

RUN hf download BAAI/bge-large-en-v1.5 \
    --local-dir /models/bge-large-en-v1.5

# ---------------------------------------------------------------------------
# Stage 2 — Runtime image (defaults to TARGETPLATFORM — the deployment arch).
# BASE_TAG selects the correct TEI image for that arch.
# ---------------------------------------------------------------------------
FROM ghcr.io/huggingface/text-embeddings-inference:${BASE_TAG}

# Copy the pre-downloaded model into /data (TEI's standard model directory).
COPY --from=model-downloader /models /data

# --- Runtime defaults ---
ENV MODEL_ID=/data/bge-large-en-v1.5
ENV PORT=80

EXPOSE 80

# TEI router entrypoint — loads the model directly from the local path.
ENTRYPOINT ["text-embeddings-router"]
CMD ["--model-id", "/data/bge-large-en-v1.5", "--port", "80"]
