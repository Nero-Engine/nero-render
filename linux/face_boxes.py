#!/opt/nero/py/bin/python
# Linux stand-in for Projects/Tools/face-boxes (Apple Vision). Same use: face_boxes <png folder> <out.json>
# -> {file: [x, y, w, h]} normalised, origin top-left, largest face only. Uses OpenCV YuNet, then maps its box onto the box
# Apple Vision draws, so Face Circle.py crops the same way on both machines. Calibration 25-10-2026 on 34 frames of the
# Days Like This take: Vision h = 0.716 x YuNet h, w = 1.076 x YuNet w, centre +0.033 / +0.059 YuNet heights (right / down).
import cv2, json, os, sys
MODEL = os.environ.get('YUNET', '/opt/nero/models/face_detection_yunet_2023mar.onnx')
d, outp = sys.argv[1], sys.argv[2]; det = None; out = {}
files = sorted(x for x in os.listdir(d) if x.endswith('.png'))
for f in files:
    im = cv2.imread(os.path.join(d, f))
    if im is None: continue
    h, w = im.shape[:2]
    if det is None: det = cv2.FaceDetectorYN.create(MODEL, '', (w, h), 0.6, 0.3, 5000)
    det.setInputSize((w, h)); _, faces = det.detect(im)
    if faces is None or not len(faces): continue
    x, y, bw, bh = (float(v) for v in max(faces, key=lambda r: r[2])[:4])
    cx = x + bw / 2 + 0.033 * bh; cy = y + bh / 2 + 0.059 * bh; vw = 1.076 * bw; vh = 0.716 * bh
    out[f] = [(cx - vw / 2) / w, (cy - vh / 2) / h, vw / w, vh / h]
json.dump(out, open(outp, 'w'))
print('faces', len(out), 'of', len(files))
