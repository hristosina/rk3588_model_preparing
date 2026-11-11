# RKNN Model Conversion (RK3588)

Конвертация YOLOv8/YOLO12 в RKNN на Ubuntu 22.04 x86-64 (Python 3.10).

## Установка

```bash
sudo apt update
sudo apt install -y git python3.10 python3.10-venv
cd ~/rk3588
chmod +x setup_rknn.sh
./setup_rknn.sh
```

`setup_rknn.sh` скачивает репозитории Rockchip и YOLOv12 на фиксированных коммитах, создаёт общее `.venv` и устанавливает RKNN-Toolkit2 2.5.0 и Ultralytics 8.3.237. Экспортёры YOLOv8 и YOLOv12 подключаются из соответствующих исходников через `PYTHONPATH`.

## YOLOv8s

```bash
cd ~/rk3588/yolov8s
chmod +x pt_to_rknn.sh
./pt_to_rknn.sh /path/to/best.pt
```

Экспорт через форк Rockchip и конвертер RKNN Model Zoo.

## YOLO12s

```bash
cd ~/rk3588/yolov12s
chmod +x pt_to_rknn.sh
./pt_to_rknn.sh /path/to/best.pt
```

Экспорт ONNX через оригинальный форк `sunsmarterjie/yolov12` (YOLOv12-Turbo), затем конвертация в RKNN через RKNN Model Zoo.

Оба скрипта сохраняют `best.onnx` и `best.rknn` в своей папке. Параметры: RK3588, 512×512, batch 1, без INT8-квантования. Ручная активация `.venv` не требуется.

