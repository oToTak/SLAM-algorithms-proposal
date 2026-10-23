#!/usr/bin/env bash
set -euo pipefail

SEQ_DIR="$(realpath "$1")"
SEQ="$2"
RUN="${3:-1}"
ORB="${ORB:-$HOME/ORB_SLAM3}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo none)"
GT="$SEQ_DIR/groundtruth.txt"
ASSOC="$ORB/Examples/RGB-D/associations/$SEQ.txt"

command -v evo_ape >/dev/null || { echo "evo not found: activate the venv first"; exit 1; }
[ -f "$ASSOC" ] || { echo "No association file $ASSOC"; exit 1; }

run_mode() {
  local mode="$1" align="$2"; shift 2
  local out="$ROOT/results/orbslam3/$mode/tum/$SEQ"
  mkdir -p "$out"
  local tmp; tmp="$(mktemp -d)"
  (cd "$tmp" && "$@" | tee "$out/log_run$RUN.txt") || echo "WARN: $mode exited with code $?"
  local traj="$tmp/KeyFrameTrajectory.txt"
  [ "$mode" = "rgbd" ] && traj="$tmp/CameraTrajectory.txt"
  [ -s "$traj" ] || { echo "No trajectory saved for $mode"; exit 1; }
  mv "$traj" "$out/traj_run$RUN.txt"
  rm -rf "$tmp"

  local ate
  ate=$(evo_ape tum "$GT" "$out/traj_run$RUN.txt" $align --t_max_diff 0.02 \
          --save_results "$out/ape_run$RUN.zip" --no_warnings | awk '/rmse/{print $2}')
  evo_traj tum "$out/traj_run$RUN.txt" --ref "$GT" $align --sync --t_max_diff 0.02 \
          --plot_mode xy --save_plot "$out/traj_xy_run$RUN.pdf" --no_warnings >/dev/null || true

  local cov
  cov=$(python3 - "$out/traj_run$RUN.txt" "$SEQ_DIR/rgb.txt" <<'PY'
import sys
def span(p):
    ts=[float(l.split()[0]) for l in open(p) if l.strip() and not l.startswith('#')]
    return max(ts)-min(ts)
print(f"{min(1.0, span(sys.argv[1])/span(sys.argv[2])):.2f}")
PY
)
  cat > "$out/meta.yaml" <<YML
method: orbslam3
mode: $mode
dataset: tum
seq: $SEQ
run: $RUN
commit: $COMMIT
config: $( [ "$mode" = rgbd ] && echo Examples/RGB-D/TUM1.yaml || echo Examples/Monocular/TUM1.yaml )
coverage: $cov
tracking_lost: false
notes: "ORB-SLAM3 4452a3c; mono saves keyframes only"
YML
  local csv="$ROOT/results/summary.csv"
  [ -f "$csv" ] || echo "method,mode,dataset,seq,run,ate_rmse_m,rpe_trans_m,coverage,tracking_lost,commit" > "$csv"
  echo "orbslam3,$mode,tum,$SEQ,$RUN,$ate,,$cov,false,$COMMIT" >> "$csv"
  echo ">>> $mode: ATE RMSE = $ate m, coverage = $cov"
}

run_mode rgbd "-a" "$ORB/Examples/RGB-D/rgbd_tum" "$ORB/Vocabulary/ORBvoc.txt" \
  "$ORB/Examples/RGB-D/TUM1.yaml" "$SEQ_DIR" "$ASSOC"
run_mode mono "-as" "$ORB/Examples/Monocular/mono_tum" "$ORB/Vocabulary/ORBvoc.txt" \
  "$ORB/Examples/Monocular/TUM1.yaml" "$SEQ_DIR"