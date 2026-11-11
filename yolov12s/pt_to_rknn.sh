#!/usr/bin/env bash
set -Eeuo pipefail

MODEL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$MODEL_DIR")"
VENV="$MODEL_DIR/.venv"
PY="$VENV/bin/python"
FORK="$ROOT/ultralytics_yolov12"
CONVERTER="$ROOT/rknn_model_zoo/examples/yolov8/python/convert.py"

[[ $# -eq 1 ]] || { echo "Usage: $0 /path/to/model.pt" >&2; exit 1; }
SRC="$(realpath -e -- "$1")"
[[ -f "$SRC" && -s "$SRC" && "$SRC" == *.pt ]] || { echo 'ERROR: нужен существующий .pt файл' >&2; exit 1; }
[[ -x "$PY" ]] || { echo "ERROR: нет $PY, запустите ../setup_rknn.sh" >&2; exit 1; }
[[ -f "$CONVERTER" && -d "$FORK/ultralytics" ]] || { echo 'ERROR: отсутствуют официальные репозитории' >&2; exit 1; }

source "$VENV/bin/activate"
unset PYTHONPATH PYTHONHOME
export PYTHONNOUSERSITE=1

NAME="$(basename -- "$SRC" .pt)"
TMP="$(mktemp -d "$MODEL_DIR/.export.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT
cp -- "$SRC" "$TMP/$NAME.pt"

echo "==> Экспорт YOLOv12: $NAME.pt -> ONNX"
(
    cd "$TMP"
    "$PY" - "$TMP/$NAME.pt" "$FORK" <<'PYTHON'
from pathlib import Path
import sys
import ultralytics
from ultralytics import YOLO

weights, repo = map(Path, sys.argv[1:3])
actual = Path(ultralytics.__file__).resolve()
if not actual.is_relative_to(repo.resolve()):
    raise RuntimeError(f'Загружен не YOLOv12 fork: {actual}')
YOLO(str(weights)).export(
    format='onnx', imgsz=512, batch=1, device='cpu',
    opset=17, dynamic=False, nms=False, simplify=False,
)
PYTHON
)
[[ -s "$TMP/$NAME.onnx" ]] || { echo 'ERROR: ONNX не создан' >&2; exit 1; }
"$PY" - "$TMP/$NAME.onnx" <<'PYTHON'
import onnx
import sys
onnx.checker.check_model(sys.argv[1])
print('ONNX validation: OK')
PYTHON

echo "==> Конвертация RKNN (rk3588, FP)"
(
    cd "$(dirname "$CONVERTER")"
    "$PY" "$CONVERTER" "$TMP/$NAME.onnx" rk3588 fp "$TMP/$NAME.rknn"
)
[[ -s "$TMP/$NAME.rknn" ]] || { echo 'ERROR: RKNN не создан' >&2; exit 1; }
mv -f -- "$TMP/$NAME.onnx" "$MODEL_DIR/$NAME.onnx"
mv -f -- "$TMP/$NAME.rknn" "$MODEL_DIR/$NAME.rknn"
echo "Готово: $MODEL_DIR/$NAME.rknn"

