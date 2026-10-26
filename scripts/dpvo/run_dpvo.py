#!/usr/bin/env python3
"""Run mono DPVO on a TUM-format sequence and write CONVENTIONS.md section 4 outputs.

Pure helpers (rgb.txt parsing, trajectory/meta writing, coverage, run numbering) need
no torch/dpvo and are unit-tested on a CPU-only machine. DPVO is imported lazily in
``run_slam`` and is never modified.
"""
import argparse
import json
import math
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
METHOD, MODE = "dpvo", "mono"
# (top/bottom, left/right) crop in pixels after undistortion, as in DPVO evaluate_tum.py
CROP_AFTER_UNDISTORT = {"tum": (8, 16)}


# ---------------------------------------------------------------- pure helpers

def read_rgb_txt(path):
    """Parse TUM rgb.txt -> list of (timestamp_seconds, image_path). Skips '#' and blank lines."""
    path = Path(path)
    frames = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        ts, rel = line.split()[:2]
        frames.append((float(ts), path.parent / rel))
    return frames


def read_calib(path):
    """Single-line calib file: fx fy cx cy [k1 k2 p1 p2 ...]."""
    vals = [float(v) for v in Path(path).read_text().split()]
    if len(vals) < 4:
        raise ValueError(f"{path}: expected at least 4 numbers, got {len(vals)}")
    return vals


def format_tum_line(t, pose):
    """pose = (x, y, z, qx, qy, qz, qw) as returned by DPVO.terminate()."""
    return f"{t:.9f} " + " ".join(f"{v:.9f}" for v in pose)


def write_tum_trajectory(path, tstamps, poses):
    """TUM: 'timestamp tx ty tz qx qy qz qw', spaces, no header."""
    if len(tstamps) != len(poses):
        raise ValueError("tstamps and poses differ in length")
    with open(path, "w") as f:
        for t, p in zip(tstamps, poses):
            f.write(format_tum_line(float(t), [float(v) for v in p]) + "\n")


def compute_coverage(traj_tstamps, rgb_tstamps):
    """(t_last - t_first of trajectory) / (t_last - t_first of rgb.txt), CONVENTIONS section 5."""
    if len(traj_tstamps) < 2 or len(rgb_tstamps) < 2:
        return 0.0
    span = max(rgb_tstamps) - min(rgb_tstamps)
    if span <= 0:
        return 0.0
    cov = (max(traj_tstamps) - min(traj_tstamps)) / span
    return max(0.0, min(1.0, cov))


def next_run_number(out_dir):
    """Next free N for traj_run<N>.txt; existing runs are never overwritten."""
    out_dir = Path(out_dir)
    nums = [int(m.group(1)) for p in out_dir.glob("traj_run*.txt")
            if (m := re.fullmatch(r"traj_run(\d+)\.txt", p.name))]
    return max(nums, default=0) + 1


def check_tstamps(tstamps, rgb_tstamps, tol=1e-6):
    """Guard: DPVO must return the exact timestamps we passed (one pose per frame)."""
    if len(tstamps) == len(rgb_tstamps):
        err = max((abs(float(a) - float(b)) for a, b in zip(tstamps, rgb_tstamps)), default=0.0)
        if err >= tol:
            raise RuntimeError(f"DPVO timestamps differ from rgb.txt (max abs diff {err:.3g} s >= {tol}); "
                               "refusing to write a trajectory with wrong time")


def poses_are_valid(poses):
    return len(poses) >= 2 and all(math.isfinite(float(v)) for p in poses for v in p)


def format_meta(*, dataset, seq, run, commit, config, coverage, tracking_lost, notes):
    """meta.yaml text per CONVENTIONS section 4 (hand-written: no PyYAML needed in Colab)."""
    return (
        f"method: {METHOD}\n"
        f"mode: {MODE}\n"
        f"dataset: {dataset}\n"
        f"seq: {seq}\n"
        f"run: {run}\n"
        f"commit: {commit}\n"
        f"config: {config}\n"
        f"coverage: {coverage:.2f}\n"
        f"tracking_lost: {'true' if tracking_lost else 'false'}\n"
        f"notes: {json.dumps(notes, ensure_ascii=False)}\n"
    )


def write_outputs(out_dir, *, dataset, seq, config, commit, rgb_tstamps, tstamps, poses,
                  tracking_lost=False, notes=""):
    """Write traj_run<N>.txt (unless tracking lost) and meta.yaml. Returns (run, traj_path or None)."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    run = next_run_number(out_dir)
    if not tracking_lost and not poses_are_valid(poses):
        tracking_lost = True
        notes = (notes + " " if notes else "") + "invalid or empty pose output."
    traj_path = None
    coverage = 0.0
    if not tracking_lost:
        traj_path = out_dir / f"traj_run{run}.txt"
        write_tum_trajectory(traj_path, tstamps, poses)
        coverage = compute_coverage(tstamps, rgb_tstamps)
    (out_dir / "meta.yaml").write_text(format_meta(
        dataset=dataset, seq=seq, run=run, commit=commit, config=config,
        coverage=coverage, tracking_lost=tracking_lost, notes=notes))
    return run, traj_path


def git_commit(repo=REPO_ROOT):
    try:
        sha = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"],
                                      text=True).strip()
        dirty = subprocess.check_output(["git", "-C", str(repo), "status", "--porcelain", "--untracked-files=no"],
                                        text=True).strip()
        return sha, bool(dirty)
    except Exception:
        return "unknown", False


def dpvo_env_note(dpvo_dir):
    """' torch X, DPVO sources patched (<shortstat>).' so meta.yaml shows how DPVO was built."""
    parts = []
    try:
        import torch
        parts.append(f"torch {torch.__version__}")
    except Exception:
        pass
    try:
        stat = subprocess.check_output(["git", "-C", str(dpvo_dir), "diff", "--shortstat"],
                                       text=True).strip()
        if stat:
            parts.append(f"DPVO sources patched for new torch ({stat})")
    except Exception:
        pass
    return f" {', '.join(parts)}." if parts else ""


# ---------------------------------------------------------------- GPU part

def frame_stream(frames, calib, dataset, stride=1):
    """Yield (timestamp, CHW BGR uint8 image, intrinsics[4]) with undistort/crop as in DPVO."""
    import cv2
    import numpy as np

    fx, fy, cx, cy = calib[:4]
    dist = np.array(calib[4:]) if len(calib) > 4 else None
    K = np.array([[fx, 0, cx], [0, fy, cy], [0, 0, 1]], dtype=np.float64)
    crop_v, crop_h = CROP_AFTER_UNDISTORT.get(dataset, (0, 0))

    for ts, imfile in frames[::stride]:
        image = cv2.imread(str(imfile))
        if image is None:
            raise FileNotFoundError(imfile)
        intr = np.array([fx, fy, cx, cy], dtype=np.float64)
        if dist is not None:
            image = cv2.undistort(image, K, dist)
        if crop_v or crop_h:
            h, w = image.shape[:2]
            image = image[crop_v:h - crop_v, crop_h:w - crop_h]
            intr[2] -= crop_h
            intr[3] -= crop_v
        h, w = image.shape[:2]
        image = image[:h - h % 16, :w - w % 16]  # DPVO needs multiples of 16
        yield ts, image.transpose(2, 0, 1), intr


def run_slam(frames, calib, dataset, dpvo_dir, network=None, stride=1):
    """Feed frames with their rgb.txt timestamps to DPVO; returns (poses Nx7, tstamps N)."""
    import numpy as np
    import torch

    sys.path.insert(0, str(dpvo_dir))  # fallback if not pip-installed
    from dpvo.config import cfg
    from dpvo.dpvo import DPVO

    cfg.merge_from_file(str(Path(dpvo_dir) / "config" / "default.yaml"))
    network = network or str(Path(dpvo_dir) / "dpvo.pth")
    torch.manual_seed(1234)
    slam = None
    with torch.no_grad():
        for ts, image, intr in frame_stream(frames, calib, dataset, stride):
            image = torch.as_tensor(image, device="cuda")
            intr = torch.as_tensor(intr, dtype=torch.float, device="cuda")
            if slam is None:
                slam = DPVO(cfg, network, ht=image.shape[-2], wd=image.shape[-1], viz=False)
            slam(ts, image, intr)
        poses, tstamps = slam.terminate()
    return np.asarray(poses), np.asarray(tstamps)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dataset", required=True, choices=["tum", "ucu"])
    ap.add_argument("--seq", required=True)
    ap.add_argument("--data-dir", required=True, type=Path)
    ap.add_argument("--calib", required=True, type=Path, help="calib file (repo-relative path is recorded in meta)")
    ap.add_argument("--dpvo-dir", type=Path, default=Path("/content/DPVO"))
    ap.add_argument("--network", default=None)
    ap.add_argument("--stride", type=int, default=1)
    ap.add_argument("--max-frames", type=int, default=0, help="debug/smoke test only: use first N frames")
    ap.add_argument("--results-root", type=Path, default=REPO_ROOT / "results")
    args = ap.parse_args()

    frames = read_rgb_txt(args.data_dir / "rgb.txt")
    if args.max_frames > 0:
        frames = frames[:args.max_frames]
    calib = read_calib(args.calib if args.calib.is_absolute() else REPO_ROOT / args.calib)
    rgb_ts = [t for t, _ in frames]
    out_dir = args.results_root / METHOD / MODE / args.dataset / args.seq
    sha, dirty = git_commit()
    config = str(args.calib)
    notes = f"DPVO 0ac95b6, config/default.yaml, stride={args.stride}, {len(frames)} frames."
    notes += dpvo_env_note(args.dpvo_dir)
    if args.max_frames > 0:
        notes += " TRUNCATED smoke run (--max-frames)."
    if dirty:
        notes += " Repo had uncommitted changes."

    try:
        poses, tstamps = run_slam(frames, calib, args.dataset, args.dpvo_dir,
                                  args.network, args.stride)
    except Exception as e:  # tracking failure / CUDA error: record it, never leave stale meta
        write_outputs(out_dir, dataset=args.dataset, seq=args.seq, config=config, commit=sha,
                      rgb_tstamps=rgb_ts, tstamps=[], poses=[], tracking_lost=True,
                      notes=f"{notes} Failed: {type(e).__name__}: {e}")
        raise
    check_tstamps(tstamps, [t for t, _ in frames[::args.stride]])
    run, traj = write_outputs(out_dir, dataset=args.dataset, seq=args.seq, config=config,
                              commit=sha, rgb_tstamps=rgb_ts, tstamps=tstamps, poses=poses,
                              notes=notes)
    print(f"Wrote {traj} ({len(poses)} poses) and {out_dir / 'meta.yaml'}")


if __name__ == "__main__":
    main()
