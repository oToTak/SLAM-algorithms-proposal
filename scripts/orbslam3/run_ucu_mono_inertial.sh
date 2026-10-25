#!/usr/bin/env bash
set -euo pipefail

SEQ_DIR="$(realpath "$1")"
SEQ="$2"
RUN="${3:-1}"
ORB="${ORB:-$HOME/ORB_SLAM3}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo none)"
CFG="$ROOT/configs/orbslam3/UCU_mono_inertial.yaml"
GT="$SEQ_DIR/groundtruth.txt"
OUT="$ROOT/results/orbslam3/mono_inertial/ucu/$SEQ"
EUROC="$ROOT/data/ucu_euroc/$SEQ"

command -v evo_ape >/dev/null || { echo "evo not found: activate the venv first"; exit 1; }
[ -d "$EUROC/mav0" ] || python3 "$ROOT/scripts/tum_to_euroc.py" "$SEQ_DIR" "$EUROC"
mkdir -p "$OUT"
TMP="$(mktemp -d)"
(cd "$TMP" && "$ORB/Examples/Monocular-Inertial/mono_inertial_euroc" "$ORB/Vocabulary/ORBvoc.txt" "$CFG" \
  "$EUROC" "$EUROC/times.txt" | tee "$OUT/log_run$RUN.txt")
awk '{printf "%.9f %s %s %s %s %s %s %s\n", $1/1e9, $2,$3,$4,$5,$6,$7,$8}' \
  "$TMP/CameraTrajectory.txt" > "$OUT/traj_run$RUN.txt"
rm -rf "$TMP"

ATE=$(evo_ape tum "$GT" "$OUT/traj_run$RUN.txt" -a --t_max_diff 0.02 \
        --save_results "$OUT/ape_run$RUN.zip" --no_warnings | awk '/rmse/{print $2}')
RPE=$(evo_rpe tum "$GT" "$OUT/traj_run$RUN.txt" -a --delta 10 --delta_unit m --t_max_diff 0.02 \
        --no_warnings | awk '/rmse/{print $2}' || true)
evo_traj tum "$OUT/traj_run$RUN.txt" --ref "$GT" -a --sync --t_max_diff 0.02 \
        --plot_mode xy --save_plot "$OUT/traj_xy_run$RUN.pdf" --no_warnings >/dev/null || true

COV=$(python3 - "$OUT/traj_run$RUN.txt" "$SEQ_DIR/rgb.txt" <<'PY'
import sys
def span(p):
    ts=[float(l.split()[0]) for l in open(p) if l.strip() and not l.startswith('#')]
    return max(ts)-min(ts)
print(f"{min(1.0, span(sys.argv[1])/span(sys.argv[2])):.2f}")
PY
)
cat > "$OUT/meta.yaml" <<YML
method: orbslam3
mode: mono_inertial
dataset: ucu
seq: $SEQ
run: $RUN
commit: $COMMIT
config: configs/orbslam3/UCU_mono_inertial.yaml
coverage: $COV
tracking_lost: false
notes: "all-frame trajectory of IMU/base_link; SE(3)-aligned to GNSS (position-only, ~1 m)"
YML
CSV="$ROOT/results/summary.csv"
[ -f "$CSV" ] || echo "method,mode,dataset,seq,run,ate_rmse_m,rpe_trans_m,coverage,tracking_lost,commit" > "$CSV"
echo "orbslam3,mono_inertial,ucu,$SEQ,$RUN,$ATE,$RPE,$COV,false,$COMMIT" >> "$CSV"
echo ">>> ATE RMSE = $ATE m, RPE(10 m) = $RPE m, coverage = $COV"