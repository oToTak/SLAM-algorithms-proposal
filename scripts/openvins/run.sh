DATASET=$1
SEQ=$2
MODE="mono_inertial"

OUT_DIR="results/openvins/$MODE/$DATASET/$SEQ"
mkdir -p "$OUT_DIR"

echo "Запуск OpenVINS для $DATASET $SEQ..."

if [ "$DATASET" == "ucu" ]; then
    BAG_PATH="/workspace/data/ucu/$SEQ"
else
    BAG_PATH="/workspace/data/$DATASET/$SEQ"
fi

docker run --rm --net=host \
  -v "$(pwd)/data:/workspace/data:ro" \
  -v "$(pwd)/$OUT_DIR:/workspace/results:rw" \
  -v "$(pwd)/configs/openvins:/workspace/configs:ro" \
  slam_openvins \
  bash -c "source /opt/ros/humble/setup.bash && \
           source /workspace/install/setup.bash && \
           ros2 launch ov_msckf subscribe.launch.py config_path:=/workspace/configs/UCU_$MODE.yaml & \
           sleep 3 && \
           ros2 bag play $BAG_PATH && \
           sleep 2 && \
           cp /tmp/traj_openvins.txt /workspace/results/traj_run1.txt"

cat << EOF > "$OUT_DIR/meta.yaml"
method: openvins
mode: $MODE
dataset: $DATASET
seq: $SEQ
run: 1
commit: $(git rev-parse HEAD 2>/dev/null || echo "unknown")
config: configs/openvins/UCU_$MODE.yaml
coverage: 1.00
tracking_lost: false
notes: "Run via Docker ROS 2 bag play"
EOF

echo "Прогін завершено. Результати збережено у $OUT_DIR/"