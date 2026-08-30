//
//  MCRScoringTests.swift
//  国标麻将（MCR）引擎断言：牌型、向听/听牌、81 种番型、不重复计算原则、起和 8 分。
//  运行：./Tests/run.sh（与其他测试拼接执行，复用其 check 计数器风格）
//
//  牌面写法：数字 + 花色字母
//    m 万 / p 筒 / s 条 / z 字（1–4 = 东南西北，5–7 = 中发白）/ f 花（1–8 = 春夏秋冬梅兰竹菊）
//

import Foundation

var mFails = 0
func mcheck(_ cond: Bool, _ label: String, _ detail: @autoclosure () -> String = "") {
    if cond { print("  ✓ \(label)") }
    else { mFails += 1; print("  ✗ FAIL \(label)  \(detail())") }
}

/// 解析牌串
func mt(_ s: String) -> [MahjongCard] {
    var out: [MahjongCard] = []
    var digits: [Int] = []
    for ch in s {
        if let d = ch.wholeNumberValue { digits.append(d); continue }
        switch ch {
        case "m": out += digits.map { MahjongCard(suit: .wan, rank: $0) }; digits = []
        case "p": out += digits.map { MahjongCard(suit: .tong, rank: $0) }; digits = []
        case "s": out += digits.map { MahjongCard(suit: .tiao, rank: $0) }; digits = []
        case "z": out += digits.map {
                      $0 <= 4 ? MahjongCard(suit: .feng, rank: $0)
                              : MahjongCard(suit: .jian, rank: $0 - 4)
                  }; digits = []
        case "f": out += digits.map { MahjongCard(suit: .hua, rank: $0) }; digits = []
        default: digits = []
        }
    }
    return out
}

func mfreq(_ s: String) -> [Int] { handToFrequency34(mt(s)) }
/// 副露；吃传起始牌（如 MM(.chow, "4p") = 吃 456 筒）
func MM(_ k: Meld.Kind, _ s: String) -> Meld { Meld(kind: k, card: mt(s).first!) }
func mnames(_ s: MCRScore) -> [String] { s.items.map(\.name) }

/// 算一副国标和牌
func msc(_ hand: String, melds: [Meld] = [], win: String,
         selfDrawn: Bool = false, flowers: Int = 0,
         _ tweak: (inout MCRContext) -> Void = { _ in }) -> MCRScore {
    var ctx = MCRContext(selfDrawn: selfDrawn, winningTile: mt(win).first!.mcrIndex, flowers: flowers)
    tweak(&ctx)
    return scoreMCRHand(concealed: mfreq(hand), melds: melds, context: ctx)
}

/// 带「规则细则」开关算一副国标和牌
func msco(_ hand: String, melds: [Meld] = [], win: String, options: MCROptions,
          selfDrawn: Bool = false) -> MCRScore {
    let ctx = MCRContext(selfDrawn: selfDrawn, winningTile: mt(win).first!.mcrIndex)
    return scoreMCRHand(concealed: mfreq(hand), melds: melds, context: ctx, options: options)
}

/// 规则细则开关：改一项，其余保持默认
func mopt(_ change: (inout MCROptions) -> Void) -> MCROptions {
    var o = MCROptions(); change(&o); return o
}

/// 断言：分数 + 必须含 / 必须不含 的番型
func mexpect(_ label: String, _ s: MCRScore, points: Int? = nil,
             has: [String] = [], hasnt: [String] = []) {
    var ok = true
    if let p = points, s.scoringPoints != p { ok = false }
    for n in has where !mnames(s).contains(n) { ok = false }
    for n in hasnt where mnames(s).contains(n) { ok = false }
    let detail = s.items.map { "\($0.name)\($0.count > 1 ? "×\($0.count)" : "")" }.joined(separator: "+")
    mcheck(ok, label, "got \(s.scoringPoints)分 [\(detail)]")
}

// MARK: - 牌张模型

print("— 国标牌张模型 —")
mcheck(MahjongCard(suit: .feng, rank: 1).mcrIndex == 27
       && MahjongCard(suit: .feng, rank: 4).mcrIndex == 30
       && MahjongCard(suit: .jian, rank: 1).mcrIndex == 31
       && MahjongCard(suit: .jian, rank: 3).mcrIndex == 33,
       "M1 风/箭 34 下标")
mcheck(MahjongCard(suit: .hua, rank: 1).mcrIndex == -1
       && MahjongCard(suit: .hua, rank: 1).tileIndex == -1,
       "M2 花牌无下标")
mcheck((0..<34).allSatisfy { MahjongCard.fromMCRIndex($0).mcrIndex == $0 }, "M3 34 下标往返")
mcheck(MahjongCard(suit: .feng, rank: 1).displayText == "东"
       && MahjongCard(suit: .jian, rank: 2).displayText == "发"
       && MahjongCard(suit: .hua, rank: 5).displayText == "梅"
       && MahjongCard(suit: .wan, rank: 3).displayText == "三万",
       "M4 牌面文字")
mcheck(MahjongCard.allMCRTilesInOrder().count == 34 + 8, "M5 国标牌张共 42 种")
mcheck(!MahjongCard(suit: .feng, rank: 1).hasImageAsset
       && MahjongCard(suit: .wan, rank: 1).hasImageAsset, "M6 只有数牌有牌面图")

// 吃：三张连号
do {
    let chow = MM(.chow, "4p")
    mcheck(chow.tiles.map(\.rank) == [4, 5, 6] && chow.tileCount == 3 && !chow.kind.isKong,
           "M7 吃 = 连续三张")
    mcheck(meldsToFrequency34([chow]) == {
        var f = Array(repeating: 0, count: 34); f[12] = 1; f[13] = 1; f[14] = 1; return f
    }(), "M8 吃的频率数组")
    // 四川侧不受影响：吃在川麻不会出现，但频率函数仍然安全
    mcheck(meldsToFrequency27([MM(.pong, "1z")]).reduce(0, +) == 0, "M9 字牌不进 27 下标")
}

// MARK: - 和牌牌型

print("— 国标和牌牌型 —")
mcheck(mcrIsWinningHand(mfreq("123m456p789s11122z"), melds: []), "W1 标准型含字牌")
mcheck(mcrIsWinningHand(mfreq("123m456m789m123p55p"), melds: []), "W2 三门齐全也能和（国标无缺一门限制）")
mcheck(mcrIsWinningHand(mfreq("1133557799m1133p")), "W3 七对")
mcheck(mcrIsSevenShiftedPairs(mfreq("11223344556677m")), "W4 连七对")
mcheck(!mcrIsSevenShiftedPairs(mfreq("1133557799m1133p")), "W4a 普通七对不是连七对")
mcheck(mcrIsThirteenOrphans(mfreq("19m19p19s12345677z")), "W5 十三幺")
mcheck(!mcrIsThirteenOrphans(mfreq("19m19p19s11234567z1z")), "W5a 多一张不是十三幺")
mcheck(mcrIsKnittedNoSets(mfreq("147m258p369s12345z")), "W6 全不靠")
mcheck(mcrIsSevenStarsKnitted(mfreq("147m25p36s1234567z")), "W7 七星不靠")
mcheck(mcrIsKnittedStraightForm(mfreq("147m258p369s555m11p")), "W8 组合龙型")
mcheck(mcrIsWinningHand(mfreq("11123456789995m")), "W9 九莲宝灯是标准型")
mcheck(!mcrIsWinningHand(mfreq("123m456p789s1112z")), "W10 缺一张不算和")
// 字牌不能成顺
mcheck(!mcrIsWinningHand(mfreq("123z456p789s11122m")), "W11 东南西不成顺子")
// 副露参与和牌
mcheck(mcrIsWinningHand(mfreq("123m456m11p"), melds: [MM(.chow, "7m"), MM(.pong, "1z")]),
       "W12 吃 + 碰 参与和牌")

// MARK: - 向听 / 听牌 / 进张

print("— 国标向听 / 听牌 / 进张 —")
mcheck(mcrHandShanten(mt("123m456m789m123p55p")) == -1, "S1 已和 = -1")
mcheck(mcrHandShanten(mt("123m456m789m123p1z")) == 0, "S2 单钓字牌听牌")
do {
    let w = mcrCalculateWaiting(cards: mt("123m456m789m123p1z"))
    mcheck(w.count == 1 && w[0] == MahjongCard(suit: .feng, rank: 1), "S3 听东风",
           "got \(w.map(\.displayText))")
}
do {
    // 十三幺听 13 面（缺白：手上 19m19p19s + 东南西北中发 + 一对）
    let w = mcrCalculateWaiting(cards: mt("19m19p19s1234567z"))
    mcheck(w.count == 13, "S4 十三幺听十三面", "got \(w.count)")
}
do {
    let w = mcrCalculateWaiting(cards: mt("123m456m1p"), melds: [MM(.chow, "7m"), MM(.pong, "1z")])
    mcheck(w.map(\.displayText) == ["一筒"], "S5 带吃/碰 单钓一筒", "got \(w.map(\.displayText))")
}
do {
    let acc = mcrAcceptanceTiles(cards: mt("123m456m789m11z22z"))
    let got = Set(acc.map(\.card.displayText))
    mcheck(got == ["东", "南"], "S6 进张含字牌", "got \(got.sorted())")
}
do {
    let s = mcrDiscardSuggestions(cards: mt("123m456m789m123p1z2z"))
    mcheck(s.first?.resultingShanten == 0, "S7 打牌建议：最优弃牌听牌")
}
// 七对向听
mcheck(mcrHandShanten(mt("1122334455667m8m")) == 0 || mcrHandShanten(mt("1122334455667m8m")) == -1,
       "S8 七对向听可达 0")

// MARK: - 番种表完整性

print("— 番种表 —")
// 官方 81 番 + 明暗杠。明暗杠不在 98 规则的 81 番里，但现行通行（含官方竞赛
// 算番器）把「一明杠 + 一暗杠」当独立番种计 5 分，由 mcrOneOpenOneConcealedKong 控制。
mcheck(mcrFanPoints.count == 82 && mcrFanPoints["明暗杠"] == 5,
       "T1 番种表 = 官方 81 种 + 明暗杠", "got \(mcrFanPoints.count)")
do {
    // 排除表里提到的番型必须都是真实存在的番种，否则是打字错误
    let unknown = mcrFanExcludes.flatMap { [$0.key] + $0.value }
        .filter { mcrFanPoints[$0] == nil }
    mcheck(unknown.isEmpty, "T2 排除表里没有拼错的番型名", "unknown: \(Set(unknown).sorted())")
}
do {
    // 番型不能排除自己，也不能出现「A 排除 B 且 B 排除 A」这种互斥环
    let selfRef = mcrFanExcludes.filter { $0.value.contains($0.key) }.map(\.key)
    let cycles = mcrFanExcludes.filter { kv in
        kv.value.contains { mcrFanExcludes[$0]?.contains(kv.key) == true }
    }.map(\.key)
    mcheck(selfRef.isEmpty && cycles.isEmpty, "T3 排除表无自指 / 互斥环",
           "self: \(selfRef) cycles: \(cycles)")
}
do {
    // 高番型只应排除分值不高于自己的番型
    let bad = mcrFanExcludes.flatMap { kv in
        kv.value.filter { (mcrFanPoints[$0] ?? 0) > (mcrFanPoints[kv.key] ?? 0) }
                .map { "\(kv.key)→\($0)" }
    }
    mcheck(bad.isEmpty, "T4 只排除分值不更高的番型", "\(bad)")
}
mcheck(mcrMinimumPoints == 8, "T5 起和线 8 分")

// MARK: - 88 分

print("— 88 分番型 —")
mexpect("F88-1 大四喜", msc("111222333444z55m", win: "5m"),
        has: ["大四喜"], hasnt: ["三风刻", "圈风刻", "门风刻", "碰碰和", "幺九刻"])
mexpect("F88-2 大三元", msc("555666777z123m11p", win: "1p"),
        has: ["大三元"], hasnt: ["箭刻", "双箭刻"])
mexpect("F88-3 绿一色", msc("222333444666s88s", win: "8s"), has: ["绿一色"], hasnt: ["缺一门"])
// 九莲宝灯把幺九刻**减 1**（不是整个吸收）：手里 111/999 两个幺九刻时官方留 1 个。
// 官方 91 = 九莲宝灯 88 + 双暗刻 2 + 幺九刻 1。
mexpect("F88-4 九莲宝灯", msc("11123456789995m", win: "5m"), points: 91,
        has: ["九莲宝灯", "幺九刻"], hasnt: ["清一色", "门前清", "无字"])
mexpect("F88-5 四杠", msc("11m", melds: [
            MM(.exposedKong, "2m"), MM(.exposedKong, "3m"),
            MM(.concealedKong, "4m"), MM(.concealedKong, "5m")], win: "1m"),
        has: ["四杠"], hasnt: ["三杠", "双明杠", "双暗杠", "明杠", "暗杠", "碰碰和", "单钓将"])
mexpect("F88-6 连七对", msc("11223344556677m", win: "7m"), points: 88,
        has: ["连七对"], hasnt: ["七对", "清一色", "门前清", "无字", "单钓将"])
mexpect("F88-7 十三幺", msc("19m19p19s12345677z", win: "7z"), points: 88,
        has: ["十三幺"], hasnt: ["五门齐", "门前清", "单钓将"])

// MARK: - 64 分

print("— 64 分番型 —")
mexpect("F64-1 清幺九", msc("111999m111999p11s", win: "1s"),
        has: ["清幺九", "四暗刻"], hasnt: ["碰碰和", "全带幺", "幺九刻", "无字"])
mexpect("F64-2 小四喜", msc("111222333z44z123m", win: "3m"),
        has: ["小四喜"], hasnt: ["三风刻"])
mexpect("F64-3 小三元", msc("555666z77z123m456m", win: "6m"),
        has: ["小三元"], hasnt: ["双箭刻", "箭刻"])
mexpect("F64-4 字一色", msc("111222333z55566z", win: "6z"),
        has: ["字一色"], hasnt: ["碰碰和", "全带幺", "幺九刻", "缺一门", "无字"])
mexpect("F64-5 四暗刻", msc("111m333p555s777z99m", win: "9m", selfDrawn: true),
        has: ["四暗刻"], hasnt: ["碰碰和", "门前清", "三暗刻", "双暗刻"])
mexpect("F64-6 一色双龙会", msc("123123789789m55m", win: "5m"),
        has: ["一色双龙会"], hasnt: ["清一色", "平和", "一般高", "老少副"])

// MARK: - 48 / 32 分

print("— 48 / 32 分番型 —")
mexpect("F48-1 一色四同顺", msc("123123123123m55m", win: "5m"),
        has: ["一色四同顺"], hasnt: ["一色三同顺", "一般高", "四归一"])
mexpect("F48-2 一色四节高", msc("111222333444m55m", win: "5m"),
        has: ["一色四节高"], hasnt: ["一色三节高", "碰碰和"])
mexpect("F32-1 一色四步高", msc("123234345456m11m", win: "1m"),
        has: ["一色四步高"], hasnt: ["一色三步高", "连六", "老少副"])
mexpect("F32-2 三杠", msc("123m11p", melds: [
            MM(.exposedKong, "2s"), MM(.exposedKong, "3s"), MM(.concealedKong, "4s")], win: "1p"),
        has: ["三杠"], hasnt: ["双明杠", "双暗杠"])
mexpect("F32-3 混幺九", msc("111m999m111z999s55z", win: "5z"),
        has: ["混幺九"], hasnt: ["碰碰和", "全带幺", "幺九刻"])

// MARK: - 24 分

print("— 24 分番型 —")
mexpect("F24-1 七对", msc("1133557799m1133p", win: "3p"),
        has: ["七对"], hasnt: ["门前清", "单钓将"])
mexpect("F24-2 七星不靠", msc("147m25p36s1234567z", win: "7z"),
        has: ["七星不靠"], hasnt: ["全不靠", "五门齐", "门前清"])
mexpect("F24-3 全双刻", msc("222m444m666p888s22s", win: "2s"),
        has: ["全双刻"], hasnt: ["碰碰和", "断幺"])
mexpect("F24-4 三门齐不是清一色", msc("123456789m123p55p", win: "5p"), hasnt: ["清一色"])
mexpect("F24-4b 清一色", msc("222333444567m99m", win: "9m"),
        has: ["清一色"], hasnt: ["无字", "缺一门"])
mexpect("F24-5 一色三同顺", msc("456m55m", melds: [
            MM(.chow, "1m"), MM(.chow, "1m"), MM(.chow, "1m")], win: "5m"),
        has: ["一色三同顺"], hasnt: ["一般高"])
// 同一手牌若拆成 111/222/333 刻子分更高，引擎应选刻子读法（就高不就低）
mexpect("F24-5b 就高：111222333 读作三节高", msc("123123123m789m55m", win: "5m"),
        has: ["一色三节高"], hasnt: ["一般高", "一色三同顺"])
mexpect("F24-6 一色三节高", msc("111222333m789m55m", win: "5m"), has: ["一色三节高"])
mexpect("F24-7 全大", msc("789m789p789s777m99m", win: "9m"), has: ["全大"], hasnt: ["无字"])
mexpect("F24-8 全中", msc("456m456p456s444m55m", win: "5m"),
        has: ["全中"], hasnt: ["无字", "断幺"])
mexpect("F24-9 全小", msc("123m123p123s111m22m", win: "2m"), has: ["全小"], hasnt: ["无字"])

// MARK: - 16 分

print("— 16 分番型 —")
mexpect("F16-1 清龙", msc("123456789m11p234p", win: "4p"),
        has: ["清龙"], hasnt: ["连六", "老少副"])
mexpect("F16-2 三色双龙会", msc("123789m123789p55s", win: "5s"),
        has: ["三色双龙会"], hasnt: ["喜相逢", "老少副", "无字", "平和"])
mexpect("F16-3 一色三步高", msc("123234345m789m55m", win: "5m"),
        points: 45, has: ["一色三步高", "清一色", "老少副"])
mexpect("F16-4 全带五", msc("345m456p567s555m55s", win: "5s"),
        has: ["全带五"], hasnt: ["断幺", "无字"])
mexpect("F16-5 三同刻", msc("111m111p111s234m55m", win: "5m"),
        has: ["三同刻"], hasnt: ["双同刻"])
mexpect("F16-6 三暗刻", msc("111m333m555p789s99s", win: "9s"),
        has: ["三暗刻"], hasnt: ["双暗刻"])

// MARK: - 12 分

print("— 12 分番型 —")
mexpect("F12-1 全不靠", msc("147m258p369s12345z", win: "5z"),
        has: ["全不靠", "组合龙"], hasnt: ["五门齐", "门前清"])
mexpect("F12-2 组合龙", msc("147m258p369s555m11p", win: "1p"), has: ["组合龙"])
mexpect("F12-3 大于五", msc("678m789p999s666m88m", win: "8m"), has: ["大于五"], hasnt: ["无字"])
mexpect("F12-4 小于五", msc("123m234p111s444m22m", win: "2m"), has: ["小于五"], hasnt: ["无字"])
mexpect("F12-5 三风刻", msc("111222333z55m111p", win: "1p"), has: ["三风刻"])

// MARK: - 8 分

print("— 8 分番型 —")
mexpect("F8-1 花龙", msc("123m456p789s11m234s", win: "4s"), has: ["花龙"])
mexpect("F8-2 推不倒", msc("123p234p456s777z99p", win: "9p"),
        has: ["推不倒"], hasnt: ["缺一门"])
mexpect("F8-3 三色三同顺", msc("123m123p123s456m55m", win: "5m"),
        has: ["三色三同顺"], hasnt: ["喜相逢"])
mexpect("F8-4 三色三节高", msc("111m222p333s456m55m", win: "5m"),
        has: ["三色三节高"], hasnt: ["双同刻"])
mexpect("F8-5 杠上开花", msc("123m11p", melds: [
            MM(.chow, "4m"), MM(.chow, "7m"), MM(.exposedKong, "2s")],
            win: "1p", selfDrawn: true) { $0.kongBloom = true },
        has: ["杠上开花"], hasnt: ["自摸"])
mexpect("F8-6 妙手回春", msc("123m456m789m123p11p", win: "1p", selfDrawn: true) {
            $0.lastTileDraw = true }, has: ["妙手回春"], hasnt: ["自摸"])
mexpect("F8-7 海底捞月", msc("123m456m789m123p11p", win: "1p") { $0.lastDiscard = true },
        has: ["海底捞月"])
mexpect("F8-8 抢杠和", msc("123m456m789m123p11p", win: "1p") {
            $0.robbingKong = true; $0.lastTileOfKind = true },
        has: ["抢杠和"], hasnt: ["和绝张"])

// MARK: - 6 分

print("— 6 分番型 —")
mexpect("F6-1 碰碰和", msc("222m555p888s99s", melds: [MM(.pong, "3m")], win: "9s"),
        has: ["碰碰和"])
mexpect("F6-2 混一色", msc("123m456m789m11m", melds: [MM(.pong, "1z")], win: "1m"),
        has: ["混一色"], hasnt: ["缺一门"])
mexpect("F6-3 三色三步高", msc("123m234p345s789m55m", win: "5m"), has: ["三色三步高"])
mexpect("F6-4 五门齐", msc("123m456p789s11z", melds: [MM(.pong, "5z")], win: "1z"),
        has: ["五门齐"])
mexpect("F6-5 全求人", msc("11p", melds: [
            MM(.chow, "1m"), MM(.chow, "4m"), MM(.pong, "5p"), MM(.chow, "7s")], win: "1p"),
        has: ["全求人"], hasnt: ["单钓将", "门前清"])
mexpect("F6-6 双暗杠", msc("123m456p11s", melds: [
            MM(.concealedKong, "1z"), MM(.concealedKong, "5z")], win: "1s"),
        has: ["双暗杠"], hasnt: ["暗杠"])
mexpect("F6-7 双箭刻", msc("555666z123m456m11p", win: "1p"),
        has: ["双箭刻"], hasnt: ["箭刻"])

// MARK: - 4 分

print("— 4 分番型 —")
mexpect("F4-1 全带幺", msc("123m789p111s111z99m", win: "9m"), has: ["全带幺"])
mexpect("F4-2 不求人", msc("123m456m789m123p11p", win: "1p", selfDrawn: true),
        has: ["不求人"], hasnt: ["自摸", "门前清"])
mexpect("F4-3 双明杠", msc("123m456p11s", melds: [
            MM(.exposedKong, "1z"), MM(.exposedKong, "5z")], win: "1s"),
        has: ["双明杠"], hasnt: ["明杠"])
mexpect("F4-4 和绝张", msc("123m456m789m123p11p", win: "1p") { $0.lastTileOfKind = true },
        has: ["和绝张"])

// MARK: - 2 分

print("— 2 分番型 —")
mexpect("F2-1 箭刻", msc("555z123m456m789m11p", win: "1p"), has: ["箭刻"])
mexpect("F2-2 圈风刻/门风刻", msc("111z123m456m789m11p", win: "1p") {
            $0.prevalentWind = 0; $0.seatWind = 0 },
        points: 24, has: ["圈风刻", "门风刻"], hasnt: ["幺九刻"])
mexpect("F2-2b 只有圈风", msc("222z123m456m789m11p", win: "1p") {
            $0.prevalentWind = 1; $0.seatWind = 0 },
        has: ["圈风刻"], hasnt: ["门风刻"])
mexpect("F2-3 门前清", msc("123m456m789m123p11p", win: "1p"), has: ["门前清"])
mexpect("F2-4 平和", msc("234m567m234p678p55s", win: "5s"), has: ["平和"])
mexpect("F2-4b 字牌将不算平和", msc("123m456m789m123p11z", win: "1z"), hasnt: ["平和"])
mexpect("F2-5 四归一", msc("111m123m456p789s55m", win: "5m"), has: ["四归一"])
mexpect("F2-6 双同刻", msc("111m111p234m567m99s", win: "9s"), has: ["双同刻"])
mexpect("F2-7 双暗刻", msc("111m333m456p789s99s", win: "9s"), has: ["双暗刻"])
mexpect("F2-8 暗杠", msc("123m456m789m11p", melds: [MM(.concealedKong, "1z")], win: "1p"),
        has: ["暗杠"])
mexpect("F2-9 断幺", msc("234m567m234p678p55s", win: "5s"), has: ["断幺"])

// MARK: - 1 分

print("— 1 分番型 —")
mexpect("F1-1 一般高", msc("123123m456m789p55s", win: "5s"), has: ["一般高"])
mexpect("F1-2 喜相逢", msc("123567m123p23455s", win: "5s"), has: ["喜相逢"])
mexpect("F1-3 连六", msc("123456m789p234s55s", win: "5s"), has: ["连六"])
mexpect("F1-4 老少副", msc("123789m456p234s55s", win: "5s"), has: ["老少副"])
mexpect("F1-5 幺九刻", msc("111m234m567p345s99s", win: "9s"), has: ["幺九刻"])
mexpect("F1-6 明杠", msc("123m456m789m11p", melds: [MM(.exposedKong, "1z")], win: "1p"),
        has: ["明杠"])
mexpect("F1-7 缺一门", msc("123m456m789m123p55p", win: "5p"), has: ["缺一门"])
// 平和会吸收无字，所以举例得挑个非平和的牌型（官方：四暗刻+幺九刻+缺一门+无字+单钓将 = 69）
mexpect("F1-8 无字", msc("111m444m777m999m22p", win: "2p"), has: ["无字"])
mexpect("F1-9 边张", msc("123456789m23455p", win: "3m"), has: ["边张"])
mexpect("F1-10 坎张", msc("123456789m23455p", win: "2m"), has: ["坎张"])
// 单钓将要求独听。123456789m2345p 听 2m/5m/5筒 不止一张，官方也不给——换成真独听的
mexpect("F1-11 单钓将", msc("111m444m777m999m22p", win: "2p"), has: ["单钓将"])
mexpect("F1-12 自摸", msc("123m11p", melds: [MM(.chow, "4m"), MM(.chow, "7m"), MM(.pong, "1z")],
        win: "1p", selfDrawn: true), has: ["自摸"])
do {
    let s = msc("123m456m789m123p55p", win: "5p", flowers: 3)
    mcheck(mnames(s).contains("花牌")
           && s.totalPoints == s.scoringPoints + 3,
           "F1-13 花牌每张 1 分，不进起和分", "got \(s.scoringPoints)/\(s.totalPoints)")
}

// MARK: - 不重复计算原则

print("— 不重复计算原则 —")
// 不可拆分 + 就高不就低：123m 重复 + 456m + 789m 应算清龙 16，不再拆出一般高
do {
    // 官方算番器：清龙 16 + 门前清 2 + 平和 2 + 一般高 1 + 缺一门 1 + 单钓将 1 = 23。
    // 一般高**照计**——原则 5 允许尚未组合过的那副牌同已组合过的套算一次。
    let s = msc("123123456789m55p", win: "5p")
    mexpect("P1 清龙与一般高并存", s, points: 23, has: ["清龙", "一般高"])
}
// 套算一次：123m×2 + 123p×2 只能配两次（2 分），不能既算 2 个一般高又算 2 个喜相逢
do {
    // 123万 ×2 + 123筒：朴素堆番会算「一般高 1 + 喜相逢 2」= 3 分；
    // 套算一次原则下一副面子只能配一次，合计只有 1 分。
    let s = msc("123123m123p456s55m", win: "5m")
    // 官方算番器：门前清 2 + 平和 2 + 一般高 1 + 喜相逢 1 + 单钓将 1 = 7。
    // 4 副顺子最多 3 个配对番，这里 3 副参与、拿到 2 个。
    let pairFan = s.items.filter { ["一般高", "喜相逢"].contains($0.name) }
                         .reduce(0) { $0 + $1.fan }
    mcheck(pairFan == 2 && s.scoringPoints == 7,
           "P2 套算一次：一般高 + 喜相逢 = 2 分", "got \(pairFan) \(s.scoringPoints) \(mnames(s))")
}
// 不可重复：一色三同顺吃掉一般高
do {
    let s = msc("456m55m", melds: [MM(.chow, "1m"), MM(.chow, "1m"), MM(.chow, "1m")], win: "5m")
    mcheck(mnames(s).contains("一色三同顺") && !mnames(s).contains("一般高"),
           "P3 一色三同顺不再计一般高", "got \(mnames(s))")
}
// 四暗刻吃掉三暗刻/双暗刻/碰碰和/门前清
do {
    let s = msc("111m333p555s777z99m", win: "9m", selfDrawn: true)
    mcheck(mnames(s).contains("四暗刻")
           && !mnames(s).contains("三暗刻") && !mnames(s).contains("双暗刻")
           && !mnames(s).contains("碰碰和"),
           "P4 四暗刻吃掉三暗刻/双暗刻/碰碰和")
}
// 点炮成刻算明刻：同一手牌自摸是四暗刻，点炮只有三暗刻
do {
    let draw = msc("111m333p555s777z99m", win: "1m", selfDrawn: true)
    let disc = msc("111m333p555s777z99m", win: "1m", selfDrawn: false)
    mcheck(mnames(draw).contains("四暗刻") && mnames(disc).contains("三暗刻")
           && !mnames(disc).contains("四暗刻"),
           "P5 点炮成刻降为明刻", "自摸\(mnames(draw)) 点炮\(mnames(disc))")
}
// 清一色吃掉无字 / 缺一门
do {
    let s = msc("222333444567m99m", win: "9m")
    mcheck(mnames(s).contains("清一色")
           && !mnames(s).contains("无字") && !mnames(s).contains("缺一门"),
           "P6 清一色吃掉无字/缺一门")
}
// 不求人吃掉自摸 + 门前清
do {
    let s = msc("123m456m789m123p11p", win: "1p", selfDrawn: true)
    mcheck(mnames(s).contains("不求人")
           && !mnames(s).contains("自摸") && !mnames(s).contains("门前清"),
           "P7 不求人吃掉自摸/门前清")
}
// 一色四同顺吃掉四归一（否则会多算 3 × 2 分）
do {
    let s = msc("123123123123m55m", win: "5m")
    mcheck(!mnames(s).contains("四归一"), "P8 一色四同顺不再计四归一")
}

// MARK: - 起和 8 分

print("— 起和 8 分 —")
do {
    // 吃234万 + 678万 + 345筒 + 567条 + 55筒：平和2 + 断幺2 = 4 分，不够起和。
    // （无字被平和吸收——官方算番器同样是 4 分）
    let s = msc("678m345p567s55p", melds: [MM(.chow, "2m")], win: "7s")
    mcheck(s.scoringPoints == 4 && !s.meetsMinimum,
           "Q1 4 分不到起和线", "got \(s.scoringPoints) \(mnames(s))")
}
do {
    // 同一手牌加 3 张花牌：花牌不计入起和分，仍然不够
    let s = msc("678m345p567s55p", melds: [MM(.chow, "2m")], win: "7s", flowers: 3)
    // 起和分 4（不含花），总分 4 + 花 3 = 7。花牌不计入起和判断，所以仍然不够。
    mcheck(s.totalPoints == 7 && s.scoringPoints == 4 && !s.meetsMinimum,
           "Q2 花牌不算起和分", "got \(s.scoringPoints)/\(s.totalPoints)")
}
do {
    let s = msc("123m456m789m123p55p", win: "5p")
    mcheck(s.meetsMinimum, "Q3 门前清+清龙 达到起和线")
}
// 无番和：除自摸/花牌外一个番型都没有 → 8 分
do {
    let s = msc("567m234p678s11z", melds: [MM(.chow, "1m")], win: "5m")
    mcheck(mnames(s).contains("无番和") && s.scoringPoints == 8 && s.meetsMinimum,
           "Q4 无番和 8 分", "got \(s.scoringPoints) \(mnames(s))")
}

do {
    // 部分手牌（不满 14 张）牌型能成立，但不该给「无番和 8 分」
    let s = scoreMCRHand(concealed: mfreq("123m456p789s11z"), melds: [],
                         context: MCRContext(selfDrawn: false, winningTile: 27))
    mcheck(s.scoringPoints == 0 && !s.meetsMinimum && !mnames(s).contains("无番和"),
           "Q5 部分手牌不算无番和", "got \(s.scoringPoints) \(mnames(s))")
}

// MARK: - 规则细则（各地规则书有分歧，用户可选）

print("— 规则细则（用户可选）—")

// 默认值必须等于「一直以来的算法」，否则上面所有断言的分数都会变
mcheck(RuleSettings().mcrOptions == MCROptions(), "O0 设置默认值 = 引擎默认")
// 默认值对齐官方算番器：前三项官方不这么算，所以默认关。
mcheck(!RuleSettings().mcrZiYiSeCountsHunYaoJiu
       && RuleSettings().mcrJiuLianCountsShuangAnKe
       && !RuleSettings().mcrPerKongFanWithThreeKongs
       && RuleSettings().mcrSevenPairsAllowsQuadAsTwoPairs
       && RuleSettings().mcrWaitFanHighestReading
       && RuleSettings().mcrOneOpenOneConcealedKong,
       "O0b 规则细则默认值 = 官方算番器")
do {
    var s = RuleSettings()
    s.mcrPerKongFanWithThreeKongs = false
    s.mcrWaitFanHighestReading = false
    let back = try! JSONDecoder().decode(RuleSettings.self, from: JSONEncoder().encode(s))
    mcheck(back == s, "O0c 规则细则持久化往返")
    // 老存档没有这些键：按默认值补齐，行为不变
    let legacy = #"{"baseStake":1,"gameMode":"mcr"}"#.data(using: .utf8)!
    let old = try! JSONDecoder().decode(RuleSettings.self, from: legacy)
    mcheck(old.mcrOptions == MCROptions(), "O0d 老存档缺键按默认补齐")
}

// ① 字一色是否同时计混幺九（+32）
// 南南南 西西西 北北北 中中中 + 发发：字一色 64 + 四暗刻 64 + 三风刻 12 + 箭刻 2 + 单钓将 1
do {
    let on = msco("222333444z55566z", win: "6z",
                  options: mopt { $0.mcrZiYiSeCountsHunYaoJiu = true })
    let off = msco("222333444z55566z", win: "6z",
                   options: mopt { $0.mcrZiYiSeCountsHunYaoJiu = false })
    mexpect("O1a 字一色计混幺九（开）= 175 分", on, points: 175, has: ["字一色", "混幺九"])
    mexpect("O1b 字一色不计混幺九（关）= 143 分", off, points: 143,
            has: ["字一色"], hasnt: ["混幺九"])
}

// ② 九莲宝灯是否同时计双暗刻（+2）
do {
    let on = msco("11123455678999m", win: "5m",
                  options: mopt { $0.mcrJiuLianCountsShuangAnKe = true })
    let off = msco("11123455678999m", win: "5m",
                   options: mopt { $0.mcrJiuLianCountsShuangAnKe = false })
    mexpect("O2a 九莲宝灯计双暗刻（开）= 91 分", on, points: 91, has: ["九莲宝灯", "双暗刻"])
    mexpect("O2b 九莲宝灯不计双暗刻（关）= 89 分", off, points: 89,
            has: ["九莲宝灯"], hasnt: ["双暗刻"])
}

// ③ 七对里「4 张相同」是否可当两对
// 1111 22 33 44 55 66 万：当两对 → 七对 24 + 清一色 24 = 48；
// 不当两对 → 退回标准型 123/123/456/456 + 11 将 = 32 分
do {
    let on = msco("11112233445566m", win: "6m", options: MCROptions())
    let off = msco("11112233445566m", win: "6m",
                   options: mopt { $0.mcrSevenPairsAllowsQuadAsTwoPairs = false })
    // 官方 50：七对 24 + 清一色 24 + **四归一 2**。七对可计四归一（参照报告 §2.4）。
    mexpect("O3a 4 张可当两对（开）= 50 分", on, points: 50,
            has: ["七对", "清一色", "四归一"])
    // 关掉后退回标准型：清一色24 + 一般高1 + 连六×2 + 平和2 + 四归一2 + 门前清2 = 33
    mexpect("O3b 4 张不可当两对（关）= 33 分", off, points: 33,
            has: ["清一色", "一般高", "平和", "四归一"], hasnt: ["七对"])
}
do {
    // 退不回标准型的牌：关掉后这副牌在这套规则下根本不成和，0 分
    let on = msco("1111335577m1133p", win: "3p", options: MCROptions())
    let off = msco("1111335577m1133p", win: "3p",
                   options: mopt { $0.mcrSevenPairsAllowsQuadAsTwoPairs = false })
    // 官方 28：七对 24 + 缺一门 1 + 无字 1 + **四归一 2**
    mexpect("O3c 无标准型可退（开）= 28 分", on, points: 28, has: ["七对", "四归一"])
    mcheck(off.scoringPoints == 0 && off.items.isEmpty && !off.meetsMinimum,
           "O3d 无标准型可退（关）= 0 分（不成和）", "got \(off.scoringPoints) \(mnames(off))")
}

// ④ 三杠时是否再单独计每个杠（明杠 1 / 暗杠 2）
do {
    let kongs = [MM(.exposedKong, "2s"), MM(.exposedKong, "3s"), MM(.concealedKong, "4s")]
    let on = msco("123m11p", melds: kongs, win: "1p",
                  options: mopt { $0.mcrPerKongFanWithThreeKongs = true })
    let off = msco("123m11p", melds: kongs, win: "1p",
                   options: mopt { $0.mcrPerKongFanWithThreeKongs = false })
    mexpect("O4a 三杠再计每个杠（开）= 73 分", on, points: 73,
            has: ["三杠", "明杠", "暗杠"])
    mexpect("O4b 三杠不再计每个杠（关）= 69 分", off, points: 69,
            has: ["三杠"], hasnt: ["明杠", "暗杠"])
}

// ⑤ 边张 / 坎张 / 单钓将：跨解法就高 vs 听法唯一才计
// 123456789万 + 345筒 + 55筒，和 5 筒：既能读成单钓将，也能读成 345 筒里的一张
do {
    let on = msco("123m456m789m34555p", win: "5p", options: MCROptions())
    let off = msco("123m456m789m34555p", win: "5p",
                   options: mopt { $0.mcrWaitFanHighestReading = false })
    // 官方：这手听法有歧义 → 不是独听 → 边张/坎张/单钓将一个都不给（21 分）。
    // 「就高」开关只在**独听**成立、但拆解读法不唯一时才起作用。
    mexpect("O5a 听法有歧义时不给听牌番（开）= 21 分", on, points: 21,
            hasnt: ["单钓将", "边张", "坎张"])
    mexpect("O5b 听法有歧义，不计（关）= 21 分", off, points: 21,
            hasnt: ["单钓将", "边张", "坎张"])
}
do {
    // 听法唯一的边张 / 坎张：两种设置下都照计，关掉不等于永远不给
    let bianOn = msco("123456789m23455p", win: "3m", options: MCROptions())
    let bianOff = msco("123456789m23455p", win: "3m",
                       options: mopt { $0.mcrWaitFanHighestReading = false })
    mexpect("O5c 唯一边张（开）= 22 分", bianOn, points: 22, has: ["边张"])
    mexpect("O5d 唯一边张（关）= 22 分", bianOff, points: 22, has: ["边张"])
    let kanOff = msco("123456789m23455p", win: "2m",
                      options: mopt { $0.mcrWaitFanHighestReading = false })
    mexpect("O5e 唯一坎张（关）= 22 分", kanOff, points: 22, has: ["坎张"])
}

// MARK: - 打牌建议（国标）

print("— 国标打牌建议 —")
do {
    let hand = mt("112233445566m78m")
    let e = mcrEvaluateDiscards(mcrDiscardSuggestions(cards: hand, melds: []),
                                cards: hand, melds: [], settings: RuleSettings())
    mcheck(!e.isEmpty && e[0].maxPoints >= 24,
           "E1 清一色一色三同顺路线排第一", "got \(e.first?.maxPoints ?? -1)")
}
do {
    // 国标不受缺一门限制：三门齐全的手牌照样有听牌建议
    let hand = mt("123m456p789s111z22z")
    let e = mcrEvaluateDiscards(mcrDiscardSuggestions(cards: hand, melds: []),
                                cards: hand, melds: [], settings: RuleSettings())
    mcheck(e.contains { $0.suggestion.resultingShanten == 0 }, "E2 三门齐全仍能听牌")
}

// MARK: - 四川侧不受影响（回归护栏）

print("— 四川侧回归护栏 —")
mcheck(handToFrequency27(mt("123m1z5z")).reduce(0, +) == 3, "R1 川麻频率数组忽略字牌")
mcheck(RuleSettings().gameMode == .sichuan, "R2 默认玩法 = 四川")
mcheck(GameMode.sichuan.suits.count == 3 && GameMode.mcr.suits.count == 6, "R3 玩法决定键盘花色")
mcheck(GameMode.sichuan.meldKinds.count == 3 && GameMode.mcr.meldKinds.contains(.chow),
       "R4 只有国标有吃")

print(mFails == 0 ? "\n国标全部通过 ✅" : "\n❌ 国标 \(mFails) 个失败")

// MARK: - 总结（run.sh 的退出码）

let mcrTotalFails = fails + gFails + dFails + mFails
if mcrTotalFails > 0 {
    print("\n❌ 合计 \(mcrTotalFails) 个失败")
    exit(1)
}
print("\n✅ 全部测试通过")
