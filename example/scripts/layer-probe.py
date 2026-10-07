"""Measures MapModelLayer against another library's map on Android screenshots.

munimmapsexample://layer/<rnmapbox|rnmaps-google>/pan shows a probe: a
magenta circle drawn by the host map and a box drawn by munim-maps at the
same coordinate (#00B000, lit to about #69D246). Take raw
frames while the map is dragged (layer-pan.sh: `adb exec-out screencap`
during `adb shell input swipe …`) and this prints, per frame, the centre of
each (the middle of their pixels' bounding box, 1% outliers trimmed) and how
far apart they are.

    python3 layer-probe.py <density, e.g. 2.8125> frame.raw…
"""
import struct
import sys


def load(path):
    data = open(path, 'rb').read()
    w, h, _fmt = struct.unpack_from('<III', data, 0)
    # Android 8 and later: a 4-byte colour space follows the format.
    off = 16 if len(data) - 16 == w * h * 4 else 12
    return w, h, memoryview(data)[off:]


def bbox(px, w, test, x0, y0, x1, y1, reach):
    """Middle of the bounding box of the matching pixels within `reach` x
    sqrt(count) of their median (map icons of a similar colour elsewhere on
    the screen are left out), 0.5% outliers trimmed."""
    points = []
    for y in range(y0, y1):
        row = y * w * 4
        for x in range(x0, x1):
            i = row + x * 4
            if test(px[i], px[i + 1], px[i + 2]):
                points.append((x, y))
    if len(points) < 20:
        return None
    mx = sorted(p[0] for p in points)[len(points) // 2]
    my = sorted(p[1] for p in points)[len(points) // 2]
    limit = (reach * len(points) ** 0.5) ** 2
    near = [p for p in points if (p[0] - mx) ** 2 + (p[1] - my) ** 2 <= limit]
    xs = sorted(p[0] for p in near)
    ys = sorted(p[1] for p in near)
    k = max(1, len(xs) // 200)
    return ((xs[k] + xs[-k - 1]) / 2, (ys[k] + ys[-k - 1]) / 2, len(xs), xs[0], ys[0], xs[-1], ys[-1])


def magenta(r, g, b):
    return r > 200 and g < 90 and b > 200


def box(r, g, b):
    return r < 150 and b < 120 and g > 150 and g > r + 60 and g > b + 80


def main():
    density = float(sys.argv[1])
    worst = 0.0
    for path in sys.argv[2:]:
        w, h, px = load(path)
        m = bbox(px, w, magenta, 0, 0, w, h, 1.0)
        c = None
        if m:
            # The box is looked for around the circle only.
            pad = int(max(m[5] - m[3], m[6] - m[4]))
            c = bbox(px, w, box, max(0, m[3] - pad), max(0, m[4] - pad), min(w, m[5] + pad), min(h, m[6] + pad), 1.0)
        if not m or not c:
            print(f'{path}: circle={m and m[:3]} box={c and c[:3]} (not both on screen)')
            continue
        d = ((m[0] - c[0]) ** 2 + (m[1] - c[1]) ** 2) ** 0.5
        worst = max(worst, d)
        print(f'{path}: host ({m[0]:.1f}, {m[1]:.1f}) munim ({c[0]:.1f}, {c[1]:.1f}) '
              f'apart {d:.1f} px = {d / density:.2f} pt  [{m[2]} / {c[2]} px]')
    print(f'worst {worst:.1f} px = {worst / density:.2f} pt')


main()
