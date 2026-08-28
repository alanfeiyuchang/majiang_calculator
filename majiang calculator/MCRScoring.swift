//
//  MCRScoring.swift
//  majiang calculator
//
//  国标麻将（MCR / 中国麻将竞赛规则）81 种番型的算番引擎，起和 8 分。
//
//  ── 不重复计算原则 ────────────────────────────────────────────────
//  国标算番不是把番型堆起来，必须遵守四条原则，本文件的实现方式如下：
//
//  1. 不可拆分原则：已组成某番的面子不可再拆开去凑另一个番。
//     → 面子结构类番型（一般高/喜相逢/连六/老少副/双同刻/清龙/一色三同顺…）
//       通过「把 4 副面子做集合划分、每块取最高番、取总分最大的划分」来计算，
//       一副面子只可能落进一个块里，天然不可拆分。
//
//  2. 不可重复原则：同一组合只能计一次。
//     → 由 `mcrFanExcludes` 排除表实现：高番型出现时，把它已经«包含»的
//       低番型整条删掉（如 大三元 出现即删掉 箭刻 / 双箭刻）。
//
//  3. 就高不就低：一种组合能算多个番型时取最高的。
//     → 集合划分里每块取「该块能成立的最高番」；整手牌层面则对所有
//       和牌牌型 × 所有拆解方式 × 和牌张归属 取总分最大者。
//
//  4. 套算一次原则：一副面子与别的面子「配对」只能配一次。
//     → 同样由集合划分保证：两两配对型番（一般高等）在划分中是大小为 2 的块，
//       一副面子不可能同时进两个块。
//
//  ── 需要说明的取舍 ────────────────────────────────────────────────
//  · 杠的番：四杠 88（独占）；三杠 32 + 每个杠各自的 明杠 1 / 暗杠 2；
//    两个及以下时 双明杠 4（吃掉两个明杠）、双暗杠 6（吃掉两个暗杠）。
//  · 七对允许「4 张相同 = 两对」，与多数国标实现一致。
//  · 无番和：除 花牌、自摸 外没有任何番型时计 8 分。
//  · 和绝张、妙手回春、海底捞月、抢杠和 等场景番无法从牌面推断，由用户勾选。
//

import Foundation

// MARK: - 面子

struct MCRSet: Equatable {
    enum Kind: Equatable { case chow, pung, kong, pair }
    var kind: Kind
    /// 顺子存起始牌下标；刻/杠/将存牌本身
    var tile: Int
    /// 结构上是「暗」的（手内的牌，或暗杠）
    var concealed: Bool
    /// 来自副露区
    var fromMeld: Bool

    var isPungLike: Bool { kind == .pung || kind == .kong }
    var suit: Int { mcrSuitOf(tile) }
    var rank: Int { mcrRankOf(tile) }

    /// 这副面子覆盖的牌下标
    var tiles: [Int] {
        switch kind {
        case .chow: return [tile, tile + 1, tile + 2]
        case .pung: return [tile, tile, tile]
        case .kong: return [tile, tile, tile, tile]
        case .pair: return [tile, tile]
        }
    }
}

// MARK: - 和牌场景

/// 国标胡牌瞬间的场景信息
struct MCRContext {
    var selfDrawn: Bool = false
    /// 和的那张牌（34 下标）；-1 表示未知（如仅做打牌建议的粗估）
    var winningTile: Int = -1
    /// 圈风 0–3 = 东南西北
    var prevalentWind: Int = 0
    /// 门风 0–3 = 东南西北
    var seatWind: Int = 0
    /// 杠上开花（自摸侧）
    var kongBloom: Bool = false
    /// 妙手回春：自摸牌墙最后一张
    var lastTileDraw: Bool = false
    /// 海底捞月：和最后一张打出的牌
    var lastDiscard: Bool = false
    /// 抢杠和
    var robbingKong: Bool = false
    /// 和绝张：和的这张牌是明面上的第 4 张
    var lastTileOfKind: Bool = false
    /// 花牌张数
    var flowers: Int = 0
}

// MARK: - 算番结果

struct MCRScore {
    let items: [FanItem]
    /// 含花牌的总分
    let totalPoints: Int
    /// 不含花牌的分（起和线按这个算）
    let scoringPoints: Int
    /// 是否达到起和 8 分
    var meetsMinimum: Bool { scoringPoints >= mcrMinimumPoints }
}

/// 起和分
let mcrMinimumPoints = 8

// MARK: - 番种分值表（81 种）

let mcrFanPoints: [String: Int] = [
    // 88
    "大四喜": 88, "大三元": 88, "绿一色": 88, "九莲宝灯": 88,
    "四杠": 88, "连七对": 88, "十三幺": 88,
    // 64
    "清幺九": 64, "小四喜": 64, "小三元": 64, "字一色": 64,
    "四暗刻": 64, "一色双龙会": 64,
    // 48
    "一色四同顺": 48, "一色四节高": 48,
    // 32
    "一色四步高": 32, "三杠": 32, "混幺九": 32,
    // 24
    "七对": 24, "七星不靠": 24, "全双刻": 24, "清一色": 24,
    "一色三同顺": 24, "一色三节高": 24, "全大": 24, "全中": 24, "全小": 24,
    // 16
    "清龙": 16, "三色双龙会": 16, "一色三步高": 16, "全带五": 16,
    "三同刻": 16, "三暗刻": 16,
    // 12
    "全不靠": 12, "组合龙": 12, "大于五": 12, "小于五": 12, "三风刻": 12,
    // 8
    "花龙": 8, "推不倒": 8, "三色三同顺": 8, "三色三节高": 8, "无番和": 8,
    "妙手回春": 8, "海底捞月": 8, "杠上开花": 8, "抢杠和": 8,
    // 6
    "碰碰和": 6, "混一色": 6, "三色三步高": 6, "五门齐": 6,
    "全求人": 6, "双暗杠": 6, "双箭刻": 6,
    // 4
    "全带幺": 4, "不求人": 4, "双明杠": 4, "和绝张": 4,
    // 2
    "箭刻": 2, "圈风刻": 2, "门风刻": 2, "门前清": 2, "平和": 2,
    "四归一": 2, "双同刻": 2, "双暗刻": 2, "暗杠": 2, "断幺": 2,
    // 1
    "一般高": 1, "喜相逢": 1, "连六": 1, "老少副": 1, "幺九刻": 1,
    "明杠": 1, "缺一门": 1, "无字": 1, "边张": 1, "坎张": 1,
    "单钓将": 1, "自摸": 1, "花牌": 1,
]

/// 不可重复原则的排除表：key 番型成立时，把 value 里的番型整条删掉
let mcrFanExcludes: [String: [String]] = [
    "大四喜": ["三风刻", "圈风刻", "门风刻", "碰碰和", "幺九刻"],
    "大三元": ["箭刻", "双箭刻"],
    "绿一色": ["缺一门"],
    "九莲宝灯": ["清一色", "门前清", "无字", "幺九刻"],
    "四杠": ["三杠", "双明杠", "双暗杠", "明杠", "暗杠", "碰碰和", "单钓将"],
    "连七对": ["七对", "清一色", "门前清", "无字", "单钓将", "不求人"],
    "十三幺": ["五门齐", "门前清", "单钓将", "不求人"],

    "清幺九": ["碰碰和", "全带幺", "幺九刻", "无字"],
    "小四喜": ["三风刻"],
    "小三元": ["双箭刻", "箭刻"],
    "字一色": ["碰碰和", "全带幺", "幺九刻", "缺一门", "无字"],
    "四暗刻": ["碰碰和", "门前清", "三暗刻", "双暗刻"],
    "一色双龙会": ["清一色", "平和", "一般高", "老少副", "喜相逢"],

    "一色四同顺": ["一色三同顺", "一般高", "四归一"],
    "一色四节高": ["一色三节高", "碰碰和"],

    "一色四步高": ["一色三步高", "连六", "老少副"],
    "三杠": ["双明杠", "双暗杠"],
    "混幺九": ["碰碰和", "全带幺", "幺九刻"],

    "七对": ["门前清", "单钓将"],
    "七星不靠": ["全不靠", "五门齐", "门前清", "不求人"],
    "全双刻": ["碰碰和", "断幺"],
    "清一色": ["无字", "缺一门"],
    "一色三同顺": ["一般高"],
    "全大": ["无字"],
    "全中": ["无字", "断幺"],
    "全小": ["无字"],

    "清龙": ["连六", "老少副"],
    "三色双龙会": ["喜相逢", "老少副", "无字", "平和"],
    "一色三步高": ["连六", "老少副"],
    "全带五": ["断幺", "无字"],
    "三同刻": ["双同刻"],
    "三暗刻": ["双暗刻"],

    "全不靠": ["五门齐", "门前清", "不求人"],
    "大于五": ["无字"],
    "小于五": ["无字"],

    "推不倒": ["缺一门"],
    "三色三同顺": ["喜相逢"],
    "三色三节高": ["双同刻"],
    "妙手回春": ["自摸"],
    "杠上开花": ["自摸"],
    "抢杠和": ["和绝张"],

    "混一色": ["缺一门"],
    "全求人": ["单钓将", "门前清"],
    "双暗杠": ["暗杠"],
    "双箭刻": ["箭刻"],

    "不求人": ["自摸", "门前清"],
    "双明杠": ["明杠"],
]

// MARK: - 一次命中

private struct FanHit {
    let name: String
    var count: Int = 1
}

private func points(_ name: String) -> Int { mcrFanPoints[name] ?? 0 }

/// 应用排除表并折算成 FanItem 列表 + 总分
private func mcrFinalize(_ hits: [FanHit], flowers: Int) -> MCRScore {
    var merged: [String: Int] = [:]
    var order: [String] = []
    for h in hits where h.count > 0 {
        if merged[h.name] == nil { order.append(h.name) }
        merged[h.name, default: 0] += h.count
    }

    // 不可重复原则：按原始命中集合一次性删除被包含的低番型
    let present = Set(merged.keys)
    var removed = Set<String>()
    for name in present {
        for victim in mcrFanExcludes[name] ?? [] where victim != name {
            removed.insert(victim)
        }
    }
    for name in removed { merged[name] = nil }
    order.removeAll { merged[$0] == nil }

    // 无番和：除花牌、自摸外没有任何番型
    let coreTotal = order.reduce(0) { sum, name in
        name == "自摸" ? sum : sum + points(name) * (merged[name] ?? 0)
    }
    if coreTotal == 0 {
        order.insert("无番和", at: 0)
        merged["无番和"] = 1
    }

    var items: [FanItem] = order.map { name in
        let n = merged[name] ?? 0
        return FanItem(name: name, fan: points(name) * n, count: n)
    }
    let scoringPoints = items.reduce(0) { $0 + $1.fan }
    if flowers > 0 {
        items.append(FanItem(name: "花牌", fan: points("花牌") * flowers, count: flowers))
    }
    return MCRScore(
        items: items,
        totalPoints: scoringPoints + points("花牌") * flowers,
        scoringPoints: scoringPoints
    )
}

// MARK: - 拆解

/// 把副露转成面子
func mcrMeldSets(_ melds: [Meld]) -> [MCRSet] {
    melds.compactMap { m in
        let i = m.card.mcrIndex
        guard i >= 0 else { return nil }
        switch m.kind {
        case .chow: return MCRSet(kind: .chow, tile: i, concealed: false, fromMeld: true)
        case .pong: return MCRSet(kind: .pung, tile: i, concealed: false, fromMeld: true)
        case .exposedKong: return MCRSet(kind: .kong, tile: i, concealed: false, fromMeld: true)
        case .concealedKong: return MCRSet(kind: .kong, tile: i, concealed: true, fromMeld: true)
        }
    }
}

/// 暗牌拆解结果：1 将 + 若干手内面子
struct MCRDecomposition {
    var pair: MCRSet
    var handSets: [MCRSet]
}

private func enumerateHandSets(
    _ c: inout [Int], _ acc: inout [MCRSet], _ need: Int, _ out: inout [[MCRSet]]
) {
    if acc.count == need {
        if c.allSatisfy({ $0 == 0 }) { out.append(acc) }
        return
    }
    guard let i = c.firstIndex(where: { $0 > 0 }) else { return }
    if c[i] >= 3 {
        c[i] -= 3
        acc.append(MCRSet(kind: .pung, tile: i, concealed: true, fromMeld: false))
        enumerateHandSets(&c, &acc, need, &out)
        acc.removeLast(); c[i] += 3
    }
    if mcrCanStartChow(i), c[i + 1] > 0, c[i + 2] > 0 {
        c[i] -= 1; c[i + 1] -= 1; c[i + 2] -= 1
        acc.append(MCRSet(kind: .chow, tile: i, concealed: true, fromMeld: false))
        enumerateHandSets(&c, &acc, need, &out)
        acc.removeLast()
        c[i] += 1; c[i + 1] += 1; c[i + 2] += 1
    }
}

/// 暗牌的全部「1 将 + n 面子」拆解
func mcrDecompose(concealed freq: [Int], meldCount: Int) -> [MCRDecomposition] {
    let need = 4 - meldCount
    guard need >= 0 else { return [] }
    var out: [MCRDecomposition] = []
    var seen = Set<String>()
    for p in 0..<mcrTileKinds where freq[p] >= 2 {
        var c = freq
        c[p] -= 2
        var acc: [MCRSet] = []
        var sets: [[MCRSet]] = []
        enumerateHandSets(&c, &acc, need, &sets)
        for s in sets {
            let key = "\(p)|" + s.map { "\($0.kind)\($0.tile)" }.sorted().joined(separator: ",")
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(MCRDecomposition(
                pair: MCRSet(kind: .pair, tile: p, concealed: true, fromMeld: false),
                handSets: s
            ))
        }
    }
    return out
}

// MARK: - 整手牌属性判定

private struct TileStats {
    let freq: [Int]
    let present: [Int]
    let numberedSuits: Set<Int>
    let hasHonor: Bool
    let hasWind: Bool
    let hasDragon: Bool

    init(_ freq: [Int]) {
        self.freq = freq
        let p = (0..<mcrTileKinds).filter { freq[$0] > 0 }
        present = p
        numberedSuits = Set(p.filter { $0 < 27 }.map { $0 / 9 })
        hasHonor = p.contains { mcrIsHonor($0) }
        hasWind = p.contains { mcrIsWind($0) }
        hasDragon = p.contains { mcrIsDragon($0) }
    }

    func allRanksIn(_ set: Set<Int>) -> Bool {
        !hasHonor && present.allSatisfy { set.contains(mcrRankOf($0)) }
    }
}

private let mcrGreenTiles: Set<Int> = [19, 20, 21, 23, 25, 32]        // 2/3/4/6/8 条 + 发
private let mcrReversibleTiles: Set<Int> = [
    9, 10, 11, 12, 13, 16, 17,      // 1/2/3/4/5/8/9 筒
    19, 21, 22, 23, 25, 26,         // 2/4/5/6/8/9 条
    33,                              // 白
]

/// 整手牌层面的番（与拆解方式无关的部分）
private func mcrWholeHandFan(_ stats: TileStats) -> [FanHit] {
    var hits: [FanHit] = []
    let allHonor = stats.present.allSatisfy { mcrIsHonor($0) }

    if allHonor {
        hits.append(FanHit(name: "字一色"))
    } else if stats.numberedSuits.count == 1 {
        hits.append(FanHit(name: stats.hasHonor ? "混一色" : "清一色"))
    }
    if stats.numberedSuits.count == 2 { hits.append(FanHit(name: "缺一门")) }
    if !stats.hasHonor { hits.append(FanHit(name: "无字")) }
    if stats.numberedSuits.count == 3, stats.hasWind, stats.hasDragon {
        hits.append(FanHit(name: "五门齐"))
    }
    if stats.present.allSatisfy({ !mcrIsTerminalOrHonor($0) }) { hits.append(FanHit(name: "断幺")) }
    if Set(stats.present).isSubset(of: mcrGreenTiles) { hits.append(FanHit(name: "绿一色")) }
    if Set(stats.present).isSubset(of: mcrReversibleTiles) { hits.append(FanHit(name: "推不倒")) }
    if stats.allRanksIn([7, 8, 9]) { hits.append(FanHit(name: "全大")) }
    if stats.allRanksIn([4, 5, 6]) { hits.append(FanHit(name: "全中")) }
    if stats.allRanksIn([1, 2, 3]) { hits.append(FanHit(name: "全小")) }
    if stats.allRanksIn([6, 7, 8, 9]) { hits.append(FanHit(name: "大于五")) }
    if stats.allRanksIn([1, 2, 3, 4]) { hits.append(FanHit(name: "小于五")) }
    return hits
}

/// 九莲宝灯：门清、一门数牌、1112345678999 + 任意一张
private func mcrIsNineGates(_ freq: [Int], melds: [Meld]) -> Bool {
    guard melds.isEmpty, freq.reduce(0, +) == 14 else { return false }
    let suits = Set((0..<27).filter { freq[$0] > 0 }.map { $0 / 9 })
    guard suits.count == 1, (27..<34).allSatisfy({ freq[$0] == 0 }) else { return false }
    let base = suits.first! * 9
    let pattern = [3, 1, 1, 1, 1, 1, 1, 1, 3]
    var extra = 0
    for r in 0..<9 {
        let d = freq[base + r] - pattern[r]
        if d < 0 { return false }
        extra += d
    }
    return extra == 1
}

// MARK: - 面子结构番：集合划分

/// {0,1,2,3} 的全部集合划分（Bell(4) = 15）
private let mcrPartitionsOf4: [[[Int]]] = {
    var result: [[[Int]]] = []
    func build(_ i: Int, _ blocks: [[Int]]) {
        if i == 4 { result.append(blocks); return }
        for b in blocks.indices {
            var next = blocks
            next[b].append(i)
            build(i + 1, next)
        }
        build(i + 1, blocks + [[i]])
    }
    build(0, [])
    return result
}()

private func mcrBestFanForBlock(_ block: [MCRSet], pair: MCRSet) -> (String, Int)? {
    var best: (String, Int)?
    func offer(_ name: String) {
        let p = points(name)
        if best == nil || p > best!.1 { best = (name, p) }
    }

    let chows = block.filter { $0.kind == .chow }
    let pungs = block.filter { $0.isPungLike }

    switch block.count {
    case 4:
        if chows.count == 4 {
            let suits = Set(chows.map(\.suit))
            let starts = chows.map(\.rank).sorted()
            if suits.count == 1 {
                if starts == [1, 1, 7, 7], pair.suit == chows[0].suit, pair.rank == 5 {
                    offer("一色双龙会")
                }
                if Set(starts).count == 1 { offer("一色四同顺") }
                let d = starts[1] - starts[0]
                if (d == 1 || d == 2),
                   starts[2] - starts[1] == d, starts[3] - starts[2] == d {
                    offer("一色四步高")
                }
            } else if suits.count == 2 {
                // 三色双龙会：两门各 123+789，将是第三门的 5
                var ok = true
                for s in suits {
                    let inSuit = chows.filter { $0.suit == s }.map(\.rank).sorted()
                    if inSuit != [1, 7] { ok = false }
                }
                if ok, pair.rank == 5, mcrSuitOf(pair.tile) < 3, !suits.contains(pair.suit) {
                    offer("三色双龙会")
                }
            }
        }
        if pungs.count == 4 {
            let suits = Set(pungs.map(\.suit))
            let ranks = pungs.map(\.rank).sorted()
            if suits.count == 1, suits.first != 3,
               ranks[1] == ranks[0] + 1, ranks[2] == ranks[0] + 2, ranks[3] == ranks[0] + 3 {
                offer("一色四节高")
            }
        }
    case 3:
        if chows.count == 3 {
            let suits = Set(chows.map(\.suit))
            let starts = chows.map(\.rank).sorted()
            if suits.count == 1 {
                if Set(starts).count == 1 { offer("一色三同顺") }
                if starts == [1, 4, 7] { offer("清龙") }
                let d = starts[1] - starts[0]
                if (d == 1 || d == 2), starts[2] - starts[1] == d { offer("一色三步高") }
            } else if suits.count == 3 {
                if Set(starts).count == 1 { offer("三色三同顺") }
                if starts == [1, 4, 7] { offer("花龙") }
                if starts[1] == starts[0] + 1, starts[2] == starts[0] + 2 { offer("三色三步高") }
            }
        }
        if pungs.count == 3 {
            let suits = Set(pungs.map(\.suit))
            let ranks = pungs.map(\.rank).sorted()
            if suits.count == 1, suits.first != 3,
               ranks[1] == ranks[0] + 1, ranks[2] == ranks[0] + 2 {
                offer("一色三节高")
            }
            if suits.count == 3, !suits.contains(3) {
                if Set(ranks).count == 1 { offer("三同刻") }
                if ranks[1] == ranks[0] + 1, ranks[2] == ranks[0] + 2 { offer("三色三节高") }
            }
        }
    case 2:
        if pungs.count == 2, pungs[0].suit != pungs[1].suit,
           !pungs.contains(where: { $0.suit == 3 }), pungs[0].rank == pungs[1].rank {
            offer("双同刻")
        }
        if chows.count == 2 {
            let a = chows[0], b = chows[1]
            if a.suit == b.suit {
                if a.rank == b.rank { offer("一般高") }
                if abs(a.rank - b.rank) == 3 { offer("连六") }
                if Set([a.rank, b.rank]) == Set([1, 7]) { offer("老少副") }
            } else if a.rank == b.rank {
                offer("喜相逢")
            }
        }
    default:
        break
    }
    return best
}

/// 面子结构番：取「总分最高的集合划分」，实现不可拆分 / 套算一次 / 就高不就低
private func mcrStructureFan(_ sets: [MCRSet], pair: MCRSet) -> [FanHit] {
    guard sets.count == 4 else { return [] }
    var bestTotal = -1
    var bestHits: [FanHit] = []
    for partition in mcrPartitionsOf4 {
        var total = 0
        var hits: [FanHit] = []
        for block in partition {
            let blockSets = block.map { sets[$0] }
            if let (name, p) = mcrBestFanForBlock(blockSets, pair: pair) {
                total += p
                hits.append(FanHit(name: name))
            }
        }
        if total > bestTotal {
            bestTotal = total
            bestHits = hits
        }
    }
    return bestHits
}

// MARK: - 字牌番 / 暗刻番 / 杠番

private func mcrHonorFan(_ sets: [MCRSet], pair: MCRSet, ctx: MCRContext) -> [FanHit] {
    var hits: [FanHit] = []
    let pungs = sets.filter { $0.isPungLike }
    let windPungs = pungs.filter { mcrIsWind($0.tile) }
    let dragonPungs = pungs.filter { mcrIsDragon($0.tile) }

    if windPungs.count == 4 { hits.append(FanHit(name: "大四喜")) }
    else if windPungs.count == 3 {
        hits.append(FanHit(name: mcrIsWind(pair.tile) ? "小四喜" : "三风刻"))
    }
    if dragonPungs.count == 3 { hits.append(FanHit(name: "大三元")) }
    else if dragonPungs.count == 2 {
        if mcrIsDragon(pair.tile) { hits.append(FanHit(name: "小三元")) }
        hits.append(FanHit(name: "双箭刻"))
    }
    if !dragonPungs.isEmpty { hits.append(FanHit(name: "箭刻", count: dragonPungs.count)) }
    if windPungs.contains(where: { $0.tile == 27 + ctx.prevalentWind }) {
        hits.append(FanHit(name: "圈风刻"))
    }
    if windPungs.contains(where: { $0.tile == 27 + ctx.seatWind }) {
        hits.append(FanHit(name: "门风刻"))
    }
    let yaojiuPungs = pungs.filter { mcrIsTerminal($0.tile) || mcrIsWind($0.tile) }.count
    if yaojiuPungs > 0 { hits.append(FanHit(name: "幺九刻", count: yaojiuPungs)) }
    return hits
}

/// 暗刻 / 杠。`pungConcealed` 已把「点炮成刻」降为明刻。
private func mcrConcealmentFan(_ sets: [MCRSet]) -> [FanHit] {
    var hits: [FanHit] = []
    let concealedPungs = sets.filter { $0.isPungLike && $0.concealed }.count
    switch concealedPungs {
    case 4: hits.append(FanHit(name: "四暗刻"))
    case 3: hits.append(FanHit(name: "三暗刻"))
    case 2: hits.append(FanHit(name: "双暗刻"))
    default: break
    }

    let kongs = sets.filter { $0.kind == .kong }
    let exposed = kongs.filter { !$0.concealed }.count
    let hidden = kongs.count - exposed
    switch kongs.count {
    case 4:
        hits.append(FanHit(name: "四杠"))
    case 3:
        hits.append(FanHit(name: "三杠"))
        if exposed > 0 { hits.append(FanHit(name: "明杠", count: exposed)) }
        if hidden > 0 { hits.append(FanHit(name: "暗杠", count: hidden)) }
    default:
        if exposed == 2 { hits.append(FanHit(name: "双明杠")) }
        else if exposed == 1 { hits.append(FanHit(name: "明杠")) }
        if hidden == 2 { hits.append(FanHit(name: "双暗杠")) }
        else if hidden == 1 { hits.append(FanHit(name: "暗杠")) }
    }
    return hits
}

// MARK: - 面子构成番（碰碰和 / 平和 / 全带幺 …）

private func mcrCompositionFan(_ sets: [MCRSet], pair: MCRSet, stats: TileStats) -> [FanHit] {
    var hits: [FanHit] = []
    let all = sets + [pair]
    let allPungs = sets.allSatisfy { $0.isPungLike }
    let allChows = sets.allSatisfy { $0.kind == .chow }

    if allPungs { hits.append(FanHit(name: "碰碰和")) }
    if allChows, !mcrIsHonor(pair.tile) { hits.append(FanHit(name: "平和")) }

    if all.allSatisfy({ $0.tiles.contains(where: mcrIsTerminalOrHonor) }) {
        hits.append(FanHit(name: "全带幺"))
    }
    if all.allSatisfy({ $0.tiles.contains { !mcrIsHonor($0) && mcrRankOf($0) == 5 } }) {
        hits.append(FanHit(name: "全带五"))
    }
    if allPungs {
        let tiles = stats.present
        if tiles.allSatisfy({ mcrIsTerminal($0) }) { hits.append(FanHit(name: "清幺九")) }
        else if tiles.allSatisfy({ mcrIsTerminalOrHonor($0) }) { hits.append(FanHit(name: "混幺九")) }
        if tiles.allSatisfy({ !mcrIsHonor($0) && mcrRankOf($0) % 2 == 0 }) {
            hits.append(FanHit(name: "全双刻"))
        }
    }
    // 四归一：某张牌 4 张齐，其中 3 张在一副面子里、另 1 张在别处（成杠不算）
    let kongTiles = Set(sets.filter { $0.kind == .kong }.map(\.tile))
    var quads = 0
    for i in 0..<mcrTileKinds where stats.freq[i] == 4 && !kongTiles.contains(i) { quads += 1 }
    if quads > 0 { hits.append(FanHit(name: "四归一", count: quads)) }
    return hits
}

// MARK: - 场景番

private func mcrSituationalFan(
    ctx: MCRContext, fullyConcealed: Bool, allMelded: Bool, singleWait: Bool
) -> [FanHit] {
    var hits: [FanHit] = []
    if ctx.selfDrawn {
        hits.append(FanHit(name: "自摸"))
        if fullyConcealed { hits.append(FanHit(name: "不求人")) }
        if ctx.kongBloom { hits.append(FanHit(name: "杠上开花")) }
        if ctx.lastTileDraw { hits.append(FanHit(name: "妙手回春")) }
    } else {
        if fullyConcealed { hits.append(FanHit(name: "门前清")) }
        if allMelded && singleWait { hits.append(FanHit(name: "全求人")) }
        if ctx.lastDiscard { hits.append(FanHit(name: "海底捞月")) }
        if ctx.robbingKong { hits.append(FanHit(name: "抢杠和")) }
    }
    if ctx.lastTileOfKind { hits.append(FanHit(name: "和绝张")) }
    return hits
}

/// 和牌张落在哪副面子上 → 边张 / 坎张 / 单钓将（互斥，最多一个）
private func mcrWaitFan(winSet: MCRSet, winningTile: Int) -> [FanHit] {
    guard winningTile >= 0 else { return [] }
    switch winSet.kind {
    case .pair:
        return [FanHit(name: "单钓将")]
    case .chow:
        let s = winSet.tile
        if winningTile == s + 1 { return [FanHit(name: "坎张")] }
        if winningTile == s + 2, s % 9 == 0 { return [FanHit(name: "边张")] }
        if winningTile == s, s % 9 == 6 { return [FanHit(name: "边张")] }
        return []
    default:
        return []
    }
}

// MARK: - 主入口

/// 对一副完整的国标和牌算番。
/// - Parameters:
///   - concealed: 暗牌频率数组（长度 34，含所和那张，不含花牌）
///   - melds: 副露（吃/碰/明杠/暗杠）
///   - context: 和牌场景（自摸/点炮、圈风门风、场景番、花牌数）
func scoreMCRHand(concealed: [Int], melds: [Meld], context: MCRContext) -> MCRScore {
    var full = concealed
    let meldFreq = meldsToFrequency34(melds)
    for i in 0..<mcrTileKinds { full[i] += meldFreq[i] }
    let stats = TileStats(full)

    // 门清：没有吃 / 碰 / 明杠（暗杠可）
    let fullyConcealed = melds.allSatisfy { $0.kind == .concealedKong }
    let allMelded = melds.count == 4 && melds.allSatisfy { $0.kind != .concealedKong }
    let flowers = context.flowers

    var best: MCRScore?
    func consider(_ hits: [FanHit]) {
        let s = mcrFinalize(hits, flowers: flowers)
        if best == nil || s.scoringPoints > best!.scoringPoints { best = s }
    }

    let concealedSum = concealed.reduce(0, +)

    // ── 特殊牌型（门清、暗牌恰 14 张）────────────────────────────
    if melds.isEmpty, concealedSum == 14 {
        // 十三幺
        if mcrIsThirteenOrphans(full) {
            var hits: [FanHit] = [FanHit(name: "十三幺")]
            hits += mcrWholeHandFan(stats)
            hits += mcrSituationalFan(ctx: context, fullyConcealed: true,
                                      allMelded: false, singleWait: true)
            consider(hits)
        }
        // 七对 / 连七对
        if mcrIsSevenPairs(full) {
            var hits: [FanHit] = [FanHit(name: mcrIsSevenShiftedPairs(full) ? "连七对" : "七对")]
            hits += mcrWholeHandFan(stats)
            hits += mcrSituationalFan(ctx: context, fullyConcealed: true,
                                      allMelded: false, singleWait: true)
            consider(hits)
        }
        // 全不靠 / 七星不靠（可与组合龙叠加）
        if mcrIsKnittedNoSets(full) {
            var hits: [FanHit] = [
                FanHit(name: mcrIsSevenStarsKnitted(full) ? "七星不靠" : "全不靠")
            ]
            if mcrHasKnittedStraight(full) { hits.append(FanHit(name: "组合龙")) }
            hits += mcrWholeHandFan(stats)
            hits += mcrSituationalFan(ctx: context, fullyConcealed: true,
                                      allMelded: false, singleWait: false)
            consider(hits)
        }
        // 九莲宝灯
        if mcrIsNineGates(full, melds: melds) {
            var hits: [FanHit] = [FanHit(name: "九莲宝灯")]
            hits += mcrWholeHandFan(stats)
            hits += mcrSituationalFan(ctx: context, fullyConcealed: true,
                                      allMelded: false, singleWait: false)
            consider(hits)
        }
    }

    // ── 组合龙型：9 张组合龙在手 + 1 面子（可副露）+ 1 将 ──────────
    if melds.count <= 1, mcrIsKnittedStraightForm(concealed, meldCount: melds.count) {
        var hits: [FanHit] = [FanHit(name: "组合龙")]
        hits += mcrWholeHandFan(stats)
        hits += mcrSituationalFan(ctx: context, fullyConcealed: fullyConcealed,
                                  allMelded: false, singleWait: false)
        consider(hits)
    }

    // ── 标准型：枚举所有拆解 × 和牌张归属 ────────────────────────
    let meldSets = mcrMeldSets(melds)
    for decomp in mcrDecompose(concealed: concealed, meldCount: melds.count) {
        let handAll = decomp.handSets + [decomp.pair]
        // 和牌张可能落在多副手内面子上，逐一试，取最优
        var winCandidates: [Int] = []
        if context.winningTile >= 0 {
            for (i, s) in handAll.enumerated() where s.tiles.contains(context.winningTile) {
                winCandidates.append(i)
            }
        }
        if winCandidates.isEmpty { winCandidates = [-1] }

        for winIdx in winCandidates {
            var sets = decomp.handSets + meldSets
            let pair = decomp.pair
            // 点炮成刻算明刻（只影响暗刻类番，门前清不受影响）
            if !context.selfDrawn, winIdx >= 0, winIdx < decomp.handSets.count,
               sets[winIdx].isPungLike {
                sets[winIdx].concealed = false
            }
            guard sets.count == 4 else { continue }

            var hits: [FanHit] = []
            hits += mcrWholeHandFan(stats)
            if mcrIsNineGates(full, melds: melds) { hits.append(FanHit(name: "九莲宝灯")) }
            hits += mcrStructureFan(sets, pair: pair)
            hits += mcrHonorFan(sets, pair: pair, ctx: context)
            hits += mcrConcealmentFan(sets)
            hits += mcrCompositionFan(sets, pair: pair, stats: stats)

            let winSet: MCRSet? = winIdx >= 0 ? handAll[winIdx] : nil
            let singleWait = winSet?.kind == .pair
            if let w = winSet { hits += mcrWaitFan(winSet: w, winningTile: context.winningTile) }
            hits += mcrSituationalFan(ctx: context, fullyConcealed: fullyConcealed,
                                      allMelded: allMelded, singleWait: singleWait)
            consider(hits)
        }
    }

    return best ?? mcrFinalize([], flowers: flowers)
}

// MARK: - 打牌建议评估（国标）

/// 一个国标候选弃牌的完整评估
struct MCREvaluatedDiscard: Identifiable {
    var id: UUID { suggestion.id }
    let suggestion: DiscardSuggestion
    let waitScores: [(card: MahjongCard, score: MCRScore)]
    /// 听牌里能达到的最高分；未听牌 / 空听 = -1
    let maxPoints: Int
}

/// 给国标打牌建议补上「弃后听牌 + 各自番分」，按「最高分降序 → 向听升序 → 进张降序」重排。
/// 分数按点炮基线（不含自摸等场景番）。
func mcrEvaluateDiscards(
    _ suggestions: [DiscardSuggestion],
    cards: [MahjongCard],
    melds: [Meld],
    settings: RuleSettings,
    flowers: Int = 0
) -> [MCREvaluatedDiscard] {
    let baseFreq = handToFrequency34(cards)

    let evaluated = suggestions.map { s -> MCREvaluatedDiscard in
        guard s.resultingShanten == 0, !s.acceptance.isEmpty else {
            return MCREvaluatedDiscard(suggestion: s, waitScores: [], maxPoints: -1)
        }
        var afterDiscard = baseFreq
        let di = s.discard.mcrIndex
        guard di >= 0 else { return MCREvaluatedDiscard(suggestion: s, waitScores: [], maxPoints: -1) }
        afterDiscard[di] -= 1
        let waitScores = s.acceptance.map { wait -> (card: MahjongCard, score: MCRScore) in
            var winning = afterDiscard
            winning[wait.mcrIndex] += 1
            let ctx = MCRContext(
                selfDrawn: false,
                winningTile: wait.mcrIndex,
                prevalentWind: settings.mcrPrevalentWind,
                seatWind: settings.mcrSeatWind,
                flowers: flowers
            )
            return (card: wait, score: scoreMCRHand(concealed: winning, melds: melds, context: ctx))
        }
        return MCREvaluatedDiscard(
            suggestion: s,
            waitScores: waitScores,
            maxPoints: waitScores.map { $0.score.totalPoints }.max() ?? -1
        )
    }

    return evaluated.sorted { a, b in
        if a.maxPoints != b.maxPoints { return a.maxPoints > b.maxPoints }
        if a.suggestion.resultingShanten != b.suggestion.resultingShanten {
            return a.suggestion.resultingShanten < b.suggestion.resultingShanten
        }
        if a.suggestion.acceptanceCount != b.suggestion.acceptanceCount {
            return a.suggestion.acceptanceCount > b.suggestion.acceptanceCount
        }
        return mcrCardOrder(a.suggestion.discard, b.suggestion.discard)
    }
}
