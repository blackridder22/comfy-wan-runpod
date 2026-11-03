# ComfyUI on a Runpod GPU pod for Wan 2.2

One-command setup for Wan 2.2 14B text-to-video and image-to-video, Wan 2.2 Animate (image plus a driving video), Lightx2v 4-step LoRAs, and a Real-ESRGAN video upscale. An optional second upscaler, SeedVR2, stays off unless you ask for it.

ComfyUI and the weights live on the Runpod network volume at `/workspace`, so the next time you start a pod with that volume the scripts skip files that are already there and resume a partial download.

Target GPUs are an RTX A6000 48GB or an L40S 48GB (Ampere or Ada, CUDA 12). The default weights are the fp8 scaled 14B files. A 48GB card holds one fp8 expert plus the fp8 text encoder with room left for the video latents. fp16 weights are selected with `PRECISION=fp16` (Wan Animate's full-precision file from Comfy-Org is bf16, not fp16).

You do not need a custom Docker image. Use a stock Runpod PyTorch image. A Dockerfile is in the repo only as an optional extra.

## 1. Create a network volume

In the Runpod console, create a network volume in the same region you will deploy.

| What you download | Size |
| --- | --- |
| Default fp8 set (14B T2V, 14B I2V, Animate, text encoder, VAE, CLIP vision, Lightx2v and relight LoRAs, DWPose, SAM2, ViTPose, YOLO, Real-ESRGAN x4 and x2) | 93.02 GB (86.63 GiB) |
| fp16 diffusion models, bf16 Animate, and the fp16 text encoder instead of the fp8 set | 170.93 GB (159.19 GiB) |
| Optional SeedVR2 3B int8 plus its VAE | another 3.96 GB (3.69 GiB) |

ComfyUI, the virtualenv, and custom nodes add roughly 8–15 GB on top of that, and generations write into `output/`. Use a **150 GB** volume for the default fp8 install, or **250 GB** if you set `PRECISION=fp16`. The volume is billed for storage even while the pod is stopped. The GPU is not.

## 2. Deploy a pod on that volume

1. Deploy a GPU pod on an RTX A6000 or L40S.
2. Choose a Runpod PyTorch template with CUDA 12.x. This tag exists on Docker Hub: `runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04`. CUDA 12.4 images in the same family work too. Do not pick a CUDA 11 image.
3. Attach the network volume. It must mount at `/workspace`.
4. Expose **HTTP port 8188**.
5. Set the container start command to:

```bash
bash -c "cd /workspace && (test -d comfy-wan-runpod || git clone https://github.com/blackridder22/comfy-wan-runpod) && cd comfy-wan-runpod && git pull && bash start.sh"
```

`start.sh` installs ComfyUI on the first boot, downloads the weights, and launches the UI. The next boot sees the files and skips them.

Optional environment variables, set on the pod before you deploy:

| Variable | Default | Effect |
| --- | --- | --- |
| `PRECISION` | `fp8` | `fp16` downloads fp16 (Animate: bf16) weights and points the installed workflows at them. `both` downloads both sets and leaves the workflows on the fp8 names. |
| `INSTALL_SEEDVR2` | `0` | `1` clones [numz/ComfyUI-SeedVR2_VideoUpscaler](https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler) and downloads the native SeedVR2 3B int8 weights. |
| `DOWNLOAD_SEEDVR2` | `0` | `1` downloads those SeedVR2 weights without cloning the numz node. The shipped SeedVR2 workflow uses native ComfyUI nodes. |
| `HF_TOKEN` | empty | Only needed if Hugging Face rate-limits you. A read token is enough. Do not put a token in this repo. |
| `UPDATE_REPOS` | `0` | `1` runs `git pull` on ComfyUI and the custom nodes. |
| `FORCE_SETUP` | `0` | `1` reinstalls Python dependencies. |
| `REFRESH_WORKFLOWS` | `0` | `1` overwrites workflows already copied into ComfyUI. |
| `COMFY_EXTRA_ARGS` | empty | Extra arguments appended to `python main.py`. |

## 3. Open ComfyUI

The first boot downloads about 93 GB. When the log says ComfyUI is listening, open the Runpod **HTTP service** link for port 8188. That is the proxy URL:

`https://<pod-id>-8188.proxy.runpod.net`

Replace `<pod-id>` with the pod id from the console. The Connect menu also shows this link once port 8188 is ready.

### SSH tunnel to localhost:8188

From the pod's Connect menu, copy the SSH command (`ssh root@<ip> -p <port> -i <key>`). Forward port 8188 and leave that session open:

```bash
ssh -L 8188:127.0.0.1:8188 -p <port> root@<ip> -i <key>
```

Then open `http://127.0.0.1:8188` on your machine.

## 4. Load a workflow

In ComfyUI, open a workflow from `user/default/workflows/`. The same files are in this repo under `workflows/`.

| File | What it does |
| --- | --- |
| `wan22_14b_t2v.json` | Wan 2.2 14B text-to-video. |
| `wan22_14b_i2v.json` | Wan 2.2 14B image-to-video. Put a start image on the Load Image node. |
| `wan22_14b_animate.json` | Wan 2.2 Animate. Reference image plus a driving video. **Mix** replaces the person in the video. **Move** applies the driving motion to the reference character. |
| `wan22_upscale_realesrgan.json` | Real-ESRGAN x4 pass over a video (switch the loader to `RealESRGAN_x2plus.pth` for x2). |
| `wan22_upscale_seedvr2.json` | Optional SeedVR2 3B int8 video upscale. Needs `INSTALL_SEEDVR2=1` or `DOWNLOAD_SEEDVR2=1` first. |

Workflow sources:

- T2V, I2V, and Animate are adapted from the official Comfy-Org templates in [Comfy-Org/workflow_templates](https://github.com/Comfy-Org/workflow_templates) (`video_wan2_2_14B_t2v.json`, `video_wan2_2_14B_i2v.json`, `video_wan2_2_14B_animate.json`), documented at [Wan 2.2](https://docs.comfy.org/tutorials/video/wan/wan2_2) and [Wan 2.2 Animate](https://docs.comfy.org/tutorials/video/wan/wan2-2-animate). Those templates are MIT; the notice is in `workflows/LICENSE-Comfy-Org-workflow_templates`.
- SeedVR2 is adapted from `utility_seedvr2_3b_int8_upscale_video.json` in the same repo, documented at [SeedVR2](https://docs.comfy.org/tutorials/utility/seedvr2). It uses native ComfyUI nodes.
- The Real-ESRGAN graph is original. It uses core Load Video, Get Video Components, Load Upscale Model, Upscale Image (using Model), Create Video, and Save Video. Weights are the official xinntao releases: [RealESRGAN_x4plus.pth](https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth) and [RealESRGAN_x2plus.pth](https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth).

If you edit a workflow inside ComfyUI, save it under a new name. `start.sh` will not overwrite a copy whose precision stamp still matches. Set `REFRESH_WORKFLOWS=1` to replace them from this repo.

## Speed versus quality

The speed LoRAs in the T2V and I2V graphs are the Lightx2v 4-step files republished by [Comfy-Org/Wan_2.2_ComfyUI_Repackaged](https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged) (the templates label the widgets "lightning"):

- T2V: `wan2.2_t2v_lightx2v_4steps_lora_v1.1_high_noise.safetensors` and `..._low_noise.safetensors`
- I2V: `wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors` and `..._low_noise.safetensors`

On the T2V or I2V subgraph node:

- **Speed:** turn **enable_turbo_mode** on. That is 4 steps total, CFG 1, Euler / simple, high-noise expert for the first 2 steps and low-noise for the last 2, LoRA strength 1.
- **Quality:** leave **enable_turbo_mode** off (the template default). That is 20 steps, CFG 3.5, LoRAs bypassed, split at step 10.
- **Around 8 steps:** leave turbo off and open the subgraph. Set the quality **Int (Steps)** node from 20 to 8 and **split_step** from 10 to 4. There is no separate 8-step LoRA file in the Comfy-Org repack; the shipped speed LoRAs are the 4-step ones. Using them means the 4-step path above, not an 8-step checkpoint.

Wan Animate ships on the official fast setting: **6 steps, CFG 1**, with `lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors` at strength 1 and `WanAnimate_relight_lora_fp16.safetensors` at strength 1. For a cleaner lighting match at higher step counts, set the Lightx2v LoRA strength to 0 and raise the KSampler steps inside **Video Sampling and output**. Leave relight on if you still want the lighting/color match. Drop steps toward 4 for a faster preview.

Real-ESRGAN does not use those LoRAs. x2 is the lighter upscale; x4 is the default in the loader.

## What gets installed

`setup.sh` clones current ComfyUI from [Comfy-Org/ComfyUI](https://github.com/Comfy-Org/ComfyUI) into `/workspace/ComfyUI` and creates `/workspace/ComfyUI/venv` with `--system-site-packages`, so it reuses the image's CUDA PyTorch instead of downloading a second copy.

Custom nodes:

- [ComfyUI-Manager](https://github.com/Comfy-Org/ComfyUI-Manager)
- [ComfyUI-WanVideoWrapper](https://github.com/kijai/ComfyUI-WanVideoWrapper) (Kijai wrapper; the example graphs themselves use native Wan nodes)
- [ComfyUI-VideoHelperSuite](https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite)
- [ComfyUI-KJNodes](https://github.com/kijai/ComfyUI-KJNodes) (Points Editor and mask nodes in the Animate graph)
- [ComfyUI-Frame-Interpolation](https://github.com/Fannovel16/ComfyUI-Frame-Interpolation) (installed without the optional cupy build; RIFE and other interpolator weights download on first use into this checkout, which is on the volume)
- [comfyui_controlnet_aux](https://github.com/Fannovel16/comfyui_controlnet_aux) (DWPose for Animate)
- [ComfyUI-segment-anything-2](https://github.com/kijai/ComfyUI-segment-anything-2)
- [ComfyUI-WanAnimatePreprocess](https://github.com/kijai/ComfyUI-WanAnimatePreprocess) (ViTPose + YOLO, if you build a Kijai preprocess graph)
- [ComfyUI-SeedVR2_VideoUpscaler](https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler) only when `INSTALL_SEEDVR2=1`

Model files, and where they go:

| File | Folder | Source |
| --- | --- | --- |
| `wan2.2_t2v_*_14B_fp8_scaled.safetensors` (or fp16) | `models/diffusion_models` | [Comfy-Org/Wan_2.2_ComfyUI_Repackaged](https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged) |
| `wan2.2_i2v_*_14B_fp8_scaled.safetensors` (or fp16) | `models/diffusion_models` | same |
| `Wan2_2-Animate-14B_fp8_e4m3fn_scaled_KJ.safetensors` | `models/diffusion_models` | [Kijai/WanVideo_comfy_fp8_scaled](https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled) |
| `wan2.2_animate_14B_bf16.safetensors` (fp16 mode only) | `models/diffusion_models` | Comfy-Org repack |
| `umt5_xxl_fp8_e4m3fn_scaled.safetensors` (or fp16) | `models/text_encoders` | Comfy-Org repack |
| `wan_2.1_vae.safetensors` | `models/vae` | Comfy-Org repack. 14B Wan uses the Wan 2.1 VAE. |
| `clip_vision_h.safetensors` | `models/clip_vision` | [Comfy-Org/Wan_2.1_ComfyUI_repackaged](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged) |
| Lightx2v 4-step high/low LoRAs | `models/loras` | Comfy-Org repack. The template uses these filenames. Comfy-Org lists [lightx2v/Wan2.2-Lightning](https://huggingface.co/lightx2v/Wan2.2-Lightning) and [lightx2v/Wan2.2-Distill-Loras](https://huggingface.co/lightx2v/Wan2.2-Distill-Loras) as the upstream sources. |
| `lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors` | `models/loras` | [Kijai/WanVideo_comfy](https://huggingface.co/Kijai/WanVideo_comfy) Lightx2v folder. This is the LoRA the official Animate template loads. |
| `WanAnimate_relight_lora_fp16.safetensors` | `models/loras` | Kijai `LoRAs/Wan22_relight` |
| `sam2_hiera_base_plus.safetensors` | `models/sam2` | [Kijai/sam2-safetensors](https://huggingface.co/Kijai/sam2-safetensors) |
| `yolov10m.onnx`, `vitpose-l-wholebody.onnx` | `models/detection` | [Wan-AI/Wan2.2-Animate-14B](https://huggingface.co/Wan-AI/Wan2.2-Animate-14B) and [JunkyByte/easy_ViTPose](https://huggingface.co/JunkyByte/easy_ViTPose) |
| `yolox_l.onnx`, `dw-ll_ucoco_384_bs5.torchscript.pt` | `custom_nodes/comfyui_controlnet_aux/ckpts/...` | [yzd-v/DWPose](https://huggingface.co/yzd-v/DWPose) and [hr16/DWPose-TorchScript-BatchSize5](https://huggingface.co/hr16/DWPose-TorchScript-BatchSize5) |
| `RealESRGAN_x4plus.pth`, `RealESRGAN_x2plus.pth` | `models/upscale_models` | xinntao Real-ESRGAN releases |
| `seedvr2_3b_int8_convrot.safetensors`, `seedvr2_ema_vae_fp16.safetensors` | `models/diffusion_models` and `models/vae` | [Comfy-Org/SeedVR2](https://huggingface.co/Comfy-Org/SeedVR2), only if SeedVR2 download is on |

`Comfy-Org/Wan_2.2_ComfyUI_Repackaged` is the name used by the ComfyUI docs. The Hugging Face API currently reports that repo id as `Comfy-Org/Wan-2.2`. The resolve URLs on the old name return the files.

Attention stays on PyTorch SDPA, which runs on A6000 (sm_86) and L40S (sm_89). SageAttention is not installed; it is an optional compile and it is easy to break a pod image with it.

## 5. Stop the pod

Stopping the pod stops GPU billing. Use **Stop** in the Runpod console, not a process kill inside the container, if you want billing to end. The network volume keeps ComfyUI and the weights. Start another pod later with the same volume and the same start command; `start.sh` will not download files that are already complete.

Deleting the pod does not delete a network volume. Deleting the volume deletes the install.

## Run it by hand

On a pod that already has the repo:

```bash
cd /workspace/comfy-wan-runpod
bash setup.sh
bash models.sh
bash start.sh
```

`models.sh` alone is safe to repeat. A file is skipped when its size matches the size recorded in the script. A shorter file is resumed.

## Files

- `start.sh` — install if needed, download if needed, launch ComfyUI
- `setup.sh` — ComfyUI, venv, custom nodes
- `models.sh` — weights
- `lib.sh` — clone and download helpers
- `workflows/` — example graphs
- `Dockerfile` — optional, not required
