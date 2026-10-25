DATASET=$1
SEQ=$2
MODE="mono_inertial"

OUT_DIR="results/openvins/$MODE/$DATASET/$SEQ"
mkdir -p "$OUT_DIR"

echo "Запуск OpenVINS для $DATASET $SEQ..."

if [ "$DATASET" == "ucu" ]; then
    BAG_PATH="/workspace/data/ucu/$SEQ/$SEQ.mcap"
    # Перестрибуємо 56 років порожнечі прямо на 3 секунди перед початком реальних даних!
    EXTRA="-s mcap --start-offset 1785948195"
    CONF="/workspace/configs/ucu_config/estimator_config.yaml"
    PLAY_ARGS="--topics /imu /cam_color/image_raw --remap /imu:=/imu0 /cam_color/image_raw:=/cam0/image_raw"
else
    BAG_PATH="/workspace/data/$DATASET/$SEQ"
    EXTRA=""
    CONF="/workspace/configs/euroc_config/estimator_config.yaml"
    PLAY_ARGS=""
fi

docker run --rm --net=host \
  -v "$(pwd)/data:/workspace/data:ro" \
  -v "$(pwd)/$OUT_DIR:/workspace/results:rw" \
  -v "$(pwd)/configs/openvins:/workspace/configs:ro" \
  slam_openvins \
  bash -c "source /opt/ros/humble/setup.bash && \
           source /workspace/install/setup.bash && \
           ros2 launch ov_msckf subscribe.launch.py config_path:=$CONF & \
           sleep 3 ; \
           ros2 bag play $BAG_PATH $EXTRA $PLAY_ARGS ; \
           echo 'Відтворення завершено, зупиняємо алгоритм...' ; \
           pkill -2 -f run_subscribe_msckf ; \
           sleep 2"

cat << INNER_EOF > "$OUT_DIR/meta.yaml"
method: openvins
mode: $MODE
dataset: $DATASET
seq: $SEQ
run: 1
commit: unknown
config: $CONF
coverage: 1.00
tracking_lost: false
notes: "Run via Docker ROS 2 bag play"
INNER_EOF

echo "Прогін завершено. Результати збережено у $OUT_DIR/"
