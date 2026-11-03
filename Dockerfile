# Optional. The supported path is a stock Runpod PyTorch pod plus the
# container start command in the README. This file only adds OS packages on
# top of a published runpod/pytorch CUDA 12 image. ComfyUI and the weights
# still install onto the network volume at /workspace the first time start.sh
# runs. Do not bake models into an image.
#
# Tag checked on Docker Hub (HTTP 200) on 2026-11-03:
#   runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04

FROM runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04

USER root
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        aria2 \
        ca-certificates \
        wget \
        ffmpeg \
        libgl1 \
        libglib2.0-0 \
        build-essential \
        python3-venv \
        python3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
EXPOSE 8188
CMD ["bash", "-lc", "cd /workspace && (test -d comfy-wan-runpod || git clone https://github.com/blackridder22/comfy-wan-runpod) && cd comfy-wan-runpod && git pull && bash start.sh"]
