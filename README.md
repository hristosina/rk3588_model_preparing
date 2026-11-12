# RKNN conversion (RK3588)

Ubuntu 22.04 x86-64, Python 3.10. Конвертация моделей в `.rknn` без INT8-квантования (512×512, batch 1).

## Установка

```bash
sudo apt install -y git python3.10 python3.10-venv
./setup_rknn.sh
```

Скрипт клонирует зафиксированные репозитории, настраивает независимые окружения `yolov8s/.venv` и `yolov12s/.venv`.

## YOLOv8s

```bash
./yolov8s/pt_to_rknn.sh /path/to/model.pt
```

## YOLO12s

Выберите реализацию, на которой обучена модель:

```bash
# Стандартная Ultralytics (AAttn.qkv)
./yolov12s/pt_to_rknn.sh /path/to/model.pt standard

# Оригинальный YOLOv12-Turbo (AAttn.qk и AAttn.v)
./yolov12s/pt_to_rknn.sh /path/to/model.pt turbo
```

Оба варианта используют `yolov12s/.venv`. Результаты сохраняются как `model.onnx` и `model.rknn` в каталоге соответствующей модели. При одинаковом исходном имени повторный запуск перезапишет результаты.

`pt_to_rknn.sh` не проверяет количество классов; для запуска на RK3588 нужна постобработка, соответствующая выходам конкретного ONNX/RKNN.
