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
import CoreGraphics

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
/// ③ 最大的簇视为手牌，其余簇按「相邻同牌」切段判定（几组副露紧挨也能拆）：
///    每段 3 张同牌 → 碰、4 张同牌 → 明杠、孤立单张 → 暗杠、认不准 → 并回手牌。
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
        if cards.count == 1 {
            melds.append(Meld(kind: .concealedKong, card: cards[0]))   // 暗杠：只露的那张明牌
            guessed = true
        } else if let parsed = parseMeldRuns(cards) {
            melds.append(contentsOf: parsed)
            if parsed.contains(where: { $0.kind == .concealedKong }) { guessed = true }
        } else {
            hand.append(contentsOf: cards)   // 认不准 → 并回手牌
        }
    }
    return RecognitionResult(hand: hand, melds: melds, guessedConcealedKong: guessed)
}

/// 把一个非手牌簇解析成一组或多组副露（桌上几组碰/杠可能紧挨着没有空隙）。
/// 按「相邻同牌」切段：3 张 = 碰、4 张 = 明杠、单张 = 暗杠只露的那张明牌；
/// 出现 2 张同牌等认不准的段、或整簇没有一个 3/4 张的段，返回 nil（并回手牌）。
private func parseMeldRuns(_ cards: [MahjongCard]) -> [Meld]? {
    var runs: [[MahjongCard]] = []
    for c in cards {
        if let last = runs.last?.last, last == c {
            runs[runs.count - 1].append(c)
        } else {
            runs.append([c])
        }
    }
    guard runs.contains(where: { $0.count == 3 || $0.count == 4 }) else { return nil }

    var melds: [Meld] = []
    for run in runs {
        switch run.count {
        case 3: melds.append(Meld(kind: .pong, card: run[0]))
        case 4: melds.append(Meld(kind: .exposedKong, card: run[0]))
        case 1: melds.append(Meld(kind: .concealedKong, card: run[0]))
        default: return nil
        }
    }
    return melds
}

// MARK: - 二次放大识别的区域估计

/// 第一遍识别出的牌框（原图像素坐标）的并集区域，外扩后返回，用于裁剪放大再识别。
/// 区域已占满画面（放大无意义）或没有检测框时返回 nil。
func zoomRegion(boxes: [CGRect], imageSize: CGSize) -> CGRect? {
    guard let first = boxes.first, imageSize.width > 0, imageSize.height > 0 else { return nil }
    var union = first
    for b in boxes.dropFirst() { union = union.union(b) }

    // 外扩：约 1.5 张牌高 + 并集的 12%，容忍第一遍漏检的边缘牌
    let avgH = boxes.map(\.height).reduce(0, +) / CGFloat(boxes.count)
    let pad = max(avgH * 1.5, max(union.width, union.height) * 0.12)
    let padded = union.insetBy(dx: -pad, dy: -pad)
        .intersection(CGRect(origin: .zero, size: imageSize))
    guard padded.width > 0, padded.height > 0 else { return nil }

    // 两个方向都已接近整图 → 放大没有收益
    if padded.width > imageSize.width * 0.85 && padded.height > imageSize.height * 0.85 {
        return nil
    }
    return padded
}
