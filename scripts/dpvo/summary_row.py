#!/usr/bin/env python3
"""Print one results/summary.csv row (CONVENTIONS.md section 6) for an evaluated DPVO run.

Usage: scripts/dpvo/summary_row.py <tum|ucu> <seq> [run] [--header] [--root DIR]

Reads meta.yaml (run, coverage, tracking_lost, commit) and the evo result zips written by
eval.sh (ape_run<N>.zip -> ate_rmse_m, rpe_run<N>.zip -> rpe_trans_m, TUM only).
Stdlib only. meta.yaml describes the latest run, so an older run number is refused.
"""
import argparse
import json
import re
import sys
import zipfile
from pathlib import Path

HEADER = "method,mode,dataset,seq,run,ate_rmse_m,rpe_trans_m,coverage,tracking_lost,commit"


def read_meta(path):
    meta = {}
    for line in Path(path).read_text().splitlines():
        m = re.match(r"^([a-z_]+):[ \t]*(.*)$", line)
        if m:
            meta[m.group(1)] = m.group(2).strip().strip("\"'")
    return meta


def rmse_from_zip(path):
    with zipfile.ZipFile(path) as z:
        return json.loads(z.read("stats.json"))["rmse"]


def build_row(res_dir, dataset, seq, run=None):
    res_dir = Path(res_dir)
    meta = read_meta(res_dir / "meta.yaml")
    meta_run = int(meta["run"])
    run = meta_run if run is None else run
    if run != meta_run:
        raise SystemExit(f"meta.yaml describes run {meta_run}, not run {run} "
                         "(older runs keep their rows in summary.csv)")
    lost = meta["tracking_lost"] == "true"
    ate = rpe = ""
    if not lost:
        ape_zip = res_dir / f"ape_run{run}.zip"
        if not ape_zip.exists():
            raise SystemExit(f"missing {ape_zip}: run scripts/dpvo/eval.sh {dataset} {seq} {run} first")
        ate = f"{rmse_from_zip(ape_zip):.3f}"
        rpe_zip = res_dir / f"rpe_run{run}.zip"
        if dataset == "tum":  # UCU: RPE is not computed (CONVENTIONS section 5)
            if not rpe_zip.exists():
                raise SystemExit(f"missing {rpe_zip}: run scripts/dpvo/eval.sh {dataset} {seq} {run} first")
            rpe = f"{rmse_from_zip(rpe_zip):.3f}"
    fields = [meta["method"], meta["mode"], dataset, seq, str(run), ate, rpe,
              meta["coverage"], meta["tracking_lost"], meta["commit"][:7]]
    return ",".join(fields)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("dataset", choices=["tum", "ucu"])
    ap.add_argument("seq")
    ap.add_argument("run", nargs="?", type=int)
    ap.add_argument("--header", action="store_true", help="print the CSV header line first")
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = ap.parse_args()
    res_dir = args.root / "results" / "dpvo" / "mono" / args.dataset / args.seq
    row = build_row(res_dir, args.dataset, args.seq, args.run)
    if args.header:
        print(HEADER)
    print(row)


if __name__ == "__main__":
    sys.exit(main())
