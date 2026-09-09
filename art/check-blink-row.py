#!/usr/bin/env python3
"""Check a generated blink row against the row it is supposed to be a blink of.

An image tool asked to close the pet's eyes will sometimes edit the file it was
given and sometimes quietly redraw the character. The second looks fine on its
own and is useless: cut against the original at speed, the fur and the outline
move and he changes shape every time he blinks.

This normalises whatever came back onto the 192x208 cell grid and then measures
what actually changed. Usage:

    python3 art/check-blink-row.py <generated.png> <source-row> [out-dir]

where <source-row> is 9 or 10. Needs ffmpeg on PATH.
"""
import os, subprocess, sys, tempfile

CELL_W, CELL_H, COLUMNS = 192, 208, 8
ROW_W = CELL_W * COLUMNS
SHEET = "Sources/MikkelPet/Resources/spritesheet.png"


def raw(path, out, size=None):
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", path,
           "-f", "rawvideo", "-pix_fmt", "rgba", out]
    subprocess.run(cmd, check=True)
    return open(out, "rb").read()


def dimensions(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x", path],
        capture_output=True, text=True, check=True).stdout.strip()
    return tuple(int(v) for v in out.split("x"))


def bbox(buf, w, h, x0, x1, thresh=40):
    minx, miny, maxx, maxy = 10**9, 10**9, -1, -1
    for y in range(h):
        base = y * w
        for x in range(x0, x1):
            if buf[(base + x) * 4 + 3] > thresh:
                minx = min(minx, x); maxx = max(maxx, x)
                miny = min(miny, y); maxy = max(maxy, y)
    return minx, miny, maxx, maxy


def characters(buf, w, h, thresh=40, gap=20):
    cols = []
    for x in range(w):
        hit = any(buf[(y * w + x) * 4 + 3] > thresh for y in range(0, h, 2))
        cols.append(hit)
    runs, start = [], None
    for x, v in enumerate(cols):
        if v and start is None:
            start = x
        elif not v and start is not None:
            if x - start > gap:
                runs.append((start, x))
            start = None
    if start is not None:
        runs.append((start, w))
    return runs


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    generated, row = sys.argv[1], int(sys.argv[2])
    out_dir = sys.argv[3] if len(sys.argv) > 3 else tempfile.mkdtemp()
    os.makedirs(out_dir, exist_ok=True)

    src_png = os.path.join(out_dir, f"source-row{row}.png")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", SHEET,
                    "-vf", f"crop={ROW_W}:{CELL_H}:0:{row * CELL_H}", src_png], check=True)
    src = raw(src_png, os.path.join(out_dir, "source.raw"))

    gw, gh = dimensions(generated)
    edited_in_place = (gw, gh) == (ROW_W, CELL_H)
    print(f"returned {gw}x{gh}" + ("  (edited in place)" if edited_in_place
                                   else "  (redrawn: a new canvas, so expect drift)"))

    gen = raw(generated, os.path.join(out_dir, "generated.raw"))
    runs = characters(gen, gw, gh)
    if len(runs) != COLUMNS:
        print(f"found {len(runs)} characters, expected {COLUMNS}: cannot line them up")
        return 1

    # Rescale each character so its height matches the source cell's, then plant
    # it on the source's baseline and centre. Anything more than this is fitting
    # the result to the answer.
    cells = []
    for i in range(COLUMNS):
        s = bbox(src, ROW_W, CELL_H, i * CELL_W, (i + 1) * CELL_W)
        sw, sh = s[2] - s[0] + 1, s[3] - s[1] + 1
        g = bbox(gen, gw, gh, runs[i][0], runs[i][1])
        rw, rh = g[2] - g[0] + 1, g[3] - g[1] + 1
        tw = max(1, round(rw * (sh / rh)))
        x_off = round((s[0] + s[2]) / 2 - tw / 2) - i * CELL_W
        cell = os.path.join(out_dir, f"cell{i}.png")
        subprocess.run([
            "ffmpeg", "-y", "-loglevel", "error", "-i", generated, "-filter_complex",
            f"color=black@0:s={CELL_W}x{CELL_H},format=rgba[bg];"
            f"[0:v]crop={rw}:{rh}:{g[0]}:{g[1]},scale={tw}:{sh}:flags=lanczos[c];"
            f"[bg][c]overlay={x_off}:{s[1]}", "-frames:v", "1", cell], check=True)
        cells.append(cell)

    normalized = os.path.join(out_dir, "normalized.png")
    args = ["ffmpeg", "-y", "-loglevel", "error"]
    for c in cells:
        args += ["-i", c]
    args += ["-filter_complex", "".join(f"[{i}:v]" for i in range(COLUMNS)) +
             f"hstack=inputs={COLUMNS}", "-frames:v", "1", normalized]
    subprocess.run(args, check=True)
    norm = raw(normalized, os.path.join(out_dir, "normalized.raw"))

    print(f"\n{'cell':>4} {'silhouette moved':>17} {'colour changed':>15}")
    print("-" * 40)
    worst = 0.0
    for c in range(COLUMNS):
        x0 = c * CELL_W
        sil = body = total = counted = 0
        for y in range(CELL_H):
            for x in range(x0, x0 + CELL_W):
                i = (y * ROW_W + x) * 4
                a_on, b_on = src[i + 3] > 40, norm[i + 3] > 40
                body += a_on
                sil += a_on != b_on
                if a_on and b_on:
                    total += (abs(src[i] - norm[i]) + abs(src[i + 1] - norm[i + 1])
                              + abs(src[i + 2] - norm[i + 2]))
                    counted += 1
        pct = 100 * sil / max(body, 1)
        worst = max(worst, pct)
        print(f"{c:>4} {pct:>16.1f}% {total / max(counted, 1):>15.1f}")

    compare = os.path.join(out_dir, "compare.png")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", src_png, "-i", normalized,
                    "-filter_complex", "[0:v][1:v]vstack,scale=1400:-1", compare], check=True)

    print(f"\nworst silhouette change: {worst:.1f}%")
    print("a real edit scores 0.0%; anything past about 1% will visibly pop")
    print(f"\nnormalized row: {normalized}\ncomparison:     {compare}")
    return 0 if worst < 1.0 else 1


if __name__ == "__main__":
    sys.exit(main())
