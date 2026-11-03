#!/usr/bin/env bash
# Download Wan 2.2, Animate, Lightx2v, pose, and Real-ESRGAN weights onto the
# network volume. Existing files whose byte size matches the verified size are
# skipped. Short files are resumed with aria2c or wget -c.
#
# Sizes and URLs were checked with HTTP HEAD on 2026-11-03 (all returned 200
# and Content-Length matched the Hugging Face tree API / GitHub release size).
#
# PRECISION=fp8   (default) fp8 scaled diffusion + fp8 text encoder
# PRECISION=fp16  fp16 diffusion, bf16 Wan Animate (no fp16 animate exists), fp16 text encoder
# PRECISION=both  download both sets
#
# INSTALL_SEEDVR2=1 or DOWNLOAD_SEEDVR2=1 also fetches the native SeedVR2 3B
# int8 weights used by workflows/wan22_upscale_seedvr2.json.
#
# HF_TOKEN is optional. Public files do not need it. Never commit a token.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${ROOT}/lib.sh"

require_writable_workspace

case "${PRECISION}" in
  fp8|fp16|both) ;;
  *) die "PRECISION must be fp8, fp16, or both (got ${PRECISION})" ;;
esac

if [[ ! -d "${COMFY_DIR}" ]]; then
  die "ComfyUI directory ${COMFY_DIR} is missing. Run setup.sh first."
fi

export HF_HOME="${HF_HOME:-/workspace/hf-home}"
export HUGGINGFACE_HUB_CACHE="${HUGGINGFACE_HUB_CACHE:-${HF_HOME}/hub}"
mkdir -p "${HF_HOME}" "${HUGGINGFACE_HUB_CACHE}"

# group|relative-dir-under-COMFY_DIR|filename|url|bytes
manifest() {
  cat << 'EOF'
common|models/vae|wan_2.1_vae.safetensors|https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors|253815318
common|models/clip_vision|clip_vision_h.safetensors|https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors|1264219396
common|models/loras|wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors|https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors|1226977424
common|models/loras|wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors|https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors|1226977424
common|models/loras|wan2.2_t2v_lightx2v_4steps_lora_v1.1_high_noise.safetensors|https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_t2v_lightx2v_4steps_lora_v1.1_high_noise.safetensors|1226977424
common|models/loras|wan2.2_t2v_lightx2v_4steps_lora_v1.1_low_noise.safetensors|https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_t2v_lightx2v_4steps_lora_v1.1_low_noise.safetensors|1226977424
common|models/loras|lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors|https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Lightx2v/lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors|738005744
common|models/loras|WanAnimate_relight_lora_fp16.safetensors|https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/Wan22_relight/WanAnimate_relight_lora_fp16.safetensors|1436672440
common|models/sam2|sam2_hiera_base_plus.safetensors|https://huggingface.co/Kijai/sam2-safetensors/resolve/main/sam2_hiera_base_plus.safetensors|323407992
common|models/detection|yolov10m.onnx|https://huggingface.co/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx|61659339
common|models/detection|vitpose-l-wholebody.onnx|https://huggingface.co/JunkyByte/easy_ViTPose/resolve/main/onnx/wholebody/vitpose-l-wholebody.onnx|1234579166
common|custom_nodes/comfyui_controlnet_aux/ckpts/yzd-v/DWPose|yolox_l.onnx|https://huggingface.co/yzd-v/DWPose/resolve/main/yolox_l.onnx|216746733
common|custom_nodes/comfyui_controlnet_aux/ckpts/hr16/DWPose-TorchScript-BatchSize5|dw-ll_ucoco_384_bs5.torchscript.pt|https://huggingface.co/hr16/DWPose-TorchScript-BatchSize5/resolve/main/dw-ll_ucoco_384_bs5.torchscript.pt|135059124
common|models/upscale_models|RealESRGAN_x4plus.pth|https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth|67040989
common|models/upscale_models|RealESRGAN_x2plus.pth|https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth|67061725
fp8|models/diffusion_models|wan2.2_t2v_high_noise_14B_fp8_scaled.safetensors|https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_t2v_high_noise_14B_fp8_scaled.safetensors|14293923632
fp8|models/diffusion_models|wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors|https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors|14293923632
fp8|models/diffusion_models|wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors|https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors|14294742832
fp8|models/diffusion_models|wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors|https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors|14294742832
fp8|models/diffusion_models|Wan2_2-Animate-14B_fp8_e4m3fn_scaled_KJ.safetensors|https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/Wan22Animate/Wan2_2-Animate-14B_fp8_e4m3fn_scaled_KJ.safetensors|18401760586
fp8|models/text_encoders|umt5_xxl_fp8_e4m3fn_scaled.safetensors|https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors|6735906897
fp16|models/diffusion_models|wan2.2_t2v_high_noise_14B_fp16.safetensors|https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_t2v_high_noise_14B_fp16.safetensors|28577095592
fp16|models/diffusion_models|wan2.2_t2v_low_noise_14B_fp16.safetensors|https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_t2v_low_noise_14B_fp16.safetensors|28577095592
fp16|models/diffusion_models|wan2.2_i2v_high_noise_14B_fp16.safetensors|https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp16.safetensors|28577914792
fp16|models/diffusion_models|wan2.2_i2v_low_noise_14B_fp16.safetensors|https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp16.safetensors|28577914792
fp16|models/diffusion_models|wan2.2_animate_14B_bf16.safetensors|https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_animate_14B_bf16.safetensors|34549787368
fp16|models/text_encoders|umt5_xxl_fp16.safetensors|https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp16.safetensors|11366399385
seedvr|models/diffusion_models|seedvr2_3b_int8_convrot.safetensors|https://huggingface.co/Comfy-Org/SeedVR2/resolve/main/diffusion_models/seedvr2_3b_int8_convrot.safetensors|3458259704
seedvr|models/vae|seedvr2_ema_vae_fp16.safetensors|https://huggingface.co/Comfy-Org/SeedVR2/resolve/main/vae/seedvr2_ema_vae_fp16.safetensors|501324814
EOF
}

want_group() {
  local group="$1"
  case "${group}" in
    common) return 0 ;;
    fp8)
      [[ "${PRECISION}" == "fp8" || "${PRECISION}" == "both" ]]
      ;;
    fp16)
      [[ "${PRECISION}" == "fp16" || "${PRECISION}" == "both" ]]
      ;;
    seedvr)
      [[ "${INSTALL_SEEDVR2:-0}" == "1" || "${DOWNLOAD_SEEDVR2:-0}" == "1" ]]
      ;;
    *)
      die "unknown manifest group ${group}"
      ;;
  esac
}

if [[ ! -d "${COMFY_DIR}/custom_nodes/comfyui_controlnet_aux" ]]; then
  die "comfyui_controlnet_aux is not installed. Run setup.sh before models.sh."
fi

log "PRECISION=${PRECISION} INSTALL_SEEDVR2=${INSTALL_SEEDVR2:-0} DOWNLOAD_SEEDVR2=${DOWNLOAD_SEEDVR2:-0}"

while IFS='|' read -r group subdir filename url bytes; do
  [[ -z "${group}" ]] && continue
  if ! want_group "${group}"; then
    continue
  fi
  download_file "${url}" "${COMFY_DIR}/${subdir}/${filename}" "${bytes}"
done < <(manifest)

log "model download step finished"
