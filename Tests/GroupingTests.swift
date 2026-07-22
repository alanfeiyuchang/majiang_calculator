//
//  GroupingTests.swift
//  拍照识别空间聚类断言（groupTiles，独立可运行，不进 App 编译目标）。
//  运行：./Tests/run.sh
//  用合成坐标构造「手牌 + 副露」布局，验证碰/明杠/暗杠/纯手牌的分组正确。
//

// 一张牌宽 10、高 14，行内相邻牌间隔 1（紧挨）；簇之间用大间隔（≥ 8）分开。
private let tileW: CGFloat = 10
private let tileH: CGFloat = 14

/// 从 x 起点顺次摆放同一行的若干牌（间隔 1），返回牌盒与下一个可用 x
private func lay(_ cards: [MahjongCard], from x0: CGFloat, cy: CGFloat = 0) -> (boxes: [TileBox], next: CGFloat) {
    var x = x0
    var out: [TileBox] = []
    for c in cards {
        out.append(TileBox(minX: x, maxX: x + tileW, cy: cy, height: tileH, card: c))
        x += tileW + 1
    }
    return (out, x)
}

private func c(_ s: String) -> MahjongCard {
    let rank = Int(String(s.first!))!
    let suit: MahjongCard.Suit = s.last == "m" ? .wan : (s.last == "p" ? .tong : .tiao)
    return MahjongCard(suit: suit, rank: rank)
}
private func cards(_ ss: [String]) -> [MahjongCard] { ss.map(c) }
private func meldDesc(_ m: Meld) -> String { "\(m.kind.rawValue)\(m.card.displayText)" }

var gFails = 0
func gcheck(_ cond: Bool, _ label: String, _ detail: @autoclosure () -> String = "") {
    if cond { print("  ✓ \(label)") }
    else { gFails += 1; print("  ✗ FAIL \(label)  \(detail())") }
}

print("— 拍照分组 groupTiles —")

// G1 纯手牌（无间隔断开）→ 全部手牌，无副露
do {
    let (boxes, _) = lay(cards(["1m","2m","3m","4m","5m","6m","7m","8m","9m","1p","2p","3p","5p"]), from: 0)
    let r = groupTiles(boxes)
    gcheck(r.hand.count == 13 && r.melds.isEmpty && !r.guessedConcealedKong, "G1 纯手牌13张无副露",
           "hand=\(r.hand.count) melds=\(r.melds.map(meldDesc))")
}

// G2 手牌 + 碰（3 张同牌，大间隔分开）
do {
    var (boxes, x) = lay(cards(["1m","2m","3m","4m","5m","6m","7m","8m","9m","2p"]), from: 0)
    x += 8 * tileW                                   // 大空档
    let pong = lay(cards(["5p","5p","5p"]), from: x)
    boxes += pong.boxes
    let r = groupTiles(boxes)
    gcheck(r.hand.count == 10 && r.melds.count == 1
           && meldDesc(r.melds[0]) == "碰五筒" && !r.guessedConcealedKong, "G2 手牌+碰5筒",
           "hand=\(r.hand.count) melds=\(r.melds.map(meldDesc))")
}

// G3 手牌 + 明杠（4 张同牌）
do {
    var (boxes, x) = lay(cards(["1m","2m","3m","4m","5m","6m","7m","2p"]), from: 0)
    x += 8 * tileW
    let kong = lay(cards(["9p","9p","9p","9p"]), from: x)
    boxes += kong.boxes
    let r = groupTiles(boxes)
    gcheck(r.melds.count == 1 && meldDesc(r.melds[0]) == "明杠九筒" && !r.guessedConcealedKong,
           "G3 手牌+明杠9筒", "melds=\(r.melds.map(meldDesc))")
}

// G4 手牌 + 暗杠（只露一张 → 孤立单张）
do {
    var (boxes, x) = lay(cards(["1m","2m","3m","4m","5m","6m","7m","2p"]), from: 0)
    x += 8 * tileW
    let kong = lay(cards(["3p"]), from: x)           // 只露的那张明牌
    boxes += kong.boxes
    let r = groupTiles(boxes)
    gcheck(r.melds.count == 1 && meldDesc(r.melds[0]) == "暗杠三筒" && r.guessedConcealedKong,
           "G4 手牌+暗杠3筒(单张)", "melds=\(r.melds.map(meldDesc))")
}

// G5 手牌 + 两副露（碰 + 暗杠），副露在下面一行
do {
    let (hand, _) = lay(cards(["1m","2m","3m","4m","5m","6m","7m"]), from: 0, cy: 0)
    var (pong, x2) = lay(cards(["8p","8p","8p"]), from: 0, cy: 40)   // 下一行
    x2 += 8 * tileW
    let kong = lay(cards(["2m"]), from: x2, cy: 40)
    let r = groupTiles(hand + pong + kong.boxes)
    gcheck(r.hand.count == 7 && r.melds.count == 2
           && r.melds.contains { meldDesc($0) == "碰八筒" }
           && r.melds.contains { meldDesc($0) == "暗杠二万" }
           && r.guessedConcealedKong, "G5 两行：手牌+碰+暗杠",
           "hand=\(r.hand.count) melds=\(r.melds.map(meldDesc))")
}

// G6 金钩钓布局：手牌只剩单对 + 4 副露（此处不追求语义，仅验证分组不误判）
do {
    var (boxes, x) = lay(cards(["5m","5m"]), from: 0)   // 手里一对（最大簇之一）
    // 4 个碰，各自间隔
    for tile in ["1m","2m","3m","4m"] {
        x += 8 * tileW
        let p = lay(cards([tile, tile, tile]), from: x)
        boxes += p.boxes
        x = p.next
    }
    let r = groupTiles(boxes)
    // 4 个碰应被识别为副露；手牌为那一对（或某个 3 张簇被当手牌——取决于最大簇）
    gcheck(r.melds.filter { $0.kind == .pong }.count >= 3, "G6 金钩钓4碰多数识别为碰",
           "melds=\(r.melds.map(meldDesc))")
}

// G7 认不准的小簇（2 张不同牌）→ 并回手牌，不误判为副露
do {
    var (boxes, x) = lay(cards(["1m","2m","3m","4m","5m","6m","7m","8m"]), from: 0)
    x += 8 * tileW
    let stray = lay(cards(["2p","4p"]), from: x)       // 2 张不同 → 不是碰/杠
    boxes += stray.boxes
    let r = groupTiles(boxes)
    gcheck(r.melds.isEmpty && r.hand.count == 10, "G7 两张不同的小簇并回手牌",
           "hand=\(r.hand.count) melds=\(r.melds.map(meldDesc))")
}

print(gFails == 0 ? "\n分组全部通过 ✅" : "\n❌ 分组 \(gFails) 个失败")
