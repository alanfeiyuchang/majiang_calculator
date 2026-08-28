//
//  MCRCalculator.swift
//  majiang calculator
//
//  国标麻将（MCR / 中国麻将竞赛规则）的和牌、听牌、向听、进张、打牌建议。
//
//  牌张：34 种 —— 0–8 万、9–17 筒、18–26 条、27–30 东南西北、31–33 中发白，各 4 张。
//  花牌（春夏秋冬梅兰竹菊）不参与和牌，单独计分，不进 34 下标。
//
//  和牌牌型：
//  ① 标准型：4 面子 + 1 将（字牌只能成刻，不能成顺）
//  ② 七对：七个对子（4 张相同按两对计）
//  ③ 十三幺：十三种幺九牌各一张 + 其中任一张成对
//  ④ 全不靠：三门数牌分别取 147 / 258 / 369 中互不相同的一组，加字牌，14 张互不相同、无对子
//
//  四川的「缺一门 / 花猪」在国标下完全不适用，本文件不做任何花色数量限制。
//

import Foundation

// MARK: - 34 下标工具

let mcrTileKinds = 34

@inline(__always) func mcrIsHonor(_ i: Int) -> Bool { i >= 27 }
@inline(__always) func mcrIsWind(_ i: Int) -> Bool { i >= 27 && i <= 30 }
@inline(__always) func mcrIsDragon(_ i: Int) -> Bool { i >= 31 }
/// 0 万 / 1 筒 / 2 条 / 3 字牌
@inline(__always) func mcrSuitOf(_ i: Int) -> Int { i < 27 ? i / 9 : 3 }
/// 数牌 1–9；风 1–4（东南西北）；箭 1–3（中发白）
@inline(__always) func mcrRankOf(_ i: Int) -> Int { i < 27 ? i % 9 + 1 : (i < 31 ? i - 26 : i - 30) }
@inline(__always) func mcrIsTerminal(_ i: Int) -> Bool { i < 27 && (i % 9 == 0 || i % 9 == 8) }
@inline(__always) func mcrIsTerminalOrHonor(_ i: Int) -> Bool { mcrIsHonor(i) || mcrIsTerminal(i) }
/// 顺子起点合法（同花色数牌 1–7）
@inline(__always) func mcrCanStartChow(_ i: Int) -> Bool { i < 27 && i % 9 <= 6 }

/// 十三幺的十三种牌
let mcrThirteenOrphans: [Int] = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33]

// MARK: - 手牌 / 副露 → 频率数组

/// 手牌 → 长度 34 的频率数组（花牌被忽略）
func handToFrequency34(_ cards: [MahjongCard]) -> [Int] {
    var c = Array(repeating: 0, count: mcrTileKinds)
    for card in cards {
        let i = card.mcrIndex
        guard i >= 0 else { continue }
        c[i] += 1
    }
    return c
}

/// 副露占用的牌 → 长度 34 的频率数组
func meldsToFrequency34(_ melds: [Meld]) -> [Int] {
    var c = Array(repeating: 0, count: mcrTileKinds)
    for m in melds {
        for tile in m.tiles {
            let i = tile.mcrIndex
            guard i >= 0 else { continue }
            c[i] += 1
        }
    }
    return c
}

/// 手牌里的花牌（不参与和牌，单独计分）
func flowerCards(_ cards: [MahjongCard]) -> [MahjongCard] {
    cards.filter { $0.suit.isFlower }
}

// MARK: - 牌型：标准型

/// 剩余牌能否恰好拆成若干刻子/顺子（不含将）。字牌只能成刻。
private func mcrMeldsBacktrack(_ counts: inout [Int]) -> Bool {
    guard let j = counts.firstIndex(where: { $0 > 0 }) else { return true }

    if counts[j] >= 3 {
        counts[j] -= 3
        if mcrMeldsBacktrack(&counts) { counts[j] += 3; return true }
        counts[j] += 3
    }
    if mcrCanStartChow(j), counts[j + 1] > 0, counts[j + 2] > 0 {
        counts[j] -= 1; counts[j + 1] -= 1; counts[j + 2] -= 1
        if mcrMeldsBacktrack(&counts) {
            counts[j] += 1; counts[j + 1] += 1; counts[j + 2] += 1
            return true
        }
        counts[j] += 1; counts[j + 1] += 1; counts[j + 2] += 1
    }
    return false
}

/// 频率数组能否拆成「1 将 + (总数−2)/3 个面子」
func mcrIsStandardForm(_ freq: [Int]) -> Bool {
    var c = freq
    for i in 0..<mcrTileKinds where c[i] >= 2 {
        c[i] -= 2
        if mcrMeldsBacktrack(&c) { c[i] += 2; return true }
        c[i] += 2
    }
    return false
}

// MARK: - 牌型：七对 / 十三幺 / 全不靠

/// 14 张是否七对（4 张相同按两对计，与国标常见实现一致）
func mcrIsSevenPairs(_ freq: [Int]) -> Bool {
    freq.reduce(0, +) == 14 && freq.allSatisfy { $0 % 2 == 0 }
}

/// 连七对：同一花色 7 个连续点数各成对（如 1122334455667788 中的任意 7 连）
func mcrIsSevenShiftedPairs(_ freq: [Int]) -> Bool {
    guard mcrIsSevenPairs(freq) else { return false }
    for suit in 0..<3 {
        for start in 0...2 {
            let base = suit * 9 + start
            if (0..<7).allSatisfy({ freq[base + $0] == 2 }),
               freq.reduce(0, +) == 14,
               (0..<mcrTileKinds).allSatisfy({ i in
                   (i >= base && i < base + 7) ? freq[i] == 2 : freq[i] == 0
               }) {
                return true
            }
        }
    }
    return false
}

/// 十三幺：13 种幺九牌齐全，其中一种成对
func mcrIsThirteenOrphans(_ freq: [Int]) -> Bool {
    guard freq.reduce(0, +) == 14 else { return false }
    for i in 0..<mcrTileKinds where !mcrThirteenOrphans.contains(i) {
        if freq[i] > 0 { return false }
    }
    var pairs = 0
    for i in mcrThirteenOrphans {
        if freq[i] == 0 { return false }
        if freq[i] == 2 { pairs += 1 }
        if freq[i] > 2 { return false }
    }
    return pairs == 1
}

/// 组合龙的三组「隔三」牌：{1,4,7} {2,5,8} {3,6,9}（花色内偏移）
private let mcrKnittedOffsets: [[Int]] = [[0, 3, 6], [1, 4, 7], [2, 5, 8]]
/// 三门数牌分配给三组的 6 种排列
private let mcrSuitPermutations: [[Int]] = [
    [0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]
]

/// 一副「不靠」牌允许出现的牌集合（给定 花色→组 的分配）
private func mcrKnittedAllowed(_ assign: [Int]) -> Set<Int> {
    var s = Set(27..<34)
    for suit in 0..<3 {
        for off in mcrKnittedOffsets[assign[suit]] { s.insert(suit * 9 + off) }
    }
    return s
}

/// 全不靠：14 张互不相同，数牌按 147/258/369 分门取，其余为字牌
func mcrIsKnittedNoSets(_ freq: [Int]) -> Bool {
    guard freq.reduce(0, +) == 14, freq.allSatisfy({ $0 <= 1 }) else { return false }
    let present = Set((0..<mcrTileKinds).filter { freq[$0] > 0 })
    for perm in mcrSuitPermutations where present.isSubset(of: mcrKnittedAllowed(perm)) {
        return true
    }
    return false
}

/// 七星不靠：全不靠 且 七种字牌齐全
func mcrIsSevenStarsKnitted(_ freq: [Int]) -> Bool {
    mcrIsKnittedNoSets(freq) && (27..<34).allSatisfy { freq[$0] == 1 }
}

/// 手上是否含完整「组合龙」（147/258/369 分属三门，共 9 张）
func mcrHasKnittedStraight(_ freq: [Int]) -> Bool {
    for perm in mcrSuitPermutations {
        var ok = true
        for suit in 0..<3 {
            for off in mcrKnittedOffsets[perm[suit]] where freq[suit * 9 + off] == 0 {
                ok = false; break
            }
            if !ok { break }
        }
        if ok { return true }
    }
    return false
}

/// 组合龙牌型（非全不靠）：暗牌里含完整的 9 张组合龙，其余部分组成「1 将 + 剩下的面子」。
/// 组合龙的 9 张必须在手内，另一副面子可以是副露（最多 1 组）。
func mcrIsKnittedStraightForm(_ freq: [Int], meldCount: Int = 0) -> Bool {
    guard meldCount <= 1, freq.reduce(0, +) + 3 * meldCount == 14 else { return false }
    for perm in mcrSuitPermutations {
        var c = freq
        var ok = true
        for suit in 0..<3 {
            for off in mcrKnittedOffsets[perm[suit]] {
                let i = suit * 9 + off
                if c[i] == 0 { ok = false; break }
                c[i] -= 1
            }
            if !ok { break }
        }
        guard ok else { continue }
        // 剩 5 张（1 面子 + 将）或 2 张（只剩将，第 4 副是副露）
        if mcrIsStandardForm(c) { return true }
    }
    return false
}

// MARK: - 和牌判定

/// 暗牌（含所和那张）+ 副露 是否构成一副国标可和的牌型。
/// 特殊牌型（七对 / 十三幺 / 全不靠 / 组合龙型）要求门清且暗牌恰 14 张。
func mcrIsCompleteHand(_ freq: [Int], melds: [Meld] = []) -> Bool {
    guard freq.count == mcrTileKinds else { return false }
    let sum = freq.reduce(0, +)
    guard sum >= 2, sum % 3 == 2, sum + 3 * melds.count <= 14 else { return false }

    if melds.isEmpty, sum == 14 {
        if mcrIsSevenPairs(freq) { return true }
        if mcrIsThirteenOrphans(freq) { return true }
        if mcrIsKnittedNoSets(freq) { return true }
    }
    // 组合龙型：9 张组合龙在手，第 4 副面子可以是副露
    if melds.count <= 1, sum + 3 * melds.count == 14,
       mcrIsKnittedStraightForm(freq, meldCount: melds.count) {
        return true
    }
    return mcrIsStandardForm(freq)
}

/// 完整一副牌（暗牌 + 副露）是否可和
func mcrIsWinningHand(_ freq: [Int], melds: [Meld] = []) -> Bool {
    freq.reduce(0, +) + 3 * melds.count == 14 && mcrIsCompleteHand(freq, melds: melds)
}

// MARK: - 向听数

/// 标准型向听：counts 拆成「n 面子 + 1 将」最少还差几张。-1 已和，0 听牌。
private func mcrStandardShanten(_ counts: [Int], neededMelds n: Int) -> Int {
    var best = 2 * n
    var c = counts
    func dfs(_ start: Int, _ m: Int, _ t: Int, _ p: Int) {
        var i = start
        while i < mcrTileKinds && c[i] == 0 { i += 1 }
        if i == mcrTileKinds {
            var sh = 2 * n - 2 * m - t
            if m + t == n + 1 && p == 0 { sh += 1 }
            if sh < best { best = sh }
            return
        }
        if m < n, c[i] >= 3 {
            c[i] -= 3; dfs(i, m + 1, t, p); c[i] += 3
        }
        if m < n, mcrCanStartChow(i), c[i + 1] > 0, c[i + 2] > 0 {
            c[i] -= 1; c[i + 1] -= 1; c[i + 2] -= 1
            dfs(i, m + 1, t, p)
            c[i] += 1; c[i + 1] += 1; c[i + 2] += 1
        }
        if m + t < n + 1, c[i] >= 2 {
            c[i] -= 2; dfs(i, m, t + 1, p + 1); c[i] += 2
        }
        if m + t < n + 1, i < 27, i % 9 <= 7, c[i + 1] > 0 {
            c[i] -= 1; c[i + 1] -= 1; dfs(i, m, t + 1, p); c[i] += 1; c[i + 1] += 1
        }
        if m + t < n + 1, mcrCanStartChow(i), c[i + 2] > 0 {
            c[i] -= 1; c[i + 2] -= 1; dfs(i, m, t + 1, p); c[i] += 1; c[i + 2] += 1
        }
        c[i] -= 1; dfs(i, m, t, p); c[i] += 1
    }
    dfs(0, 0, 0, 0)
    return best
}

/// 七对向听（整手 13/14 张才有意义）；4 张相同按两对计
private func mcrSevenPairsShanten(_ counts: [Int]) -> Int {
    var pairs = 0
    for x in counts { pairs += x / 2 }
    return 6 - pairs
}

/// 十三幺向听
private func mcrThirteenOrphansShanten(_ counts: [Int]) -> Int {
    var kinds = 0
    var hasPair = false
    for i in mcrThirteenOrphans where counts[i] > 0 {
        kinds += 1
        if counts[i] >= 2 { hasPair = true }
    }
    return 13 - kinds - (hasPair ? 1 : 0)
}

/// 全不靠向听
private func mcrKnittedShanten(_ counts: [Int]) -> Int {
    var best = 13
    for perm in mcrSuitPermutations {
        let allowed = mcrKnittedAllowed(perm)
        var matched = 0
        for i in allowed where counts[i] > 0 { matched += 1 }
        best = min(best, 13 - min(matched, 13))
    }
    return best
}

/// 暗牌频率数组的向听数（含副露）。门清整手时并入七对 / 十三幺 / 全不靠。
func mcrShantenOf(_ freq: [Int], melds: [Meld] = []) -> Int {
    let size = freq.reduce(0, +)
    guard size >= 1 else { return 8 }
    let n = size / 3
    var best = mcrStandardShanten(freq, neededMelds: n)
    if melds.isEmpty, size == 13 || size == 14 {
        best = min(best, mcrSevenPairsShanten(freq))
        best = min(best, mcrThirteenOrphansShanten(freq))
        best = min(best, mcrKnittedShanten(freq))
    }
    return best
}

func mcrHandShanten(_ cards: [MahjongCard], melds: [Meld] = []) -> Int {
    mcrShantenOf(handToFrequency34(cards), melds: melds)
}

// MARK: - 进张 / 打牌建议 / 听牌

/// 3n+1 暗牌的进张
func mcrAcceptanceTiles(cards: [MahjongCard], melds: [Meld] = []) -> [(card: MahjongCard, remaining: Int)] {
    let base = handToFrequency34(cards)
    let meldFreq = meldsToFrequency34(melds)
    let size = base.reduce(0, +)
    guard size % 3 == 1, size + 3 * melds.count <= 13 else { return [] }
    let s0 = mcrShantenOf(base, melds: melds)
    var result: [(MahjongCard, Int)] = []
    for i in 0..<mcrTileKinds where base[i] + meldFreq[i] < 4 {
        var trial = base
        trial[i] += 1
        if mcrShantenOf(trial, melds: melds) < s0 {
            result.append((MahjongCard.fromMCRIndex(i), 4 - base[i] - meldFreq[i]))
        }
    }
    return result.sorted { mcrCardOrder($0.0, $1.0) }
}

/// 3n+2 暗牌的打牌建议
func mcrDiscardSuggestions(cards: [MahjongCard], melds: [Meld] = []) -> [DiscardSuggestion] {
    var base = handToFrequency34(cards)
    let size = base.reduce(0, +)
    guard size % 3 == 2, size + 3 * melds.count <= 14 else { return [] }

    var out: [DiscardSuggestion] = []
    for d in 0..<mcrTileKinds where base[d] > 0 {
        base[d] -= 1
        let remainingCards = (0..<mcrTileKinds).flatMap { idx in
            Array(repeating: MahjongCard.fromMCRIndex(idx), count: base[idx])
        }
        let sh = mcrShantenOf(base, melds: melds)
        let acc = mcrAcceptanceTiles(cards: remainingCards, melds: melds)
        base[d] += 1
        out.append(DiscardSuggestion(
            discard: MahjongCard.fromMCRIndex(d),
            resultingShanten: sh,
            acceptance: acc.map(\.card),
            acceptanceCount: acc.reduce(0) { $0 + $1.remaining }
        ))
    }
    return out.sorted { a, b in
        if a.resultingShanten != b.resultingShanten { return a.resultingShanten < b.resultingShanten }
        if a.acceptanceCount != b.acceptanceCount { return a.acceptanceCount > b.acceptanceCount }
        return mcrCardOrder(a.discard, b.discard)
    }
}

/// 3n+1 暗牌的听牌
func mcrCalculateWaiting(cards: [MahjongCard], melds: [Meld] = []) -> [MahjongCard] {
    let base = handToFrequency34(cards)
    let meldFreq = meldsToFrequency34(melds)
    let n = base.reduce(0, +)
    guard n % 3 == 1, n + 3 * melds.count <= 13 else { return [] }

    var waits: [MahjongCard] = []
    for i in 0..<mcrTileKinds {
        guard base[i] + meldFreq[i] < 4 else { continue }
        var trial = base
        trial[i] += 1
        if mcrIsCompleteHand(trial, melds: melds) {
            waits.append(MahjongCard.fromMCRIndex(i))
        }
    }
    return waits.sorted(by: mcrCardOrder)
}

/// 万 → 条 → 筒 → 风 → 箭 → 花，同门按点数
func mcrCardOrder(_ a: MahjongCard, _ b: MahjongCard) -> Bool {
    if a.suit.displaySortIndex != b.suit.displaySortIndex {
        return a.suit.displaySortIndex < b.suit.displaySortIndex
    }
    return a.rank < b.rank
}
