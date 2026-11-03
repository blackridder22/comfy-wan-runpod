#!/usr/bin/env bash
# Install ComfyUI, a venv on the network volume, and the custom nodes for
# Wan 2.2, Wan 2.2 Animate, and Real-ESRGAN video upscale.
# Idempotent: existing git checkouts are left alone unless UPDATE_REPOS=1.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${ROOT}/lib.sh"

require_writable_workspace

STAMP="${COMFY_DIR}/.comfy-wan-setup-stamp"
NODES="${COMFY_DIR}/custom_nodes"

install_os_packages() {
  if ! command -v apt-get >/dev/null 2>&1; then
    log "apt-get not found; expecting git, wget, and ffmpeg to already be installed"
    return 0
  fi
  if [[ "$(id -u)" -ne 0 ]]; then
    log "not root; skipping apt-get"
    return 0
  fi
  if command -v git >/dev/null 2>&1 \
    && command -v wget >/dev/null 2>&1 \
    && command -v ffmpeg >/dev/null 2>&1 \
    && command -v aria2c >/dev/null 2>&1 \
    && [[ "${FORCE_SETUP:-0}" != "1" ]]; then
    log "git, wget, ffmpeg, and aria2c already installed"
    return 0
  fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
    git \
    aria2 \
    ca-certificates \
    wget \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    build-essential \
    python3-venv \
    python3-dev
}

install_node() {
  local url="$1"
  local name="$2"
  local req="$3"
  local py="${COMFY_DIR}/venv/bin/python"
  clone_repo "${url}" "${NODES}/${name}"
  if [[ -n "${req}" && -f "${NODES}/${name}/${req}" ]]; then
    log "pip install -r ${name}/${req}"
    "${py}" -m pip install --upgrade-strategy only-if-needed -r "${NODES}/${name}/${req}"
  fi
}

ensure_seedvr_node() {
  if [[ "${INSTALL_SEEDVR2:-0}" != "1" ]]; then
    return 0
  fi
  install_node \
    "https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler.git" \
    "ComfyUI-SeedVR2_VideoUpscaler" \
    "requirements.txt"
}

install_os_packages

if [[ -f "${STAMP}" && "${FORCE_SETUP:-0}" != "1" && "${UPDATE_REPOS:-0}" != "1" \
  && -x "${COMFY_DIR}/venv/bin/python" \
  && -d "${NODES}/ComfyUI-WanVideoWrapper/.git" \
  && -d "${NODES}/ComfyUI-VideoHelperSuite/.git" \
  && -d "${NODES}/ComfyUI-KJNodes/.git" \
  && -d "${NODES}/ComfyUI-Frame-Interpolation/.git" \
  && -d "${NODES}/comfyui_controlnet_aux/.git" \
  && -d "${NODES}/ComfyUI-segment-anything-2/.git" \
  && -d "${NODES}/ComfyUI-WanAnimatePreprocess/.git" \
  && -d "${NODES}/ComfyUI-Manager/.git" ]]; then
  log "ComfyUI setup already complete (${STAMP})"
  ensure_seedvr_node
  exit 0
fi

clone_repo "https://github.com/Comfy-Org/ComfyUI.git" "${COMFY_DIR}"

if [[ ! -x "${COMFY_DIR}/venv/bin/python" ]]; then
  log "creating venv at ${COMFY_DIR}/venv (system site packages, so the image torch is reused)"
  python3 -m venv --system-site-packages "${COMFY_DIR}/venv"
fi

PY="${COMFY_DIR}/venv/bin/python"
"${PY}" -m pip install --upgrade pip setuptools wheel
log "installing ComfyUI requirements"
"${PY}" -m pip install --upgrade-strategy only-if-needed -r "${COMFY_DIR}/requirements.txt"

mkdir -p "${NODES}"

install_node "https://github.com/Comfy-Org/ComfyUI-Manager.git" "ComfyUI-Manager" "requirements.txt"
install_node "https://github.com/kijai/ComfyUI-WanVideoWrapper.git" "ComfyUI-WanVideoWrapper" "requirements.txt"
install_node "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git" "ComfyUI-VideoHelperSuite" "requirements.txt"
install_node "https://github.com/kijai/ComfyUI-KJNodes.git" "ComfyUI-KJNodes" "requirements.txt"
install_node "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git" "ComfyUI-Frame-Interpolation" "requirements-no-cupy.txt"
install_node "https://github.com/Fannovel16/comfyui_controlnet_aux.git" "comfyui_controlnet_aux" "requirements.txt"
install_node "https://github.com/kijai/ComfyUI-segment-anything-2.git" "ComfyUI-segment-anything-2" ""
install_node "https://github.com/kijai/ComfyUI-WanAnimatePreprocess.git" "ComfyUI-WanAnimatePreprocess" "requirements.txt"
ensure_seedvr_node

mkdir -p "${COMFY_DIR}/models/diffusion_models" \
  "${COMFY_DIR}/models/text_encoders" \
  "${COMFY_DIR}/models/vae" \
  "${COMFY_DIR}/models/clip_vision" \
  "${COMFY_DIR}/models/loras" \
  "${COMFY_DIR}/models/upscale_models" \
  "${COMFY_DIR}/models/detection" \
  "${COMFY_DIR}/models/sam2" \
  "${COMFY_DIR}/input" \
  "${COMFY_DIR}/output" \
  "${COMFY_DIR}/user/default/workflows"

date -u +%Y-%m-%dT%H:%M:%SZ > "${STAMP}"
log "setup complete"
