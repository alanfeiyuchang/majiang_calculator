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
