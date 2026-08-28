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

// G4 手牌 + 暗杠（只露一张 → 孤立单张）。手牌 10 张 + 暗杠 3 张名额 = 13，张数成立，
//    「猜暗杠」才会被采纳——这正是现在判定暗杠的依据。
do {
    var (boxes, x) = lay(cards(["1m","2m","3m","4m","5m","6m","7m","2p","3p","4p"]), from: 0)
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

// G8 两组碰紧挨着没有空隙 → 按相邻同牌切段，拆成两个碰
do {
    var (boxes, x) = lay(cards(["1m","2m","3m","4m","5m","6m","7m","8m","9m","2p"]), from: 0)
    x += 8 * tileW
    let two = lay(cards(["5p","5p","5p","8p","8p","8p"]), from: x)
    boxes += two.boxes
    let r = groupTiles(boxes)
    gcheck(r.hand.count == 10 && r.melds.count == 2
           && r.melds.contains { meldDesc($0) == "碰五筒" }
           && r.melds.contains { meldDesc($0) == "碰八筒" }, "G8 紧挨双碰拆成两组",
           "hand=\(r.hand.count) melds=\(r.melds.map(meldDesc))")
}

// G9 碰 + 明杠紧挨（3+4 张）
do {
    var (boxes, x) = lay(cards(["1m","2m","3m","4m","5m","6m","7m","8m","9m","2p"]), from: 0)
    x += 8 * tileW
    let mix = lay(cards(["5p","5p","5p","9p","9p","9p","9p"]), from: x)
    boxes += mix.boxes
    let r = groupTiles(boxes)
    gcheck(r.melds.count == 2
           && r.melds.contains { meldDesc($0) == "碰五筒" }
           && r.melds.contains { meldDesc($0) == "明杠九筒" }, "G9 碰+明杠紧挨拆分",
           "melds=\(r.melds.map(meldDesc))")
}

// G10 段里有 2 张同牌（认不准）→ 整簇并回手牌
do {
    var (boxes, x) = lay(cards(["1m","2m","3m","4m","5m","6m","7m","8m"]), from: 0)
    x += 8 * tileW
    let bad = lay(cards(["5p","5p","5p","6p","6p"]), from: x)   // [3][2]：2 张段认不准
    boxes += bad.boxes
    let r = groupTiles(boxes)
    gcheck(r.melds.isEmpty && r.hand.count == 13, "G10 含2张段整簇回手牌",
           "hand=\(r.hand.count) melds=\(r.melds.map(meldDesc))")
}

// G11 碰 + 暗杠明牌紧挨（3+1 张）
do {
    var (boxes, x) = lay(cards(["1m","2m","3m","4m","5m","6m","7m","8m"]), from: 0)
    x += 8 * tileW
    let mix = lay(cards(["7s","7s","7s","2m"]), from: x)
    boxes += mix.boxes
    let r = groupTiles(boxes)
    gcheck(r.melds.count == 2 && r.guessedConcealedKong
           && r.melds.contains { meldDesc($0) == "碰七条" }
           && r.melds.contains { meldDesc($0) == "暗杠二万" }, "G11 碰+暗杠明牌紧挨",
           "melds=\(r.melds.map(meldDesc))")
}

// G12 整桌入镜：自己的手牌（近、框大）+ 桌上一堆弃牌（远、框只有一半大）
//     → 弃牌被近景过滤剔除，不混进手牌
do {
    let (hand, _) = lay(cards(["1m","2m","3m","4m","5m","6m","7m","8m","9m","1p","2p","3p","5p"]),
                        from: 0, cy: 200)
    // 桌上 16 张弃牌：高度只有一半，位置在上方（离镜头远）
    var table: [TileBox] = []
    var tx: CGFloat = 0
    for i in 0..<16 {
        table.append(TileBox(minX: tx, maxX: tx + tileW / 2, cy: CGFloat(20 + (i / 8) * 10),
                             height: tileH / 2, card: c("7p")))
        tx += tileW / 2 + 1
        if i == 7 { tx = 0 }
    }
    let r = groupTiles(hand + table)
    // 契约：桌上的牌不会被静默丢弃（丢弃同样会吃掉平摊的碰/杠），
    // 而是并回手牌让张数对不上 → 由 hasValidTileCount 拦下并提示用户核对。
    // 手牌簇本身仍要选对：排在最前面的 13 张就是自己的牌。
    gcheck(Array(r.hand.prefix(13)) == cards(["1m","2m","3m","4m","5m","6m","7m","8m","9m","1p","2p","3p","5p"])
           && !r.hasValidTileCount,
           "G12 整桌入镜：手牌簇选对，多余的牌让张数对不上而被拦下",
           "hand=\(r.hand.count) valid=\(r.hasValidTileCount)")
}

// G13 桌上的牌比自己的手牌还多 → 仍以「近」为准，不会被张数压过去
do {
    let (hand, _) = lay(cards(["1m","2m","3m","4m","5m","6m","7m","8m","9m","1p"]), from: 0, cy: 200)
    var table: [TileBox] = []
    var tx: CGFloat = 0
    for _ in 0..<30 {
        table.append(TileBox(minX: tx, maxX: tx + tileW / 2, cy: 20,
                             height: tileH / 2, card: c("9s")))
        tx += tileW / 2 + 1
    }
    let r = groupTiles(hand + table)
    gcheck(Array(r.hand.prefix(10)) == cards(["1m","2m","3m","4m","5m","6m","7m","8m","9m","1p"])
           && !r.hasValidTileCount,
           "G13 远处 30 张多过手牌 10 张，手牌簇仍选对",
           "hand=\(r.hand.count) valid=\(r.hasValidTileCount)")
}

// G14 认不准的簇 → 并回手牌，绝不静默丢弃（丢弃会连带吃掉真实的碰/杠）
do {
    let (hand, _) = lay(cards(["1m","2m","3m","4m","5m","6m","7m","8m","9m","1p","2p","3p","5p"]),
                        from: 0, cy: 200)
    // 稍远一排的两张杂牌：高度 0.7 倍（过得了近景过滤），但不同排、大小对不上
    let stray = [TileBox(minX: 0, maxX: tileW * 0.7, cy: 100, height: tileH * 0.7, card: c("2p")),
                 TileBox(minX: tileW, maxX: tileW * 1.7, cy: 100, height: tileH * 0.7, card: c("4p"))]
    let r = groupTiles(hand + stray)
    gcheck(r.hand.count == 15 && r.melds.isEmpty && !r.hasValidTileCount,
           "G14 异排杂牌并回手牌，张数对不上被拦下",
           "hand=\(r.hand.count) valid=\(r.hasValidTileCount)")
}

// G14b 手牌摆成两排（大小相当、不同排）→ 合并成一副手牌，不丢弃
do {
    let (front, _) = lay(cards(["3m","5m","8m","8m","5p","6p","7p"]), from: 0, cy: 200)
    // 后排略小（0.88 倍，透视），另起一行
    var back: [TileBox] = []
    var bx: CGFloat = 0
    for card in cards(["2s","3s","4s","5s","6s","7s"]) {
        back.append(TileBox(minX: bx, maxX: bx + tileW * 0.88, cy: 140,
                            height: tileH * 0.88, card: card))
        bx += tileW * 0.88 + 1
    }
    let r = groupTiles(front + back)
    gcheck(r.hand.count == 13 && r.melds.isEmpty && r.hasValidTileCount,
           "G14b 两排手牌合并成 13 张", "hand=\(r.hand.count)")
}

// G14c 平摊在桌上的碰/杠被透视压扁（高度只有手牌的一半）→ 必须仍然识别成碰。
//      这是核心回归测试：任何「按大小丢框」的过滤都会先吃掉这一组。
do {
    let (hand, _) = lay(cards(["1m","2m","3m","4m","5m","6m","7m","8m","9m","2p"]), from: 0, cy: 200)
    // 副露：同宽、压扁一半（俯拍角度下平摊牌的典型压缩比），另起一行
    var pong: [TileBox] = []
    var px = 20 * tileW
    for card in cards(["5p","5p","5p"]) {
        pong.append(TileBox(minX: px, maxX: px + tileW, cy: 120,
                            height: tileH * 0.5, card: card))
        px += tileW + 1
    }
    let r = groupTiles(hand + pong)
    gcheck(r.hand.count == 10 && r.melds.count == 1 && meldDesc(r.melds[0]) == "碰五筒"
           && r.hasValidTileCount,
           "G14c 压扁一半的平摊碰仍识别为碰",
           "hand=\(r.hand.count) melds=\(r.melds.map(meldDesc))")
}

// G15 张数不变量：手牌 + 3×副露
do {
    var (boxes, x) = lay(cards(["1m","2m","3m","4m","5m","6m","7m","8m","9m","2p"]), from: 0)
    x += 8 * tileW
    boxes += lay(cards(["5p","5p","5p"]), from: x).boxes
    let r = groupTiles(boxes)
    gcheck(r.effectiveTileCount == 13 && r.hasValidTileCount, "G15 手牌10+碰1组=13 张合法",
           "effective=\(r.effectiveTileCount)")

    let (short, _) = lay(cards(["1m","2m","3m","4m","5m"]), from: 0)
    gcheck(!groupTiles(short).hasValidTileCount, "G15b 只识别到 5 张 → 张数不合法")
}

// G16 只拍自己的牌 → 13 张一张不少
do {
    let (boxes, _) = lay(cards(["1m","2m","3m","4m","5m","6m","7m","8m","9m","1p","2p","3p","5p"]), from: 0)
    let r = groupTiles(boxes)
    gcheck(r.hand.count == 13 && r.melds.isEmpty && r.hasValidTileCount,
           "G16 只拍自己的牌一张不少", "hand=\(r.hand.count)")
}

print("— 二次放大区域 zoomRegion —")

// Z1 牌只占画面一角 → 返回外扩区域，含所有框且不越界
do {
    let rects = [CGRect(x: 1000, y: 800, width: 60, height: 80),
                 CGRect(x: 1070, y: 800, width: 60, height: 80)]
    let size = CGSize(width: 4000, height: 3000)
    let region = zoomRegion(boxes: rects, imageSize: size)
    gcheck(region != nil && region!.contains(rects[0]) && region!.contains(rects[1])
           && region!.minX >= 0 && region!.minY >= 0
           && region!.maxX <= size.width && region!.maxY <= size.height,
           "Z1 一角的牌→外扩区域", "region=\(String(describing: region))")
}

// Z2 框已占满画面 → nil（放大无意义）
do {
    let big = [CGRect(x: 10, y: 10, width: 3900, height: 2900)]
    gcheck(zoomRegion(boxes: big, imageSize: CGSize(width: 4000, height: 3000)) == nil,
           "Z2 占满画面→nil")
}

// Z3 空框 → nil；Z4 横条区域（宽满、高小）→ 仍应放大
do {
    gcheck(zoomRegion(boxes: [], imageSize: CGSize(width: 100, height: 100)) == nil, "Z3 空→nil")
    let strip = [CGRect(x: 100, y: 1400, width: 3700, height: 120)]
    gcheck(zoomRegion(boxes: strip, imageSize: CGSize(width: 4000, height: 3000)) != nil,
           "Z4 横条区域→仍放大")
}


// MARK: - 吃（国标）

// C1 国标：桌上一副吃 + 手牌
do {
    let hand = lay(cards(["1m","2m","4m","5m","7m","8m","1p","2p","4p","5p"]), from: 0)
    let chow = lay(cards(["4s","5s","6s"]), from: hand.next + 40)
    let r = groupTiles(hand.boxes + chow.boxes, mode: .mcr)
    gcheck(r.melds.map(meldDesc) == ["吃四条"], "C1 国标一副吃", "melds=\(r.melds.map(meldDesc))")
    gcheck(r.hand.count == 10, "C1 手牌 10 张", "hand=\(r.hand.count)")
    gcheck(r.effectiveTileCount == 13, "C1 张数 13", "n=\(r.effectiveTileCount)")
}

// C2 同一份布局在川麻下**不能**认成吃：无吃，该并回手牌
do {
    let hand = lay(cards(["1m","2m","4m","5m","7m","8m","1p","2p","4p","5p"]), from: 0)
    let chow = lay(cards(["4s","5s","6s"]), from: hand.next + 40)
    let r = groupTiles(hand.boxes + chow.boxes, mode: .sichuan)
    gcheck(r.melds.isEmpty, "C2 川麻不认吃", "melds=\(r.melds.map(meldDesc))")
    gcheck(r.hand.count == 13, "C2 全并回手牌", "hand=\(r.hand.count)")
}

// C3 摆放次序颠倒的吃（5-4-6）也要认出来，且起始牌是最小的那张
do {
    let hand = lay(cards(["1m","2m","4m","5m","7m","8m","1p","2p","4p","5p"]), from: 0)
    let chow = lay(cards(["5s","4s","6s"]), from: hand.next + 40)
    let r = groupTiles(hand.boxes + chow.boxes, mode: .mcr)
    gcheck(r.melds.map(meldDesc) == ["吃四条"], "C3 乱序吃→起始牌取最小", "melds=\(r.melds.map(meldDesc))")
}

// C4 一簇里两副吃紧挨着，要拆成两副
do {
    let hand = lay(cards(["1m","2m","4m","5m","7m","9m","1p"]), from: 0)
    let two = lay(cards(["1s","2s","3s","7p","8p","9p"]), from: hand.next + 40)
    let r = groupTiles(hand.boxes + two.boxes, mode: .mcr)
    gcheck(r.melds.map(meldDesc) == ["吃一条","吃七筒"], "C4 一簇拆两副吃", "melds=\(r.melds.map(meldDesc))")
    gcheck(r.effectiveTileCount == 13, "C4 张数 13", "n=\(r.effectiveTileCount)")
}

// C5 吃和碰混在一簇：碰优先（3 张同牌不能当成顺子的一部分）
do {
    let hand = lay(cards(["1m","2m","4m","5m","7m","9m","1p"]), from: 0)
    let mix = lay(cards(["5p","5p","5p","1s","2s","3s"]), from: hand.next + 40)
    let r = groupTiles(hand.boxes + mix.boxes, mode: .mcr)
    gcheck(r.melds.map(meldDesc) == ["碰五筒","吃一条"], "C5 碰+吃同簇", "melds=\(r.melds.map(meldDesc))")
}

// C6 杠排在碰前面：4 张同牌不能被拆成「碰 + 落单一张」
do {
    let hand = lay(cards(["1m","2m","4m","5m","7m","9m","1p","2p","4p","5p"]), from: 0)
    let kong = lay(cards(["8s","8s","8s","8s"]), from: hand.next + 40)
    let r = groupTiles(hand.boxes + kong.boxes, mode: .mcr)
    gcheck(r.melds.map(meldDesc) == ["明杠八条"], "C6 四张同牌→明杠不拆", "melds=\(r.melds.map(meldDesc))")
}

// C7 不同花色的连号不是吃（4万5万6筒）
do {
    gcheck(parseMeldRuns(cards(["4m","5m","6p"]), guessConcealedKong: false, allowChow: true) == nil,
           "C7 跨花色连号不是吃")
}

// C8 字牌没有顺子：东南西凑不成吃
do {
    let honors = [MahjongCard(suit: .feng, rank: 1),
                  MahjongCard(suit: .feng, rank: 2),
                  MahjongCard(suit: .feng, rank: 3)]
    gcheck(parseMeldRuns(honors, guessConcealedKong: false, allowChow: true) == nil, "C8 东南西不是吃")
}

// C9 并排两张同牌凑不成任何一副 → 整簇解析失败（不能拆成两个「暗杠」）
do {
    gcheck(parseMeldRuns(cards(["3p","3p"]), guessConcealedKong: true, allowChow: true) == nil,
           "C9 两张同牌不拆成两个暗杠")
}

print(gFails == 0 ? "\n分组全部通过 ✅" : "\n❌ 分组 \(gFails) 个失败")
