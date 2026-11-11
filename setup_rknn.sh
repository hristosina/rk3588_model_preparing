#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

[[ "$(uname -m)" == x86_64 ]] || { echo 'ERROR: требуется Ubuntu x86-64' >&2; exit 1; }
command -v git >/dev/null || { echo 'ERROR: установите git' >&2; exit 1; }
command -v python3.10 >/dev/null || { echo 'ERROR: установите python3.10 и python3.10-venv' >&2; exit 1; }

clone_at_commit() {
    local name="$1" url="$2" commit="$3"
    if [[ ! -e "$ROOT/$name" ]]; then
        git clone "$url" "$ROOT/$name"
    fi
    [[ -d "$ROOT/$name/.git" ]] || { echo "ERROR: $name не является Git-репозиторием" >&2; exit 1; }
    if [[ "$(git -C "$ROOT/$name" rev-parse HEAD)" != "$commit" ]]; then
        [[ -z "$(git -C "$ROOT/$name" status --porcelain --untracked-files=no)" ]] || {
            echo "ERROR: несохранённые изменения в $name" >&2; exit 1;
        }
        if ! git -C "$ROOT/$name" cat-file -e "${commit}^{commit}" 2>/dev/null; then
            git -C "$ROOT/$name" fetch origin "$commit"
        fi
        git -C "$ROOT/$name" checkout --detach "$commit"
    fi
    echo "OK: $name @ $(git -C "$ROOT/$name" rev-parse --short=12 HEAD)"
}

clone_at_commit rknn-toolkit2 https://github.com/airockchip/rknn-toolkit2.git 2c723177a94fac65cbc036d722907ddbc91980cf
clone_at_commit rknn_model_zoo https://github.com/airockchip/rknn_model_zoo.git 837db8e992815ff8647eadb709f07067f4bc3a71
clone_at_commit ultralytics_yolov8 https://github.com/airockchip/ultralytics_yolov8.git 4674fe6e003dfbc5f2250d3b39dd31faaf7a9877
clone_at_commit ultralytics_yolov12 https://github.com/sunsmarterjie/yolov12.git 9422f97c25ea3ee5f25a29d079a55a49bd9c5602

RKNN_REQ="$ROOT/rknn-toolkit2/rknn-toolkit2/packages/x86_64/requirements_cp310.txt"
[[ -f "$RKNN_REQ" ]] || { echo "ERROR: отсутствует $RKNN_REQ" >&2; exit 1; }

setup_env() {
    local model="$1" torch_version="$2" vision_version="$3" fork="$4"
    local env_dir="$ROOT/$model/.venv"
    local py="$env_dir/bin/python"

    echo "==> Настройка $model: $env_dir"
    mkdir -p "$ROOT/$model"
    if [[ ! -x "$py" ]]; then
        python3.10 -m venv "$env_dir"
    fi
    env -u PYTHONPATH -u PYTHONHOME "$py" -c \
        'import sys; assert sys.version_info[:2] == (3, 10), "Требуется Python 3.10"'

    pip_install() { env -u PYTHONPATH -u PYTHONHOME -u VIRTUAL_ENV "$py" -m pip install "$@"; }
    pip_install 'pip==24.3.1' 'setuptools==80.9.0' 'wheel==0.45.1'

    # CPU-only PyTorch: конвертация выполняется на Ubuntu VM, не на RK3588.
    pip_install "torch==$torch_version" "torchvision==$vision_version" \
        --index-url https://download.pytorch.org/whl/cpu

    # Зависимости RKNN и экспорта ONNX.
    pip_install \
        'numpy==1.26.4' 'protobuf==4.25.4' \
        'onnx==1.18.0' 'onnxruntime==1.20.1' \
        'opencv-python==4.10.0.84' 'scipy==1.13.1' \
        'tqdm==4.67.1' 'psutil==6.1.1' \
        'ruamel.yaml==0.18.10' 'fast-histogram==0.14' \
        'matplotlib==3.9.2' 'pillow==10.4.0' \
        'PyYAML==6.0.2' 'requests==2.32.3' \
        'pandas==2.2.3' 'seaborn==0.13.2' \
        'py-cpuinfo==9.0.0' 'ultralytics-thop==2.0.18' \
        'polars==1.35.2'
    pip_install -r "$RKNN_REQ"
    pip_install --no-deps 'rknn-toolkit2==2.5.0'

    if [[ "$model" == yolov12s ]]; then
        # YOLOv12-Turbo: зависимости, отсутствующие в основном pyproject.toml.
        # Не устанавливаем весь requirements.txt: в нём CUDA/flash-attn для cp311
        # и ONNX 1.14.0, несовместимый с ограничениями RKNN-Toolkit2 2.5.0.
        pip_install 'huggingface-hub==0.23.2' 'safetensors==0.4.3' 'timm==1.0.14'
    fi

    # Каждый fork устанавливается только в СВОЙ venv, вместо PYTHONPATH.
    pip_install --no-deps -e "$ROOT/$fork"

    env -u PYTHONPATH -u PYTHONHOME -u VIRTUAL_ENV "$py" -m pip check
    env -u PYTHONPATH -u PYTHONHOME -u VIRTUAL_ENV "$py" - "$ROOT/$fork" <<'PYTHON'
import sys
from pathlib import Path
from importlib.metadata import version
import ultralytics
from rknn.api import RKNN

expected = Path(sys.argv[1]).resolve()
actual = Path(ultralytics.__file__).resolve()
assert actual.is_relative_to(expected), f'Ожидали {expected}, но импортируется {actual}'
assert version('rknn-toolkit2') == '2.5.0'
print('Ultralytics:', ultralytics.__version__, actual)
print('RKNN-Toolkit2:', version('rknn-toolkit2'))
PYTHON
    echo "OK: $model"
}

setup_env yolov8s 2.4.0 0.19.0 ultralytics_yolov8
setup_env yolov12s 2.2.2 0.17.2 ultralytics_yolov12

echo '==> Окружения готовы:'
echo "    $ROOT/yolov8s/.venv"
echo "    $ROOT/yolov12s/.venv"

