//
//  MahjongCalculator.swift
//  majiang calculator
//
//  四川麻将（血战到底）听牌/胡牌判定。
//  牌型：仅 万/筒/条，1–9 各 4 张（无字牌、无花牌）。
//  索引 0...8 万、9...17 筒、18...26 条；每张牌 0...4 张。
//
//  胡牌成立需同时满足：
//  ① 牌型成立——标准形「1 将对 + 4 面子（刻子/顺子）」，或 七对（含龙七对）。
//  ② 缺一门——整副胡牌手牌最多只含两门花色；三门齐全即「花猪」，不能胡。
//

import Foundation

// MARK: - 手牌 → 长度 27 的频率数组

/// 将手牌转为长度 27 的计数数组（下标：0–8 万、9–17 筒、18–26 条）
func handToFrequency27(_ cards: [MahjongCard]) -> [Int] {
    var c = Array(repeating: 0, count: 27)
    for card in cards {
        let i = card.tileIndex
        guard i >= 0, i < 27 else { continue }
        c[i] += 1
    }
    return c
}

// MARK: - 缺一门

/// 频率数组中实际出现的花色门数（万 / 筒 / 条 各算一门）
func suitCount(_ freq: [Int]) -> Int {
    var n = 0
    for suit in 0..<3 {
        let base = suit * 9
        for r in 0..<9 where freq[base + r] > 0 {
            n += 1
            break
        }
    }
    return n
}

// MARK: - 牌型：标准形

/// 剩余牌是否恰好拆成若干刻子/顺子（不含将）
private func meldsBacktrack(_ counts: inout [Int]) -> Bool {
    let j = counts.firstIndex(where: { $0 > 0 }) ?? -1
    if j < 0 { return true }

    // 优先刻子
    if counts[j] >= 3 {
        counts[j] -= 3
        if meldsBacktrack(&counts) {
            counts[j] += 3
            return true
        }
        counts[j] += 3
    }

    // 顺子：同花色，且点数 1–7 可作起点
    let col = j % 9
    if col <= 6, counts[j] > 0, counts[j + 1] > 0, counts[j + 2] > 0 {
        counts[j] -= 1
        counts[j + 1] -= 1
        counts[j + 2] -= 1
        if meldsBacktrack(&counts) {
            counts[j] += 1
            counts[j + 1] += 1
            counts[j + 2] += 1
            return true
        }
        counts[j] += 1
        counts[j + 1] += 1
        counts[j + 2] += 1
    }

    return false
}

/// 14 张是否满足标准形「1 将对 + 4 面子」（不含缺一门约束）
private func isStandardForm(_ freq: [Int]) -> Bool {
    var c = freq
    for i in 0..<27 where c[i] >= 2 {
        c[i] -= 2
        if meldsBacktrack(&c) {
            return true
        }
        c[i] += 2
    }
    return false
}

// MARK: - 牌型：七对

/// 14 张是否为七对——七个对子。
/// 龙七对（4 张同牌）按两对计入，因此判定即「每种牌张数均为偶数」。
/// 调用方需自行保证总数为 14。
private func isSevenPairs(_ freq: [Int]) -> Bool {
    for count in freq where count % 2 != 0 {
        return false
    }
    return true
}

// MARK: - 胡牌判定

/// 频率数组是否构成一副可胡的牌：牌型成立 且 满足缺一门（≤ 2 门花色）。
///
/// 支持任意「3n+2」张（n = 0...4），即 2 / 5 / 8 / 11 / 14 张：
/// 拆成「1 将对 + n 面子」即可。对不满 14 张的部分手牌，等价于把尚未补齐的
/// 面子视为「默认能凑成」，从而 4 / 7 / 10 张也能正确算听。
/// 七对仅适用于完整的 14 张。
func isCompleteHand(_ freq: [Int]) -> Bool {
    guard freq.count == 27 else { return false }
    let sum = freq.reduce(0, +)
    guard sum >= 2, sum % 3 == 2 else { return false }

    // 缺一门：三门齐全为「花猪」，不能胡
    guard suitCount(freq) <= 2 else { return false }

    if sum == 14, isSevenPairs(freq) { return true }
    return isStandardForm(freq)
}

/// 完整 14 张是否可胡（四川麻将）
func isWinningHand14(_ freq: [Int]) -> Bool {
    freq.reduce(0, +) == 14 && isCompleteHand(freq)
}

// MARK: - 向听数 / 进张 / 打牌建议

/// 标准型向听数：counts 拆成「n 面子 + 1 将」最少还差几张。
/// -1 表示已和，0 表示听牌。neededMelds = 总张数 / 3。
private func standardShantenN(_ counts: [Int], neededMelds n: Int) -> Int {
    var best = 2 * n
    var c = counts
    func dfs(_ start: Int, _ m: Int, _ t: Int, _ p: Int) {
        var i = start
        while i < 27 && c[i] == 0 { i += 1 }
        if i == 27 {
            var sh = 2 * n - 2 * m - t
            if m + t == n + 1 && p == 0 { sh += 1 }   // n+1 块但无将 → +1
            if sh < best { best = sh }
            return
        }
        let col = i % 9
        // 刻子（最多 n 个面子）
        if m < n, c[i] >= 3 {
            c[i] -= 3; dfs(i, m + 1, t, p); c[i] += 3
        }
        // 顺子
        if m < n, col <= 6, c[i] > 0, c[i + 1] > 0, c[i + 2] > 0 {
            c[i] -= 1; c[i + 1] -= 1; c[i + 2] -= 1
            dfs(i, m + 1, t, p)
            c[i] += 1; c[i + 1] += 1; c[i + 2] += 1
        }
        // 搭子（面子+搭子最多 n+1 块）：对子（可作将）
        if m + t < n + 1, c[i] >= 2 {
            c[i] -= 2; dfs(i, m, t + 1, p + 1); c[i] += 2
        }
        // 搭子：两面 / 嵌张
        if m + t < n + 1, col <= 7, c[i] > 0, c[i + 1] > 0 {
            c[i] -= 1; c[i + 1] -= 1; dfs(i, m, t + 1, p); c[i] += 1; c[i + 1] += 1
        }
        if m + t < n + 1, col <= 6, c[i] > 0, c[i + 2] > 0 {
            c[i] -= 1; c[i + 2] -= 1; dfs(i, m, t + 1, p); c[i] += 1; c[i + 2] += 1
        }
        // 孤张：弃掉一张
        c[i] -= 1; dfs(i, m, t, p); c[i] += 1
    }
    dfs(0, 0, 0, 0)
    return best
}

/// 七对向听数（仅整手 13/14 张有意义）。
/// 四川麻将认龙七对：4 张同牌算两对，故按 Σ⌊张数/2⌋ 计对子数，无「七门」限制。
private func chiitoiShanten(_ counts: [Int]) -> Int {
    var pairs = 0
    for x in counts { pairs += x / 2 }
    return 6 - pairs
}

/// 频率数组的向听数（含缺一门：取「保留两门」的最优；整手时并入七对）
func shantenOf(_ freq: [Int]) -> Int {
    let size = freq.reduce(0, +)
    guard size >= 1 else { return 8 }
    let n = size / 3
    let whole = (size == 13 || size == 14)
    var best = Int.max
    for drop in 0..<3 {
        var c = freq
        for r in 0..<9 { c[drop * 9 + r] = 0 }
        best = min(best, standardShantenN(c, neededMelds: n))
        if whole { best = min(best, chiitoiShanten(c)) }
    }
    return best
}

/// 手牌向听数
func handShanten(_ cards: [MahjongCard]) -> Int {
    shantenOf(handToFrequency27(cards))
}

/// 3n+1 手牌的进张：加入后能降低向听的牌，及各自剩余张数（4 − 手中张数）
func acceptanceTiles(cards: [MahjongCard]) -> [(card: MahjongCard, remaining: Int)] {
    let base = handToFrequency27(cards)
    let size = base.reduce(0, +)
    guard size % 3 == 1, size <= 13 else { return [] }
    let s0 = shantenOf(base)
    var result: [(MahjongCard, Int)] = []
    for i in 0..<27 where base[i] < 4 {
        var trial = base
        trial[i] += 1
        if shantenOf(trial) < s0 {
            result.append((MahjongCard.fromTileIndex(i), 4 - base[i]))
        }
    }
    return result.sorted { a, b in
        if a.0.suit.displaySortIndex != b.0.suit.displaySortIndex {
            return a.0.suit.displaySortIndex < b.0.suit.displaySortIndex
        }
        return a.0.rank < b.0.rank
    }
}

/// 一个弃牌方案
struct DiscardSuggestion: Identifiable {
    let id = UUID()
    let discard: MahjongCard
    let resultingShanten: Int
    let acceptance: [MahjongCard]
    /// 进张总张数（各进张牌剩余张数之和）
    let acceptanceCount: Int
}

/// 3n+2 手牌的打牌建议：每个可弃的牌 → 弃后向听 + 进张，按「向听升序、进张降序」排序
func discardSuggestions(cards: [MahjongCard]) -> [DiscardSuggestion] {
    var base = handToFrequency27(cards)
    let size = base.reduce(0, +)
    guard size % 3 == 2, size <= 14 else { return [] }

    var out: [DiscardSuggestion] = []
    for d in 0..<27 where base[d] > 0 {
        base[d] -= 1
        let remainingCards = (0..<27).flatMap { idx in
            Array(repeating: MahjongCard.fromTileIndex(idx), count: base[idx])
        }
        let sh = shantenOf(base)
        let acc = acceptanceTiles(cards: remainingCards)
        base[d] += 1
        out.append(DiscardSuggestion(
            discard: MahjongCard.fromTileIndex(d),
            resultingShanten: sh,
            acceptance: acc.map(\.card),
            acceptanceCount: acc.reduce(0) { $0 + $1.remaining }
        ))
    }
    return out.sorted { a, b in
        if a.resultingShanten != b.resultingShanten { return a.resultingShanten < b.resultingShanten }
        if a.acceptanceCount != b.acceptanceCount { return a.acceptanceCount > b.acceptanceCount }
        if a.discard.suit.displaySortIndex != b.discard.suit.displaySortIndex {
            return a.discard.suit.displaySortIndex < b.discard.suit.displaySortIndex
        }
        return a.discard.rank < b.discard.rank
    }
}

// MARK: - 听牌

/// 当前 3n+1 张手牌（n = 0...4，即 1 / 4 / 7 / 10 / 13 张），
/// 枚举加入哪一张后能凑成「1 将对 + n 面子」（标准形 / 七对，且满足缺一门）。
/// 不满 13 张时，未补齐的面子按「默认凑成」处理。
func calculateWaiting(cards: [MahjongCard]) -> [MahjongCard] {
    let base = handToFrequency27(cards)
    let n = base.reduce(0, +)
    guard n % 3 == 1, n <= 13 else { return [] }

    var waits: [MahjongCard] = []
    for i in 0..<27 {
        guard base[i] < 4 else { continue }
        var trial = base
        trial[i] += 1
        if isCompleteHand(trial) {
            waits.append(MahjongCard.fromTileIndex(i))
        }
    }
    return waits.sorted { a, b in
        if a.suit.displaySortIndex != b.suit.displaySortIndex {
            return a.suit.displaySortIndex < b.suit.displaySortIndex
        }
        return a.rank < b.rank
    }
}
