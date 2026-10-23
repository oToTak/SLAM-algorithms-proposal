import os
import sys
from pathlib import Path

def to_ns(ts: str) -> int:
    sec, _, frac = ts.partition(".")
    return int(sec) * 1_000_000_000 + int((frac + "000000000")[:9])

def rows(path: Path):
    for line in path.read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            yield line.split()

def main(src: Path, dst: Path) -> None:
    cam = dst / "mav0" / "cam0" / "data"
    imu = dst / "mav0" / "imu0"
    cam.mkdir(parents=True, exist_ok=True)
    imu.mkdir(parents=True, exist_ok=True)

    times = []
    for ts, rel in rows(src / "rgb.txt"):
        ns = to_ns(ts)
        link = cam / f"{ns}.png"
        if not link.exists():
            os.symlink((src / rel).resolve(), link)
        times.append(ns)
    (dst / "times.txt").write_text("\n".join(map(str, times)) + "\n")

    with open(imu / "data.csv", "w") as f:
        f.write("#timestamp [ns],w_x,w_y,w_z,a_x,a_y,a_z\n")
        n = 0
        for ts, ax, ay, az, gx, gy, gz in rows(src / "imu.txt"):
            f.write(f"{to_ns(ts)},{gx},{gy},{gz},{ax},{ay},{az}\n")
            n += 1
    print(f"{len(times)} images, {n} IMU samples -> {dst}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: python scripts/tum_to_euroc.py <exported_seq_dir> <out_dir>")
    main(Path(sys.argv[1]), Path(sys.argv[2]))