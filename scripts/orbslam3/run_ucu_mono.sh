#!/usr/bin/env bash
set -euo pipefail

SEQ_DIR="$(realpath "$1")"
SEQ="$2"
RUN="${3:-1}"
ORB="${ORB:-$HOME/ORB_SLAM3}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo none)"
CFG="$ROOT/configs/orbslam3/UCU_mono.yaml"
GT="$SEQ_DIR/groundtruth.txt"
OUT="$ROOT/results/orbslam3/mono/ucu/$SEQ"

command -v evo_ape >/dev/null || { echo "evo not found: activate the venv first"; exit 1; }
mkdir -p "$OUT"
TMP="$(mktemp -d)"
(cd "$TMP" && "$ORB/Examples/Monocular/mono_tum" "$ORB/Vocabulary/ORBvoc.txt" "$CFG" "$SEQ_DIR" \
  | tee "$OUT/log_run$RUN.txt") || echo "WARN: mono exited with code $?"
[ -s "$TMP/KeyFrameTrajectory.txt" ] || { echo "No trajectory saved"; exit 1; }
mv "$TMP/KeyFrameTrajectory.txt" "$OUT/traj_run$RUN.txt"; rm -rf "$TMP"

ATE=$(evo_ape tum "$GT" "$OUT/traj_run$RUN.txt" -as --t_max_diff 0.02 \
        --save_results "$OUT/ape_run$RUN.zip" --no_warnings | awk '/rmse/{print $2}')
RPE=$(evo_rpe tum "$GT" "$OUT/traj_run$RUN.txt" -as --delta 10 --delta_unit m --t_max_diff 0.02 \
        --no_warnings | awk '/rmse/{print $2}' || true)
evo_traj tum "$OUT/traj_run$RUN.txt" --ref "$GT" -as --sync --t_max_diff 0.02 \
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
mode: mono
dataset: ucu
seq: $SEQ
run: $RUN
commit: $COMMIT
config: configs/orbslam3/UCU_mono.yaml
coverage: $COV
tracking_lost: false
notes: "keyframe trajectory; Sim(3)-aligned to GNSS (position-only, ~1 m)"
YML
CSV="$ROOT/results/summary.csv"
[ -f "$CSV" ] || echo "method,mode,dataset,seq,run,ate_rmse_m,rpe_trans_m,coverage,tracking_lost,commit" > "$CSV"
echo "orbslam3,mono,ucu,$SEQ,$RUN,$ATE,$RPE,$COV,false,$COMMIT" >> "$CSV"
echo ">>> ATE RMSE = $ATE m, RPE(10 m) = $RPE m, coverage = $COV"