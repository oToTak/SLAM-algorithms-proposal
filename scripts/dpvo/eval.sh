#!/usr/bin/env bash
# Evaluate one DPVO run: ATE (+RPE for TUM), N/M, coverage, xy plot.
# Usage: scripts/dpvo/eval.sh <tum|ucu> <seq> [run]     (run defaults to latest traj_run<N>)
# Env: ROOT overrides the repo root (used for tests); VENV overrides ~/venvs/slam.
set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "usage: $0 <tum|ucu> <seq> [run]" >&2
  exit 2
fi
dataset=$1
seq=$2
run=${3:-}

here=$(cd "$(dirname "$0")" && pwd)
root=${ROOT:-$(cd "$here/../.." && pwd)}
venv=${VENV:-$HOME/venvs/slam}
bindir="$venv/bin"
[ -d "$venv/Scripts" ] && bindir="$venv/Scripts"   # Windows venv layout
[ -x "$bindir/evo_ape" ] || [ -x "$bindir/evo_ape.exe" ] \
  || { echo "evo not found in $venv (see CONVENTIONS.md section 5)" >&2; exit 1; }
export PATH="$bindir:$PATH"
export MPLBACKEND=Agg

case "$dataset" in
  tum) data_dir="$root/data/tum/$seq" ;;
  ucu) data_dir="$root/data/ucu_tum/$seq" ;;
  *) echo "dataset must be tum or ucu" >&2; exit 2 ;;
esac
res_dir="$root/results/dpvo/mono/$dataset/$seq"
gt="$data_dir/groundtruth.txt"
rgb="$data_dir/rgb.txt"

if [ -z "$run" ]; then
  run=$(ls "$res_dir" 2>/dev/null | sed -n 's/^traj_run\([0-9][0-9]*\)\.txt$/\1/p' | sort -n | tail -1)
  [ -n "$run" ] || { echo "no traj_run<N>.txt in $res_dir" >&2; exit 1; }
fi
traj="$res_dir/traj_run$run.txt"
for f in "$gt" "$rgb" "$traj"; do [ -f "$f" ] || { echo "missing: $f" >&2; exit 1; }; done
echo "== dpvo mono $dataset/$seq run$run =="

ape_log=$(evo_ape tum "$gt" "$traj" -as --t_max_diff 0.02 -v --no_warnings \
  --save_results "$res_dir/ape_run$run.zip" 2>&1) || { echo "$ape_log" >&2; exit 1; }
echo "$ape_log" | grep -E "Found|rmse|mean|median|std|max|min" || true
nm=$(echo "$ape_log" | sed -n 's/.*Found \([0-9]*\) of max\. \([0-9]*\) possible.*/\1 \2/p' | head -1)
[ -n "$nm" ] || { echo "could not parse N/M from evo output" >&2; exit 1; }
echo "Matched timestamps N/M: ${nm% *}/${nm#* }"

if [ "$dataset" = tum ]; then
  evo_rpe tum "$gt" "$traj" -as --t_max_diff 0.02 --delta 1 --delta_unit f --no_warnings \
    --save_results "$res_dir/rpe_run$run.zip" 2>&1 | grep -E "rmse|mean|median|std|max|min" \
    | sed 's/^/RPE /' || true
fi

evo_traj tum "$traj" --ref "$gt" -as --t_max_diff 0.02 --plot_mode xy --no_warnings \
  --save_plot "$res_dir/traj_xy.pdf" >/dev/null 2>&1 \
  || { echo "evo_traj failed" >&2; exit 1; }
echo "Plot: $res_dir/traj_xy.pdf"

python "$here/update_meta.py" "$res_dir/meta.yaml" "$traj" "$rgb" "${nm% *}" "${nm#* }"
