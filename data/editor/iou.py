import json, re, sys

gt = json.load(open("/Users/feiyuchang/Desktop/Development/majiang_calculator/data/boxes.json"))
pred = {}
for line in open(sys.argv[1]):
    m = re.match(r"EVAL (\S+) ([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+)", line.strip())
    if m:
        n, *v = m.groups()
        pred[n] = dict(zip("xywh", map(float, v)))
    elif re.match(r"EVAL (\S+) nil", line.strip()):
        pred[re.match(r"EVAL (\S+)", line.strip()).group(1)] = None

def area(b): return b["w"] * b["h"]
def inter(a, b):
    x1, y1 = max(a["x"], b["x"]), max(a["y"], b["y"])
    x2 = min(a["x"] + a["w"], b["x"] + b["w"])
    y2 = min(a["y"] + a["h"], b["y"] + b["h"])
    return max(0, x2 - x1) * max(0, y2 - y1)

print(f"{'#':<4}{'IoU':>7}{'覆盖GT':>9}{'多框':>8}   预测 (x,y,w,h)")
print("-" * 66)
ious = []
for n in sorted(gt):
    g, p = gt[n], pred.get(n)
    if p is None:
        print(f"{n:<4}{'nil':>7}{'—':>9}{'—':>8}   没给框（退回手动）")
        ious.append(0.0); continue
    i = inter(g, p)
    iou = i / (area(g) + area(p) - i)
    recall = i / area(g)                 # ground truth 有多少被框住
    excess = (area(p) - i) / area(g)     # 多框进来的面积，按 GT 面积的倍数计
    ious.append(iou)
    print(f"{n:<4}{iou:>7.3f}{recall:>9.3f}{excess:>8.2f}x   "
          f"({p['x']:.3f}, {p['y']:.3f}, {p['w']:.3f}, {p['h']:.3f})")
print("-" * 66)
print(f"平均 IoU = {sum(ious)/len(ious):.3f}   "
      f"IoU≥0.7 的张数 = {sum(1 for v in ious if v >= 0.7)}/{len(ious)}")
