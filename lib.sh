#!/usr/bin/env bash
# Shared helpers for setup.sh, models.sh, and start.sh.
# Callers set `set -euo pipefail` before sourcing this file.

: "${COMFY_DIR:=/workspace/ComfyUI}"
: "${PRECISION:=fp8}"

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_writable_workspace() {
  if [[ "${COMFY_DIR}" == /workspace/* && ! -w /workspace ]]; then
    die "/workspace is not writable. Attach the Runpod network volume at /workspace."
  fi
}

clone_repo() {
  local url="$1"
  local dest="$2"
  if [[ -d "${dest}" && ! -d "${dest}/.git" ]]; then
    die "${dest} exists but is not a git checkout"
  fi
  if [[ -d "${dest}/.git" ]]; then
    if [[ "${UPDATE_REPOS:-0}" == "1" ]]; then
      log "updating ${dest}"
      git -C "${dest}" pull --ff-only --depth 1
    else
      log "already present: ${dest}"
    fi
    return 0
  fi
  mkdir -p "$(dirname "${dest}")"
  log "cloning ${url}"
  git clone --depth 1 "${url}" "${dest}"
}

# Download url to dest. Skip when the file is already expected_bytes.
# Resume a short file with aria2c, then wget -c. HF_TOKEN is optional and is
# passed via a mode-600 config file, not on the command line.
download_file() {
  local url="$1"
  local dest="$2"
  local expected="$3"
  local dir name size secret_conf wgetrc aria_ok
  dir="$(dirname "${dest}")"
  name="$(basename "${dest}")"
  mkdir -p "${dir}"

  if [[ -f "${dest}" ]]; then
    size="$(stat -c%s "${dest}")"
    if [[ "${size}" -eq "${expected}" ]]; then
      log "skip existing ${dest} (${size} bytes)"
      rm -f "${dest}.aria2"
      return 0
    fi
    if [[ "${size}" -gt "${expected}" ]]; then
      log "replacing oversized ${dest} (${size} > ${expected})"
      rm -f "${dest}" "${dest}.aria2"
    else
      log "resuming ${dest} (${size}/${expected} bytes)"
    fi
  else
    log "downloading ${name}"
  fi

  secret_conf=""
  wgetrc=""
  if [[ -n "${HF_TOKEN:-}" ]]; then
    secret_conf="$(mktemp)"
    chmod 600 "${secret_conf}"
    printf 'header=Authorization: Bearer %s\n' "${HF_TOKEN}" > "${secret_conf}"
    wgetrc="$(mktemp)"
    chmod 600 "${wgetrc}"
    printf 'header = Authorization: Bearer %s\n' "${HF_TOKEN}" > "${wgetrc}"
  fi

  aria_ok=0
  if command -v aria2c >/dev/null 2>&1; then
    if run_aria2c "${url}" "${dir}" "${name}" "${secret_conf}" 4 \
      || run_aria2c "${url}" "${dir}" "${name}" "${secret_conf}" 1; then
      aria_ok=1
    else
      log "aria2c failed for ${name}; trying wget -c"
    fi
  fi

  if [[ "${aria_ok}" -ne 1 ]]; then
    if [[ -n "${wgetrc}" ]]; then
      WGETRC="${wgetrc}" wget -c --tries=5 --timeout=60 \
        --user-agent="comfy-wan-runpod" \
        -O "${dest}" "${url}"
    else
      wget -c --tries=5 --timeout=60 \
        --user-agent="comfy-wan-runpod" \
        -O "${dest}" "${url}"
    fi
  fi

  if [[ -n "${secret_conf}" ]]; then
    rm -f "${secret_conf}"
  fi
  if [[ -n "${wgetrc}" ]]; then
    rm -f "${wgetrc}"
  fi

  if [[ ! -f "${dest}" ]]; then
    die "download did not create ${dest}"
  fi
  size="$(stat -c%s "${dest}")"
  if [[ "${size}" -ne "${expected}" ]]; then
    die "size mismatch for ${dest}: got ${size}, expected ${expected}"
  fi
  rm -f "${dest}.aria2"
}

run_aria2c() {
  local url="$1"
  local dir="$2"
  local name="$3"
  local secret_conf="$4"
  local conns="$5"
  local -a conf_args
  conf_args=()
  if [[ -n "${secret_conf}" ]]; then
    conf_args=(--conf-path="${secret_conf}")
  fi
  aria2c \
    --continue=true \
    --max-connection-per-server="${conns}" \
    --split="${conns}" \
    --min-split-size=1M \
    --max-tries=5 \
    --retry-wait=5 \
    --timeout=60 \
    --file-allocation=none \
    --auto-file-renaming=false \
    --allow-overwrite=false \
    --console-log-level=notice \
    --summary-interval=20 \
    --user-agent="comfy-wan-runpod" \
    --dir="${dir}" \
    --out="${name}" \
    "${conf_args[@]}" \
    "${url}"
}
