#!/usr/bin/env bash
set -Eeuo pipefail

MODEL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$MODEL_DIR")"
VENV="$MODEL_DIR/.venv"
PY="$VENV/bin/python"
FORK="$ROOT/ultralytics_yolov8"
CONVERTER="$ROOT/rknn_model_zoo/examples/yolov8/python/convert.py"

[[ $# -eq 1 ]] || { echo "Usage: $0 /path/to/model.pt" >&2; exit 1; }
SRC="$(realpath -e -- "$1")"
[[ -f "$SRC" && -s "$SRC" && "$SRC" == *.pt ]] || { echo 'ERROR: нужен существующий .pt файл' >&2; exit 1; }
[[ -x "$PY" ]] || { echo "ERROR: нет $PY, запустите ../setup_rknn.sh" >&2; exit 1; }
[[ -f "$CONVERTER" && -d "$FORK/ultralytics" ]] || { echo 'ERROR: отсутствуют официальные репозитории' >&2; exit 1; }

# Переключаем Python внутри скрипта; окружение вызывающей оболочки не изменяется.
source "$VENV/bin/activate"
unset PYTHONPATH PYTHONHOME
export PYTHONNOUSERSITE=1

NAME="$(basename -- "$SRC" .pt)"
TMP="$(mktemp -d "$MODEL_DIR/.export.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT
cp -- "$SRC" "$TMP/$NAME.pt"

echo "==> Экспорт YOLOv8: $NAME.pt -> ONNX"
(
    cd "$TMP"
    "$PY" - "$TMP/$NAME.pt" "$FORK" <<'PYTHON'
from pathlib import Path
import sys
import ultralytics
from ultralytics import YOLO
import onnx

weights, repo = map(Path, sys.argv[1:3])
actual = Path(ultralytics.__file__).resolve()
if not actual.is_relative_to(repo.resolve()):
    raise RuntimeError(f'Загружен не Rockchip fork: {actual}')
YOLO(str(weights)).export(format='rknn', imgsz=512, batch=1, device='cpu')
output = weights.with_suffix('.onnx')
if not output.is_file():
    raise RuntimeError(f'Не создан ONNX: {output}')
onnx.checker.check_model(str(output))
print('ONNX validation: OK')
PYTHON
)

echo "==> Конвертация RKNN (rk3588, FP)"
(
    cd "$(dirname "$CONVERTER")"
    "$PY" "$CONVERTER" "$TMP/$NAME.onnx" rk3588 fp "$TMP/$NAME.rknn"
)
[[ -s "$TMP/$NAME.rknn" ]] || { echo 'ERROR: RKNN не создан' >&2; exit 1; }
mv -f -- "$TMP/$NAME.onnx" "$MODEL_DIR/$NAME.onnx"
mv -f -- "$TMP/$NAME.rknn" "$MODEL_DIR/$NAME.rknn"
echo "Готово: $MODEL_DIR/$NAME.rknn"

