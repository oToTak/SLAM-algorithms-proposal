"""Update coverage (and N/M note) in meta.yaml for one evaluated run."""
import re
import sys
from pathlib import Path


def t_span(path):
    ts = []
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            ts.append(float(line.split()[0]))
    if len(ts) < 2:
        raise SystemExit(f"{path}: fewer than 2 timestamps")
    return min(ts), max(ts)


def main():
    meta, traj, rgb, n, m = sys.argv[1:6]
    n, m = int(n), int(m)
    a0, a1 = t_span(traj)
    b0, b1 = t_span(rgb)
    coverage = (a1 - a0) / (b1 - b0)
    text = Path(meta).read_text() if Path(meta).exists() else ""
    cov = f"coverage: {coverage:.2f}"
    if re.search(r"^coverage:.*$", text, re.M):
        text = re.sub(r"^coverage:.*$", cov, text, flags=re.M)
    else:
        text = text.rstrip("\n") + f"\n{cov}\n" if text else cov + "\n"

    note = f"ATE matched {n}/{m} timestamps"
    mnote = re.search(r"^notes:[ \t]*(.*)$", text, re.M)
    old = mnote.group(1).strip() if mnote else ""
    quote = old[:1] if old[:1] in "\"'" else ""
    old = old.strip("\"'")
    old = re.sub(r"\s*ATE matched \d+/\d+ timestamps;?", "", old).strip()
    if n < 0.9 * m:
        old = f"{old} {note}".strip()
    line = f'notes: "{old}"'
    if mnote:
        text = text[:mnote.start()] + line + text[mnote.end():]
    else:
        text = text.rstrip("\n") + "\n" + line + "\n"
    Path(meta).write_text(text)
    print(f"coverage={coverage:.2f}; N/M={n}/{m}" + (" (<0.9, noted in meta.yaml)" if n < 0.9 * m else ""))


main()
