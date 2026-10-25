#!/opt/nero/py/bin/python
# Linux stand-in for media-use transcribe.mjs (Parakeet MLX on the Mac). Same model family (NVIDIA Parakeet TDT 0.6b v3),
# run with onnx-asr on the GPU when it can, else on the CPU. Same output: {"text", "words": [{"text", "start", "end"}]}.
# Usage: transcribe --input audio_or_video --out words.json [--model nemo-parakeet-tdt-0.6b-v3] [--cpu]
import argparse, json, os, subprocess, tempfile, sys
ap = argparse.ArgumentParser(); ap.add_argument('--input', '-i', required=True); ap.add_argument('--out', '-o')
ap.add_argument('--model', default='nemo-parakeet-tdt-0.6b-v3'); ap.add_argument('--model-dir', default='/opt/nero/models/parakeet-tdt-0.6b-v3'); ap.add_argument('--cpu', action='store_true'); a = ap.parse_args()
out = a.out or os.path.splitext(a.input)[0] + '.transcribe.json'
os.environ.setdefault('HF_HOME', '/opt/nero/models/hf')
import onnxruntime as rt, onnx_asr
try: rt.preload_dlls()   # CUDA and cuDNN from the pip nvidia-* wheels
except Exception: pass
wav = tempfile.mktemp(suffix='.wav')
subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-y', '-i', a.input, '-vn', '-ac', '1', '-ar', '16000', '-c:a', 'pcm_s16le', wav], check=True)
prov = ['CPUExecutionProvider'] if a.cpu else [p for p in ('CUDAExecutionProvider', 'CPUExecutionProvider') if p in rt.get_available_providers()]
def run(providers):
    m = onnx_asr.load_model(a.model, a.model_dir if os.path.isdir(a.model_dir) else None, providers=providers)
    vd = '/opt/nero/models/silero-vad'
    try: vad = onnx_asr.load_vad('silero', vd if os.path.isdir(vd) else None, providers=['CPUExecutionProvider'])
    except Exception: vad = onnx_asr.load_vad('silero', providers=['CPUExecutionProvider'])
    return list(m.with_vad(vad).with_timestamps().recognize(wav))
try: segs = run(prov); used = prov[0]
except Exception as e:
    print('GPU run failed, using CPU:', str(e)[:200], file=sys.stderr); segs = run(['CPUExecutionProvider']); used = 'CPUExecutionProvider'
words = []
for s in segs:   # timestamps are seconds from the segment start; a token starting with ▁ begins a new word
    toks, ts = s.tokens or [], [s.start + t for t in (s.timestamps or [])]
    for i, (t, st) in enumerate(zip(toks, ts)):
        en = min(ts[i + 1], st + 0.6) if i + 1 < len(ts) else min(s.end, st + 0.5)
        if t[:1] in ('\u2581', ' ') or i == 0 or not words:
            words.append({'text': t.replace('\u2581', '').strip(), 'start': round(st, 3), 'end': round(en, 3)})
        else:
            words[-1]['text'] += t; words[-1]['end'] = round(en, 3)
words = [w for w in words if w['text']]
json.dump({'text': ' '.join(s.text.strip() for s in segs), 'words': words}, open(out, 'w'), indent=1)
os.remove(wav)
print(f'transcribed {os.path.basename(a.input)} -> {out} ({len(words)} words, parakeet on {used})')
