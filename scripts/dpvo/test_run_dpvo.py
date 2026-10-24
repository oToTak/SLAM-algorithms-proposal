"""CPU-only checks of the pure helpers in run_dpvo.py (synthetic poses). Run: python test_run_dpvo.py"""
import math
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import run_dpvo as r


def test_all():
    with tempfile.TemporaryDirectory() as d:
        d = Path(d)
        # fake TUM-style rgb.txt with header, unix-like timestamps
        t0 = 1305031102.175304
        ts = [t0 + i / 30 for i in range(300)]
        (d / "rgb.txt").write_text("# header\n# x\n" + "".join(f"{t:.6f} rgb/{t:.6f}.png\n" for t in ts))
        frames = r.read_rgb_txt(d / "rgb.txt")
        assert len(frames) == 300 and abs(frames[0][0] - t0) < 1e-6
        assert frames[0][1] == d / f"rgb/{t0:.6f}.png"

        poses = [(0.01 * i, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0) for i in range(300)]
        out = d / "res"
        # full run
        run, p = r.write_outputs(out, dataset="tum", seq="fr1_xyz", config="configs/dpvo/calib_tum_fr1.txt",
                                 commit="abc", rgb_tstamps=[t for t, _ in frames], tstamps=ts, poses=poses)
        assert run == 1 and p.name == "traj_run1.txt"
        lines = p.read_text().splitlines()
        assert len(lines) == 300 and not lines[0].startswith("#")
        f = lines[0].split()
        assert len(f) == 8 and len(f[0].split(".")[1]) == 9 and abs(float(f[0]) - t0) < 1e-6
        # second run does not overwrite; partial coverage ~0.5
        half = 150
        run2, p2 = r.write_outputs(out, dataset="tum", seq="fr1_xyz", config="c", commit="abc",
                                   rgb_tstamps=ts, tstamps=ts[:half], poses=poses[:half], notes='a "q"')
        assert run2 == 2 and p.exists() and p2.name == "traj_run2.txt"
        meta = (out / "meta.yaml").read_text()
        try:
            import yaml
            m = yaml.safe_load(meta)
            assert m["run"] == 2 and m["tracking_lost"] is False and m["notes"] == 'a "q"'
            assert m["method"] == "dpvo" and m["mode"] == "mono" and m["dataset"] == "tum"
            assert abs(m["coverage"] - 0.5) < 0.01
        except ImportError:
            assert "coverage: 0.50" in meta
        # tracking lost: no traj file, meta says so
        run3, p3 = r.write_outputs(out, dataset="tum", seq="fr1_xyz", config="c", commit="abc",
                                   rgb_tstamps=ts, tstamps=[], poses=[], tracking_lost=True)
        assert run3 == 3 and p3 is None and not (out / "traj_run3.txt").exists()
        assert "tracking_lost: true" in (out / "meta.yaml").read_text()
        # NaN poses are treated as lost
        _, p4 = r.write_outputs(out, dataset="tum", seq="fr1_xyz", config="c", commit="abc",
                                rgb_tstamps=ts, tstamps=ts[:2], poses=[(math.nan,) * 7] * 2)
        assert p4 is None
    assert r.compute_coverage([1, 3], [0, 4]) == 0.5
    assert r.compute_coverage([], [0, 4]) == 0.0
    c = r.read_calib(r.REPO_ROOT / "configs/dpvo/calib_ucu.txt")
    assert len(c) == 8
    assert len(r.read_calib(r.REPO_ROOT / "configs/dpvo/calib_tum_fr1.txt")) == 9
    r.check_tstamps([1.7e9 + 0.1], [1.7e9 + 0.1])
    r.check_tstamps([1, 2], [1, 2, 3])  # length mismatch (interpolated/shorter): not checked
    try:
        r.check_tstamps([1.7e9 + 128.0], [1.7e9])
        raise SystemExit("guard did not fire")
    except RuntimeError:
        pass
    print("OK")


if __name__ == "__main__":
    test_all()
