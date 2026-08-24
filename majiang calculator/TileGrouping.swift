//
//  TileGrouping.swift
//  majiang calculator
//
//  拍照识别后的空间聚类：把识别到的牌盒分成「手牌」与「桌上副露（碰/明杠/暗杠）」。
//  纯几何逻辑，不依赖 UIKit / ONNX，便于独立断言测试（见 Tests/GroupingTests.swift）。
//
//  川麻无吃，副露只有：碰（3 张同牌）/ 明杠（4 张同牌）/ 暗杠（1 明 3 暗，只识别到那张明牌）。
//
//  整桌入镜时，桌子中央的弃牌堆、对家的牌也会被模型检出。这里**不**按大小把它们滤掉——
//  平摊的碰/杠又扁又比手牌远一点，任何按大小的丢弃都会先吃掉自己的副露。
//  它们由裁剪页的自动框在像素层面排除；没排干净时张数会对不上，由 hasValidTileCount 提示用户。
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

    /// 换算成「手牌张数」：一组副露占 3 张名额。合法值为 13（未摸牌）或 14（已摸牌）
    var effectiveTileCount: Int { hand.count + 3 * melds.count }
    var hasValidTileCount: Bool { effectiveTileCount == 13 || effectiveTileCount == 14 }
}

// MARK: - 近景判断（**只**用于给裁剪页自动画框，绝不参与识别结果的取舍）
//
// 识别链路上不做任何按大小的丢弃：桌上的牌由「自动裁剪框」在像素层面排除，
// 万一没排干净，则由 hasValidTileCount 把张数对不上的情况显式拦下来告诉用户，
// 而不是偷偷删掉。近景判断只用来决定那个框画在哪——画歪了用户拖一下就好。
//
// 判据用**框高**。data/ 里 12 张实拍的检测框显示：属于自己的牌，框高集中在
// 0.049–0.110（相对图高）；桌上的弃牌在 0.019–0.054。12 张里 11 张能干净分开。
// 原因是弃牌**又远又平摊**，被透视双重压缩；自己的牌要么立着、要么就在眼前。
// （早先我按「副露平摊所以不能用高度」改成了按宽度判，实拍数据表明那个推理错了：
//   平摊的是弃牌，不是自己的副露。）

/// 远近一律以**牌的宽度**为准，不能用高度。
/// 手牌是立着的，碰/杠是平摊在桌上的——同样的距离，平摊牌被透视纵向压扁，
/// 框高只有立牌的 6~7 成，用高度会把自己的副露当成「远处的牌」整组滤掉。
/// 宽度几乎不受立/平影响（压缩发生在纵向），却照样随距离缩小，是干净的距离代理。
///
/// 低于「基准牌高」这个比例的框视为桌上的牌。0.70 是在 data/ 的 12 张实拍上扫出来的：
/// 配合下面的外扩与闭包，平均 IoU 0.814，且没有一张会把自己的牌裁掉。
private let nearFieldRatio: CGFloat = 0.70

/// 区域在牌框并集之外再放出去的余量，单位是「平均牌高」的倍数。
/// 模型对自己的牌检得很全（12 张实拍里 13–15 张一张不漏），所以余量给得很小；
/// 给大了薄薄的单排手牌 IoU 掉得很快。
private let regionPadTiles: CGFloat = 0.20

/// 闭包吸收阈值：已经有这么大比例压在框内的检测框会被并进来。
/// 用来救「平摊成方阵、透视很陡」的情况——最远那排偏矮会被高度阈值切掉，
/// 但它就紧贴在保留区上方，闭包能捞回来，又不会吸到远处的弃牌。
private let closureOverlap: CGFloat = 0.5

/// 基准牌高 = 高度的第 90 百分位。
/// 不用最大值（单个虚框就会把基准抬高），也不用中位数
/// （桌上的牌可能比自己的牌还多，中位数会落进远景里）。
func referenceTileHeight(_ heights: [CGFloat]) -> CGFloat {
    guard !heights.isEmpty else { return 0 }
    let sorted = heights.sorted(by: >)
    return sorted[min(sorted.count - 1, sorted.count / 10)]
}

/// 按框高筛出属于自己的牌，返回保留项与被剔除的数量。
/// 全部牌高度相近时（只拍了自己的牌）不会剔除任何一项。
func nearFieldFilter<T>(_ items: [T], height: (T) -> CGFloat) -> (kept: [T], dropped: Int) {
    let hRef = referenceTileHeight(items.map(height))
    guard hRef > 0 else { return (items, 0) }
    let minH = hRef * nearFieldRatio
    let kept = items.filter { height($0) >= minH }
    return (kept, items.count - kept.count)
}

private func medianHeight(_ boxes: [TileBox]) -> CGFloat {
    guard !boxes.isEmpty else { return 0 }
    let sorted = boxes.map(\.height).sorted()
    return sorted[sorted.count / 2]
}

/// 把识别到的牌盒按空间聚类分成手牌与副露。
///
/// 步骤：① 按纵向中心分行；
/// ② 行内按横向间距切成「簇」（间距 > 阈值即断开）；
/// ③ 按「张数 × 牌面大小」选出手牌簇，其余簇按「相邻同牌」切段判定
///    （几组副露紧挨也能拆）：每段 3 张同牌 → 碰、4 张同牌 → 明杠、孤立单张 → 暗杠；
///    认不准的簇并回手牌——不丢弃任何检测到的牌。
func groupTiles(_ boxes: [TileBox]) -> RecognitionResult {
    // 先严格解析：只有 3/4 张同牌才算副露，孤立单张**不**猜暗杠。
    // 「单张 = 暗杠」这条猜测会让几乎任何簇都能「解析成副露」，
    // 实拍里因此凭空造出好几组暗杠、张数暴涨（见 data/README.md 的识别评测）。
    let strict = group(boxes, guessConcealedKong: false)
    if strict.hasValidTileCount { return strict }

    // 张数对不上，再试把孤立单张当暗杠——只有这样能让张数说得通时才采纳。
    // 真的暗杠（只露一张）会让 13/14 成立，被切开的手牌不会。
    let lenient = group(boxes, guessConcealedKong: true)
    return lenient.hasValidTileCount ? lenient : strict
}

private func group(_ boxes: [TileBox], guessConcealedKong: Bool) -> RecognitionResult {
    guard !boxes.isEmpty else {
        return RecognitionResult(hand: [], melds: [], guessedConcealedKong: false)
    }

    // 不做任何丢弃（见上）：所有检测框都参与分组
    let near = boxes

    // ① 分行
    let avgH = near.map(\.height).reduce(0, +) / CGFloat(near.count)
    let rowGap = max(avgH * 0.6, 1)
    var rows: [[TileBox]] = []
    for b in near.sorted(by: { $0.cy < $1.cy }) {
        if let i = rows.indices.last, let first = rows[i].first, abs(b.cy - first.cy) <= rowGap {
            rows[i].append(b)
        } else {
            rows.append([b])
        }
    }

    // ② 行内按横向间距切簇（间距 > 约半张牌宽 → 断开）
    let avgW = near.map(\.width).reduce(0, +) / CGFloat(near.count)
    // 0.9 而不是 0.55：立着摆的手牌彼此有缝，阈值太小会把一排切成好几段，
    // 碎出来的单张再被当成暗杠。桌上副露与手牌的间隔通常大于一张牌宽。
    let colGap = max(avgW * 0.9, 1)
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

    // ③ 手牌簇：以张数为主，牌面大小加权——张数相近时，离镜头更近（框更宽）的那簇才是手牌。
    //    大小一致时退化为纯张数比较，与只拍自己的牌时的行为相同。
    let hRef = referenceTileHeight(near.map(\.height))
    func clusterScore(_ cluster: [TileBox]) -> CGFloat {
        let sizeRatio = hRef > 0 ? medianHeight(cluster) / hRef : 1
        return sizeRatio * CGFloat(min(cluster.count, 14))
    }
    // 每个簇先试着解析成副露；解析不成的才可能是手牌。
    // （手牌里混着单张和顺子，解析必然失败；整齐的 3/4 张同牌则会解析成功。）
    let parsed: [[Meld]?] = clusters.map {
        parseMeldRuns($0.sorted { $0.minX < $1.minX }.map(\.card),
                      guessConcealedKong: guessConcealedKong)
    }
    let handCandidates = clusters.indices.filter { parsed[$0] == nil }
    let pool = handCandidates.isEmpty ? Array(clusters.indices) : handCandidates
    guard let handIdx = pool.max(by: { clusterScore(clusters[$0]) < clusterScore(clusters[$1]) })
    else {
        return RecognitionResult(hand: [], melds: [], guessedConcealedKong: false)
    }

    var hand: [MahjongCard] = clusters[handIdx].sorted { $0.minX < $1.minX }.map(\.card)
    var melds: [Meld] = []
    var guessed = false

    for (i, cluster) in clusters.enumerated() where i != handIdx {
        let cards = cluster.sorted { $0.minX < $1.minX }.map(\.card)
        if let ms = parsed[i] {
            melds.append(contentsOf: ms)
            if ms.contains(where: { $0.kind == .concealedKong }) { guessed = true }
        } else {
            // 认不准 → 并回手牌。宁可多出来让用户看见并删掉，也不能静默丢弃：
            // 真是桌上的牌时张数会对不上，由 hasValidTileCount 拦下并提示核对。
            hand.append(contentsOf: cards)
        }
    }

    return RecognitionResult(hand: hand, melds: melds, guessedConcealedKong: guessed)
}

/// 把一个非手牌簇解析成一组或多组副露（桌上几组碰/杠可能紧挨着没有空隙）。
/// 按「相邻同牌」切段：3 张 = 碰、4 张 = 明杠、单张 = 暗杠只露的那张明牌；
/// 出现 2 张同牌等认不准的段、或整簇没有一个 3/4 张的段，返回 nil（交给调用方决定并回还是丢弃）。
private func parseMeldRuns(_ cards: [MahjongCard], guessConcealedKong: Bool) -> [Meld]? {
    var runs: [[MahjongCard]] = []
    for c in cards {
        if let last = runs.last?.last, last == c {
            runs[runs.count - 1].append(c)
        } else {
            runs.append([c])
        }
    }
    // 只露一张的暗杠：整簇就一张牌。仅在允许猜的时候成立。
    if guessConcealedKong, cards.count == 1 {
        return [Meld(kind: .concealedKong, card: cards[0])]
    }
    guard runs.contains(where: { $0.count == 3 || $0.count == 4 }) else { return nil }

    var melds: [Meld] = []
    for run in runs {
        switch run.count {
        case 3: melds.append(Meld(kind: .pong, card: run[0]))
        case 4: melds.append(Meld(kind: .exposedKong, card: run[0]))
        case 1:
            guard guessConcealedKong else { return nil }   // 不猜暗杠时，单张让整簇解析失败
            melds.append(Meld(kind: .concealedKong, card: run[0]))
        default: return nil
        }
    }
    return melds
}

// MARK: - 「自己的牌」所在区域

/// 从检测框里圈出「自己的牌（手牌 + 碰/杠）」所在区域，相对整图返回。
///
/// ① 按框高选出种子（见 nearFieldRatio）；
/// ② 闭包：反复把「已有一半以上压在当前框内」的框吸收进来，再重算框，直到不变。
///    只吸收压在框上的，所以不会像早先的「空间连通扩张」那样顺着弃牌堆一路蔓延出去。
/// ③ 并集外扩 regionPadTiles 个牌高。
///
/// 在 data/ 的 12 张实拍上：平均 IoU 0.814，8/12 达到 0.8，没有一张裁到自己的牌。
func myTilesRegion(boxes: [CGRect], imageSize: CGSize) -> CGRect? {
    guard !boxes.isEmpty, imageSize.width > 0, imageSize.height > 0 else { return nil }

    let (seed, _) = nearFieldFilter(boxes) { $0.height }
    guard !seed.isEmpty else { return nil }

    var keep = seed
    for _ in 0..<4 {
        guard let r = paddedUnion(keep, imageSize: imageSize) else { return nil }
        let grown = boxes.filter { b in
            let o = b.intersection(r)
            guard !o.isNull else { return false }
            let a = b.width * b.height
            return a > 0 && (o.width * o.height) >= closureOverlap * a
        }
        if grown.count == keep.count { break }
        keep = grown
    }
    return paddedUnion(keep, imageSize: imageSize)
}

/// 并集 + 按平均牌高外扩，钳在图内
private func paddedUnion(_ boxes: [CGRect], imageSize: CGSize) -> CGRect? {
    guard let first = boxes.first else { return nil }
    var union = first
    for b in boxes.dropFirst() { union = union.union(b) }
    let avgH = boxes.map(\.height).reduce(0, +) / CGFloat(boxes.count)
    let pad = avgH * regionPadTiles
    let padded = union.insetBy(dx: -pad, dy: -pad)
        .intersection(CGRect(origin: .zero, size: imageSize))
    return (padded.width > 0 && padded.height > 0) ? padded : nil
}



/// 近景牌框（原图像素坐标）的并集，外扩后钳在图内。
/// 传进来的框应当已经过近景过滤，否则区域会撑满整张桌子。
/// 既用于裁剪页自动画选框，也用于二次放大识别。没有检测框时返回 nil。
func handRegion(boxes: [CGRect], imageSize: CGSize) -> CGRect? {
    guard let first = boxes.first, imageSize.width > 0, imageSize.height > 0 else { return nil }
    var union = first
    for b in boxes.dropFirst() { union = union.union(b) }

    // 外扩：约 1.5 张牌高 + 并集的 12%，容忍第一遍漏检的边缘牌
    let avgH = boxes.map(\.height).reduce(0, +) / CGFloat(boxes.count)
    let pad = max(avgH * 1.5, max(union.width, union.height) * 0.12)
    let padded = union.insetBy(dx: -pad, dy: -pad)
        .intersection(CGRect(origin: .zero, size: imageSize))
    guard padded.width > 0, padded.height > 0 else { return nil }
    return padded
}

/// 二次放大识别用的区域。区域已占满画面时放大没有收益，返回 nil。
func zoomRegion(boxes: [CGRect], imageSize: CGSize) -> CGRect? {
    guard let region = handRegion(boxes: boxes, imageSize: imageSize) else { return nil }
    if region.width > imageSize.width * 0.85 && region.height > imageSize.height * 0.85 {
        return nil
    }
    return region
}
