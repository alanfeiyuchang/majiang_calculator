//
//  TileGrouping.swift
//  majiang calculator
//
//  拍照识别后的空间聚类：把识别到的牌盒分成「手牌」与「桌上副露（碰/明杠/暗杠）」。
//  纯几何逻辑，不依赖 UIKit / ONNX，便于独立断言测试（见 Tests/GroupingTests.swift）。
//
//  川麻无吃，副露只有：碰（3 张同牌）/ 明杠（4 张同牌）/ 暗杠（1 明 3 暗，只识别到那张明牌）。
//

import Foundation

/// 识别到的一张牌：横向范围 + 行位置（纵向中心）+ 牌面
struct TileBox {
    let minX: CGFloat
    let maxX: CGFloat
    /// 纵向中心（分行用）
    let cy: CGFloat
    let height: CGFloat
    let card: MahjongCard

    var width: CGFloat { maxX - minX }
    var cx: CGFloat { (minX + maxX) / 2 }
}

/// 分组结果：手牌 + 桌上副露；guessedConcealedKong 标记是否含「靠单张明牌猜出的暗杠」（需重点核对）
struct RecognitionResult {
    var hand: [MahjongCard]
    var melds: [Meld]
    var guessedConcealedKong: Bool
}

/// 把识别到的牌盒按空间聚类分成手牌与副露。
///
/// 步骤：① 按纵向中心分行；② 行内按横向间距切成「簇」（间距 > 阈值即断开）；
/// ③ 最大的簇视为手牌，其余簇按张数/是否同牌判定：
///    3 张同牌 → 碰、4 张同牌 → 明杠、孤立单张 → 暗杠、其它 → 并回手牌。
func groupTiles(_ boxes: [TileBox]) -> RecognitionResult {
    guard !boxes.isEmpty else {
        return RecognitionResult(hand: [], melds: [], guessedConcealedKong: false)
    }

    // ① 分行
    let avgH = boxes.map(\.height).reduce(0, +) / CGFloat(boxes.count)
    let rowGap = max(avgH * 0.6, 1)
    var rows: [[TileBox]] = []
    for b in boxes.sorted(by: { $0.cy < $1.cy }) {
        if let i = rows.indices.last, let first = rows[i].first, abs(b.cy - first.cy) <= rowGap {
            rows[i].append(b)
        } else {
            rows.append([b])
        }
    }

    // ② 行内按横向间距切簇（间距 > 约半张牌宽 → 断开）
    let avgW = boxes.map(\.width).reduce(0, +) / CGFloat(boxes.count)
    let colGap = max(avgW * 0.55, 1)
    var clusters: [[TileBox]] = []
    for row in rows {
        let sorted = row.sorted { $0.minX < $1.minX }
        var current: [TileBox] = []
        var prevMaxX = -CGFloat.greatestFiniteMagnitude
        for b in sorted {
            if !current.isEmpty, b.minX - prevMaxX > colGap {
                clusters.append(current)
                current = []
            }
            current.append(b)
            prevMaxX = max(prevMaxX, b.maxX)
        }
        if !current.isEmpty { clusters.append(current) }
    }

    // ③ 最大簇为手牌，其余判定副露
    guard let handIdx = clusters.indices.max(by: { clusters[$0].count < clusters[$1].count }) else {
        return RecognitionResult(hand: [], melds: [], guessedConcealedKong: false)
    }

    var hand: [MahjongCard] = []
    var melds: [Meld] = []
    var guessed = false
    for (i, cluster) in clusters.enumerated() {
        let cards = cluster.sorted { $0.minX < $1.minX }.map(\.card)
        if i == handIdx {
            hand.append(contentsOf: cards)
            continue
        }
        let allSame = cards.dropFirst().allSatisfy { $0 == cards.first }
        switch (cards.count, allSame) {
        case (3, true):
            melds.append(Meld(kind: .pong, card: cards[0]))
        case (4, true):
            melds.append(Meld(kind: .exposedKong, card: cards[0]))
        case (1, _):
            melds.append(Meld(kind: .concealedKong, card: cards[0]))   // 暗杠：只露的那张明牌
            guessed = true
        default:
            hand.append(contentsOf: cards)   // 认不准 → 并回手牌
        }
    }
    return RecognitionResult(hand: hand, melds: melds, guessedConcealedKong: guessed)
}
