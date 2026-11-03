#!/usr/bin/env bash
# First boot: install ComfyUI and download models. Later boots skip work that
# is already on the network volume, then launch ComfyUI on 0.0.0.0:8188.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${ROOT}/lib.sh"

require_writable_workspace

export HF_HOME="${HF_HOME:-/workspace/hf-home}"
export HUGGINGFACE_HUB_CACHE="${HUGGINGFACE_HUB_CACHE:-${HF_HOME}/hub}"
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-/workspace/.cache/pip}"
export PORT="${PORT:-8188}"
mkdir -p "${HF_HOME}" "${HUGGINGFACE_HUB_CACHE}" "${PIP_CACHE_DIR}"

bash "${ROOT}/setup.sh"
bash "${ROOT}/models.sh"

install_workflows() {
  local wf_dst="${COMFY_DIR}/user/default/workflows"
  mkdir -p "${wf_dst}" "${COMFY_DIR}/input" "${COMFY_DIR}/output"
  REFRESH_WORKFLOWS="${REFRESH_WORKFLOWS:-0}" \
    PRECISION="${PRECISION}" \
    WF_SRC="${ROOT}/workflows" \
    WF_DST="${wf_dst}" \
    python3 - << 'PY'
import json
import os
from pathlib import Path

precision = os.environ.get("PRECISION", "fp8")
refresh = os.environ.get("REFRESH_WORKFLOWS", "0") == "1"
src_dir = Path(os.environ["WF_SRC"])
dst_dir = Path(os.environ["WF_DST"])
replacements = [
    ("wan2.2_t2v_high_noise_14B_fp8_scaled.safetensors", "wan2.2_t2v_high_noise_14B_fp16.safetensors"),
    ("wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors", "wan2.2_t2v_low_noise_14B_fp16.safetensors"),
    ("wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors", "wan2.2_i2v_high_noise_14B_fp16.safetensors"),
    ("wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors", "wan2.2_i2v_low_noise_14B_fp16.safetensors"),
    ("Wan2_2-Animate-14B_fp8_e4m3fn_scaled_KJ.safetensors", "wan2.2_animate_14B_bf16.safetensors"),
    ("umt5_xxl_fp8_e4m3fn_scaled.safetensors", "umt5_xxl_fp16.safetensors"),
]

mapping = dict(replacements)

def retarget(value):
    if isinstance(value, dict):
        return {key: retarget(item) for key, item in value.items()}
    if isinstance(value, list):
        return [retarget(item) for item in value]
    if isinstance(value, str):
        return mapping.get(value, value)
    return value

for src in sorted(src_dir.glob("*.json")):
    obj = json.loads(src.read_text())
    if precision == "fp16":
        obj = retarget(obj)
    extra = obj.setdefault("extra", {})
    extra["comfy_wan_precision"] = precision
    dest = dst_dir / src.name
    if dest.exists() and not refresh:
        try:
            current = json.loads(dest.read_text())
        except json.JSONDecodeError:
            current = {}
        stamped = (current.get("extra") or {}).get("comfy_wan_precision")
        if stamped == precision:
            print(f"keep existing workflow {dest}")
            continue
    dest.write_text(json.dumps(obj, indent=2) + "\n")
    print(f"installed workflow {dest}")
PY
}

install_workflows

if [[ ! -x "${COMFY_DIR}/venv/bin/python" ]]; then
  die "venv python missing at ${COMFY_DIR}/venv/bin/python"
fi

# shellcheck disable=SC1091
source "${COMFY_DIR}/venv/bin/activate"

cd "${COMFY_DIR}"
extra=()
if [[ -n "${COMFY_EXTRA_ARGS:-}" ]]; then
  # Intentional split so a pod can append flags, for example: COMFY_EXTRA_ARGS="--cache-none"
  # shellcheck disable=SC2206
  extra=(${COMFY_EXTRA_ARGS})
fi

log "starting ComfyUI on 0.0.0.0:${PORT}"
exec python main.py \
  --listen 0.0.0.0 \
  --port "${PORT}" \
  --disable-auto-launch \
  --preview-method auto \
  --enable-cors-header '*' \
  "${extra[@]}"
