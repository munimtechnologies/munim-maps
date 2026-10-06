"""Builds example/routes.json: lanes for the demo traffic.

The centrelines come from Apple Maps (MKDirections, saved by a small Swift
script), so the cars follow the roads MapKit draws. Each route is trimmed
to the part that stays on its street, then moved to the right-hand lane.
Usage: python3 build-routes.py <requests.txt> <routes.json> [...pairs]
(requests.txt lines: "name lat1 lon1 lat2 lon2", the endpoints asked for)
"""
import json, math, sys

def to_xy(p, lat0):
    return ((p[1]) * 111320 * math.cos(math.radians(lat0)), p[0] * 111320)

def to_ll(x, y, lat0):
    return [round(y / 111320, 7), round(x / (111320 * math.cos(math.radians(lat0))), 7)]

def trim(points, lat0, start, end, tol=70):
    """Longest run of points within `tol` metres of the requested line."""
    xy = [to_xy(p, lat0) for p in points]
    a, b = to_xy(start, lat0), to_xy(end, lat0)
    # The requested line: first point to the furthest point along it.
    def off(p):
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dy) or 1
        return abs((p[0] - a[0]) * dy - (p[1] - a[1]) * dx) / L
    def length(run):
        return sum(math.dist(run[i], run[i + 1]) for i in range(len(run) - 1))
    best, run = [], []
    for p in xy:
        if off(p) <= tol:
            run.append(p)
        else:
            if length(run) > length(best): best = run
            run = []
    if length(run) > length(best): best = run
    return best

def offset(xy, d):
    out = []
    for i, p in enumerate(xy):
        a = xy[max(0, i - 1)]; b = xy[min(len(xy) - 1, i + 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dy) or 1
        out.append((p[0] + dy / L * d, p[1] - dx / L * d))
    return out

OFFSETS = {'michigan-s': -4.5, 'columbus': 4.5, 'michigan': 2.0, 'monroe': 4.0, 'randolph': 3.5, 'ggb': 2.4, 'lsd': 6.0}
lanes = []
seen = set()
requests = {}
pairs = list(zip(sys.argv[1::2], sys.argv[2::2]))
for txt, _ in pairs:
    for line in open(txt):
        f = line.split()
        if len(f) == 5:
            requests[f[0]] = ([float(f[1]), float(f[2])], [float(f[3]), float(f[4])])
for _, path in pairs[::-1]:
    for r in json.load(open(path))['routes'][::-1]:
        name = r['name']
        if name in seen:
            continue
        seen.add(name)
        lat0 = r['points'][0][0]
        start, end = requests[name]
        if name.startswith('ggb'):
            # The bridge span itself, tower approach to tower approach.
            span = [p for p in r['points'] if 37.8085 <= p[0] <= 37.8305 and p[1] <= -122.4740]
            xy = [to_xy(p, lat0) for p in span]
        else:
            xy = trim(r['points'], lat0, start, end)
        length = sum(math.dist(xy[i], xy[i + 1]) for i in range(len(xy) - 1))
        if length < 400:
            continue
        d = OFFSETS.get(name, OFFSETS.get(name.split('-')[0], 2.5))
        if name.startswith('ggb'):
            # Apple's two lines don't share a centreline on the bridge;
            # measured against the deck from straight above, these put each
            # direction in the middle of its carriageway.
            shift, d = {'ggb-n': (-4.2, 2.4), 'ggb-s': (5.0, 5.9)}[name]
            xy = [(x + shift, y) for x, y in xy]
        lanes.append({'name': name, 'length': round(length), 'points': [to_ll(x, y, lat0) for x, y in offset(xy, d)]})
json.dump({'lanes': lanes}, open('routes.json', 'w'), separators=(',', ':'))
for l in lanes:
    print(l['name'], l['length'])
