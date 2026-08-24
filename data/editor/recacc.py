import json, re, sys
from collections import Counter
gt = json.load(open("/Users/feiyuchang/Desktop/Development/majiang_calculator/data/labels.json"))
KIND_N = {"碰":3, "明杠":4, "暗杠":4, "杠":4}

rec = {}
for line in open(sys.argv[1]):
    m = re.match(r"REC (\S+) hand=\[(.*?)\] melds=\[(.*?)\]$", line.strip())
    if not m: continue
    n, h, ml = m.groups()
    melds = []
    for tok in ml.split():
        k, c = tok.split(":"); melds.append([k, c])
    rec[n] = {"hand": h.split() if h else [], "melds": melds}

def all_tiles(o):
    c = Counter(o["hand"])
    for k, t in o["melds"]: c[t] += KIND_N[k]
    return c
def meld_key(ms):   # 明暗未定的「杠」与明杠/暗杠都算相符
    return sorted(("K" if k.endswith("杠") else "P", t) for k, t in ms)

print(f"{'#':<4}{'牌面':>6}{'分组':>6}  说明")
print("-"*74)
tile_ok = group_ok = 0
for n in sorted(gt):
    g, r = gt[n], rec.get(n)
    if r is None:
        print(f"{n:<4}{'—':>6}{'—':>6}  无输出"); continue
    tg, tr = all_tiles(g), all_tiles(r)
    t_ok = tg == tr
    g_ok = t_ok and Counter(g["hand"]) == Counter(r["hand"]) and meld_key(g["melds"]) == meld_key(r["melds"])
    tile_ok += t_ok; group_ok += g_ok
    note = ""
    if not t_ok:
        extra = tr - tg; miss = tg - tr
        note = "多:" + " ".join(f"{k}x{v}" for k,v in sorted(extra.items())) if extra else ""
        if miss: note += ("  " if note else "") + "少:" + " ".join(f"{k}x{v}" for k,v in sorted(miss.items()))
    elif not g_ok:
        note = f"牌全对，但分组错（应 {len(g['melds'])} 组副露，实得 {len(r['melds'])} 组）"
    else:
        note = "完全正确"
    print(f"{n:<4}{'✓' if t_ok else '✗':>6}{'✓' if g_ok else '✗':>6}  {note}")
print("-"*74)
print(f"牌面全对 {tile_ok}/12    牌面+分组全对 {group_ok}/12")
