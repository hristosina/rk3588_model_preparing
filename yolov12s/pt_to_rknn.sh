#!/usr/bin/env bash
set -Eeuo pipefail

MODEL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$MODEL_DIR")"
PY="$MODEL_DIR/.venv/bin/python"
TURBO_REPO="$ROOT/ultralytics_yolov12"
CONVERTER="$ROOT/rknn_model_zoo/examples/yolov8/python/convert.py"

usage() {
    echo "Usage: $0 /path/to/model.pt {standard|turbo}" >&2
    echo "  standard - Ultralytics 8.3.237, AAttn with qkv" >&2
    echo "  turbo    - sunsmarterjie/yolov12, AAttn with qk and v" >&2
}

if [[ $# -ne 2 ]]; then
    usage
    exit 1
fi

VARIANT="$2"
case "$VARIANT" in
    standard|turbo) ;;
    *) usage; exit 1 ;;
esac

[[ -f "$1" && -s "$1" && "$1" == *.pt ]] || {
    echo "ERROR: нужен существующий непустой файл .pt: $1" >&2
    exit 1
}
SRC="$(realpath -e -- "$1")"
[[ -x "$PY" ]] || { echo "ERROR: нет $PY. Запустите setup_rknn.sh" >&2; exit 1; }
[[ -f "$CONVERTER" ]] || { echo "ERROR: нет $CONVERTER" >&2; exit 1; }
[[ "$VARIANT" != turbo || -f "$TURBO_REPO/ultralytics/__init__.py" ]] || {
    echo "ERROR: не найден оригинальный репозиторий YOLOv12: $TURBO_REPO" >&2
    exit 1
}

NAME="$(basename -- "$SRC" .pt)"
TMP="$(mktemp -d "$MODEL_DIR/.export.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT
cp -- "$SRC" "$TMP/$NAME.pt"

# Каждый запуск использует только окружение yolov12s/.venv.
# Для turbo Python импортирует код оригинального репозитория через PYTHONPATH.
# Для standard используется установленный в этом venv пакет Ultralytics.
if [[ "$VARIANT" == turbo ]]; then
    PY_CMD=(env -u PYTHONHOME -u VIRTUAL_ENV PYTHONPATH="$TURBO_REPO" PYTHONNOUSERSITE=1 "$PY")
else
    PY_CMD=(env -u PYTHONPATH -u PYTHONHOME -u VIRTUAL_ENV PYTHONNOUSERSITE=1 "$PY")
fi

printf '==> YOLO12 %s: %s -> ONNX (512x512)\n' "$VARIANT" "$NAME.pt"
(
    cd "$TMP"
    "${PY_CMD[@]}" - "$TMP/$NAME.pt" "$VARIANT" "$TURBO_REPO" <<'PYTHON'
import sys
from pathlib import Path
import ultralytics
from ultralytics import YOLO

weights = Path(sys.argv[1])
variant = sys.argv[2]
turbo_repo = Path(sys.argv[3]).resolve()
actual = Path(ultralytics.__file__).resolve()

if variant == 'standard':
    if ultralytics.__version__ != '8.3.237' or actual.is_relative_to(turbo_repo):
        raise RuntimeError(f'Требуется стандартная Ultralytics 8.3.237, загружена {ultralytics.__version__} ({actual}). Запустите setup_rknn.sh')
else:
    if not actual.is_relative_to(turbo_repo):
        raise RuntimeError(f'Требуется оригинальный YOLOv12 из {turbo_repo}, загружен {actual}. Запустите setup_rknn.sh')

model = YOLO(str(weights))
attn = [m for m in model.model.modules() if type(m).__name__ == 'AAttn']
if variant == 'standard' and any(hasattr(m, 'qk') and not hasattr(m, 'qkv') for m in attn):
    raise RuntimeError('Веса содержат AAttn.qk (YOLO12-Turbo). Выберите вариант turbo.')
if variant == 'turbo' and any(hasattr(m, 'qkv') and not hasattr(m, 'qk') for m in attn):
    raise RuntimeError('Веса содержат AAttn.qkv (стандартная YOLO12). Выберите вариант standard.')

print('Ultralytics:', ultralytics.__version__, actual)
model.export(
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

printf '==> ONNX -> RKNN (rk3588, FP)\n'
(
    cd "$(dirname "$CONVERTER")"
    env -u PYTHONPATH -u PYTHONHOME -u VIRTUAL_ENV PYTHONNOUSERSITE=1 \
        "$PY" "$CONVERTER" "$TMP/$NAME.onnx" rk3588 fp "$TMP/$NAME.rknn"
)
[[ -s "$TMP/$NAME.rknn" ]] || { echo 'ERROR: RKNN не создан' >&2; exit 1; }
mv -f -- "$TMP/$NAME.onnx" "$MODEL_DIR/$NAME.onnx"
mv -f -- "$TMP/$NAME.rknn" "$MODEL_DIR/$NAME.rknn"
printf 'Готово:\n  %s\n  %s\n' "$MODEL_DIR/$NAME.onnx" "$MODEL_DIR/$NAME.rknn"
