#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2025-2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Cloud Agent install script for the Video Search and Summarization repo.
#
# Prepares a development environment that mirrors the CI pipeline
# (.github/workflows/ci.yml) for the two developer-facing services that
# build and test without a GPU:
#   - services/agent  (Python 3.13, managed by uv)
#   - services/ui     (Node 22 monorepo, managed by npm)
#
# GPU-dependent deployment (NIM microservices, VST, RTVI, analytics, the
# full docker compose stack) is intentionally out of scope: it requires
# NVIDIA GPUs, an NGC/NVIDIA API key, and Docker, none of which exist in
# the Cloud Agent VM. Those stacks are driven separately via the deploy/
# compose files on GPU hosts.
#
# The script is idempotent: it is safe to run repeatedly and against a
# partially prepared or snapshot-cached checkout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Installing system dependencies (cairo/pkg-config for agent PDF generation)"
sudo apt-get update
sudo apt-get install -y --no-install-recommends libcairo2-dev pkg-config python3-dev

echo "==> Ensuring uv is installed and on PATH"
# astral.sh (the canonical uv installer host) is not reachable under the
# restricted egress policy, so install uv from PyPI instead. Symlink it into
# /usr/local/bin so `uv`/`uvx` are available to every future agent shell
# without mutating shell profiles.
export PATH="$HOME/.local/bin:$PATH"
if ! command -v uv >/dev/null 2>&1; then
  # --break-system-packages: the base image's system Python is PEP 668
  # externally-managed; --user keeps the install in ~/.local.
  python3 -m pip install --user --break-system-packages --upgrade uv
fi
sudo ln -sf "$HOME/.local/bin/uv" /usr/local/bin/uv
sudo ln -sf "$HOME/.local/bin/uvx" /usr/local/bin/uvx
uv --version

echo "==> services/agent: Python 3.13 venv + dev dependencies (uv sync --frozen)"
pushd services/agent >/dev/null
# pyproject allows >=3.13,<3.15; CI pins 3.13, so pin it here too for parity.
# `uv sync --python 3.13` creates (or reuses) the .venv on 3.13 and is
# idempotent, so no separate `uv venv` step is needed.
uv python install 3.13
uv sync --python 3.13 --group dev --frozen
popd >/dev/null

echo "==> services/ui: Node 22 monorepo dependencies (npm ci)"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
# .nvmrc pins v22.22.3; the base image ships v22.22.2 (patch-equivalent).
# Select the installed Node 22 rather than failing on an exact-version fetch
# (nodejs.org is not reachable under the restricted egress policy).
nvm use 22 >/dev/null 2>&1 || true
node --version
pushd services/ui >/dev/null
npm ci
popd >/dev/null

echo "==> Install complete."
echo "    Agent checks : cd services/agent && uv run ruff check . && uv run mypy src/vss_agents/ && uv run pytest -m 'not slow and not integration'"
echo "    UI build     : cd services/ui && npm run build"
echo "    UI dev server: cd services/ui && npm run dev"
