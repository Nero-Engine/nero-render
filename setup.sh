#!/bin/bash
# Installs the Nero render toolkit into /opt/nero on a plain ubuntu:24.04 pod. The ready-made image (image/Dockerfile) runs
# this same script at build time, so on that image it finds everything in /opt/nero/READY and returns at once.
# Usage: setup.sh [blender] [hyperframes] [py]     (no args = everything). Steps go to stdout, details to /tmp/<step>.log.
# Blender, HyperFrames and the Python tools install at the same time after the system packages.
WANT="${*:-blender hyperframes py}"
BLENDER_V=5.2.2; NODE_V=24.18.0; HF_V=0.8.138
N=/opt/nero; mkdir -p $N/bin $N/models
have() { grep -qx "$1" $N/READY 2>/dev/null; }
want() { case " $WANT " in *" $1 "*) ! have $1;; *) false;; esac; }
mark() { echo "$1" >> $N/READY; }
step() { echo "$(date +%T) $*"; }
die() { echo "SETUP FAILED: $1"; for f in /tmp/$2.log; do [ -f $f ] && grep -v -E '^\*+$|EP Error|Falling back|when using' $f | tail -25; done; exit 1; }
export DEBIAN_FRONTEND=noninteractive
command -v curl >/dev/null || { apt-get update -qq && apt-get install -y -qq --no-install-recommends curl ca-certificates > /tmp/apt0.log 2>&1; }
want blender && (curl -sfL -o /tmp/b.tar.xz https://download.blender.org/release/Blender${BLENDER_V%.*}/blender-${BLENDER_V}-linux-x64.tar.xz; echo $? > /tmp/b.rc) &
want hyperframes && (curl -sfL -o /tmp/n.tar.xz https://nodejs.org/dist/v${NODE_V}/node-v${NODE_V}-linux-x64.tar.xz; echo $? > /tmp/n.rc) &
if ! have apt; then
  step apt
  { apt-get update -qq && apt-get install -y -qq --no-install-recommends python3 python3-venv python3-pip curl wget ca-certificates xz-utils zstd unzip ffmpeg \
    libxrender1 libxi6 libxkbcommon0 libsm6 libgl1 libxxf86vm1 libxfixes3 libegl1 libglib2.0-0t64 libx11-6 libxext6 libwayland-client0 libdbus-1-3 \
    libnss3 libnspr4 libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 libdrm2 libatspi2.0-0t64 libxcomposite1 libxdamage1 libxrandr2 \
    libgbm1 libpango-1.0-0 libcairo2 libasound2t64 libvulkan1 libgles2 fonts-liberation fontconfig; } > /tmp/apt.log 2>&1 || die apt apt
  mark apt; step apt done
fi
wait   # the two downloads
do_blender() {
  [ "$(cat /tmp/b.rc)" = 0 ] || { echo "blender download failed"; return 1; }
  tar -C $N -xf /tmp/b.tar.xz && mv $N/blender-${BLENDER_V}-linux-x64 $N/blender && rm /tmp/b.tar.xz && ln -sf $N/blender/blender $N/bin/blender
}
do_hyperframes() {
  [ "$(cat /tmp/n.rc)" = 0 ] || { echo "node download failed"; return 1; }
  tar -C $N -xf /tmp/n.tar.xz && mv $N/node-v${NODE_V}-linux-x64 $N/node && rm /tmp/n.tar.xz || return 1
  export PATH=$N/node/bin:$PATH
  timeout 600 npm install -g --no-fund --no-audit hyperframes@${HF_V} < /dev/null || return 1
  for b in node npx npm hyperframes; do ln -sf $N/node/bin/$b $N/bin/$b; done
  # downloads hyperframes' own Chrome headless shell (the same build the Mac uses)
  HYPERFRAMES_NO_TELEMETRY=1 CI=1 timeout 300 hyperframes browser ensure < /dev/null || echo "hyperframes browser ensure exited $? (render will fetch Chrome itself)"
}
do_py() {
  python3 -m venv $N/py || return 1
  timeout 900 $N/py/bin/pip install --progress-bar off numpy opencv-python-headless "onnx-asr[hub]" "${ORT_PKG:-onnxruntime}" \
    || return 1
  curl -sfL -o $N/models/face_detection_yunet_2023mar.onnx https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx || return 1
  HF_HOME=$N/models/hf timeout 600 $N/py/bin/python -c "
from huggingface_hub import snapshot_download as d; import onnx_asr
d('istupakov/parakeet-tdt-0.6b-v3-onnx', local_dir='$N/models/parakeet-tdt-0.6b-v3')
onnx_asr.load_model('nemo-parakeet-tdt-0.6b-v3', '$N/models/parakeet-tdt-0.6b-v3', providers=['CPUExecutionProvider'])
d('istupakov/silero-vad-onnx', local_dir='$N/models/silero-vad'); onnx_asr.load_vad('silero', '$N/models/silero-vad', providers=['CPUExecutionProvider'])
print('models ok')"
}
pids=()
for s in blender hyperframes py; do
  if want $s; then step $s; ( do_$s > /tmp/$s.log 2>&1; echo $? > /tmp/$s.rc ) & pids+=($!); fi
done
wait "${pids[@]}" 2>/dev/null
for s in blender hyperframes py; do
  if want $s; then [ "$(cat /tmp/$s.rc)" = 0 ] || die $s $s; mark $s; step $s done; fi
done
echo "setup ok: $(tr '\n' ' ' < $N/READY)"
