# Nero render toolkit: Blender 5.2.2 (Cycles OptiX), Node 24 + hyperframes@0.8.138 with its Chrome headless shell and Linux
# libraries, ffmpeg (libvpx, libx264, NVENC), NVIDIA Parakeet speech-to-text (onnx-asr, CPU) and OpenCV YuNet faces.
# Built by GitHub Actions (.github/workflows/build-image.yml), never on the Mac. Pods on this image skip the install.
FROM ubuntu:24.04
LABEL org.opencontainers.image.source=https://github.com/Nero-Engine/nero-render
LABEL org.opencontainers.image.description="Blender, HyperFrames, ffmpeg and speech-to-text for cloud video builds"
COPY setup.sh /opt/nero/setup.sh
COPY linux/ /opt/nero/linux/
RUN bash /opt/nero/setup.sh blender hyperframes py \
 && for f in /opt/nero/linux/*.py; do b=$(basename $f .py | tr _ -); cp $f /opt/nero/bin/$b; chmod +x /opt/nero/bin/$b; done \
 && rm -rf /var/lib/apt/lists/* /root/.npm /root/.cache/pip /tmp/*
ENV PATH=/opt/nero/bin:/opt/nero/node/bin:$PATH HF_HOME=/opt/nero/models/hf HYPERFRAMES_NO_TELEMETRY=1 NVIDIA_DRIVER_CAPABILITIES=all
