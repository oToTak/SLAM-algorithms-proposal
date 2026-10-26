#!/usr/bin/env bash
# Usage: scripts/dpvo/run.sh <dataset> <seq>   e.g. tum fr1_xyz | ucu seq01
# Runs mono DPVO (stride 1) and writes results/dpvo/mono/<dataset>/<seq>/traj_run<N>.txt + meta.yaml.
# Needs a CUDA GPU and DPVO installed (see docker/dpvo/README.md). Env: DPVO_DIR (default /content/DPVO).
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <dataset: tum|ucu> <seq>" >&2
  exit 2
fi
dataset="$1"
seq="$2"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

case "$dataset" in
  tum) data_dir="$root/data/tum/$seq"; calib="configs/dpvo/calib_tum_fr1.txt" ;;
  ucu) data_dir="$root/data/ucu_tum/$seq"; calib="configs/dpvo/calib_ucu.txt" ;;
  *) echo "Unknown dataset '$dataset' (expected tum or ucu)" >&2; exit 2 ;;
esac

if [ ! -f "$data_dir/rgb.txt" ]; then
  echo "Missing $data_dir/rgb.txt (see CONVENTIONS.md section 3)" >&2
  exit 1
fi

cd "$root"
exec python3 scripts/dpvo/run_dpvo.py \
  --dataset "$dataset" --seq "$seq" \
  --data-dir "$data_dir" --calib "$calib" \
  --dpvo-dir "${DPVO_DIR:-/content/DPVO}"
