#!/bin/bash
#
# 运行川麻算番断言（Tests/ScoringTests.swift）。
# 把算法/算番源码与测试拼成一个独立 Swift 文件后用 `swift` 直接跑，
# 不依赖 XCTest / 模拟器，也不把测试代码带进 App 编译目标。
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/majiang calculator"
TMP="$(mktemp -d)"
OUT="$TMP/combined.swift"

# 1) 纯逻辑源码（MahjongScoring 去掉 @MainActor 的 RuleSettingsStore 与 Combine 依赖）
cat "$SRC/MahjongCard.swift" "$SRC/Meld.swift" "$SRC/MahjongCalculator.swift" "$SRC/TileGrouping.swift" > "$OUT"

python3 - "$SRC/MahjongScoring.swift" "$OUT" << 'PY'
import sys
src = open(sys.argv[1]).read()
start = src.index("@MainActor\nfinal class RuleSettingsStore")
depth, j = 0, src.index("{", start)
while True:
    if src[j] == "{": depth += 1
    elif src[j] == "}":
        depth -= 1
        if depth == 0: break
    j += 1
src = (src[:start] + src[j+1:]).replace("import Combine\n", "")
open(sys.argv[2], "a").write(src)
PY

# 2) 测试
cat "$ROOT/Tests/ScoringTests.swift" "$ROOT/Tests/GroupingTests.swift" \
    "$ROOT/Tests/DiscardEvalTests.swift" >> "$OUT"

swift "$OUT"
