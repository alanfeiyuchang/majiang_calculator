//
//  SpokenSummaryTests.swift
//  语音播报文案断言（独立可运行，不进 App 编译目标）。
//  运行：./Tests/run.sh
//

var vFails = 0
func vcheck(_ cond: Bool, _ label: String, _ detail: @autoclosure () -> String = "") {
    if cond { print("  ✓ \(label)") }
    else { vFails += 1; print("  ✗ FAIL \(label)  \(detail())") }
}

private func w(_ s: String, _ money: Double? = nil, _ fan: Int? = nil) -> SpokenWait {
    let rank = Int(String(s.first!))!
    let suit: MahjongCard.Suit = s.last == "m" ? .wan : (s.last == "p" ? .tong : .tiao)
    return SpokenWait(card: MahjongCard(suit: suit, rank: rank), money: money, fan: fan)
}
private func card(_ s: String) -> MahjongCard {
    let rank = Int(String(s.first!))!
    let suit: MahjongCard.Suit = s.last == "m" ? .wan : (s.last == "p" ? .tong : .tiao)
    return MahjongCard(suit: suit, rank: rank)
}

print("— 语音播报 SpokenSummary —")

// V1 已听多张：牌名与金额必须分段——合成一句会被 TTS 念成「四万八千块」。
//    同时按金额归组、值高的先念：先听到「最值钱的是哪张」比按牌序背一遍有用。
do {
    let s = SpokenState(shanten: 0, waits: [w("4m", 8), w("5m", 8), w("8m", 16)])
    let segs = SpokenSummary.segments(for: s)
    vcheck(segs == ["已听", "八万", "16块", "四万、五万", "8块"],
           "V1 已听三张：分段 + 高金额优先", "segs=\(segs)")
}

// V2 向听 + 打牌建议
do {
    let s = SpokenState(shanten: 1, bestDiscard: card("4m"))
    vcheck(SpokenSummary.text(for: s) == "向听1，建议打四万",
           "V2 向听 1 给建议", SpokenSummary.text(for: s))
}

// V3 打出去就听牌，说法要更明确
do {
    let s = SpokenState(shanten: 1, bestDiscard: card("5m"), discardLeadsToTenpai: true)
    vcheck(SpokenSummary.text(for: s) == "向听1，打五万就听牌",
           "V3 打出即听", SpokenSummary.text(for: s))
}

// V4 空听：不能报金额，那是摸不到的钱
do {
    let s = SpokenState(shanten: 0, waits: [w("4m", 8)], isDeadWait: true)
    let segs = SpokenSummary.segments(for: s)
    vcheck(!segs.contains(where: { $0.contains("块") }), "V4 空听不报金额", "segs=\(segs)")
    vcheck(segs.contains(where: { $0.contains("空听") }), "V4 空听要说明", "segs=\(segs)")
}

// V5 阻断提示优先：结果本身不可信，先说问题
do {
    let s = SpokenState(shanten: 0, waits: [w("4m", 8)], blockingHint: "三门花色齐全，花猪")
    vcheck(SpokenSummary.segments(for: s) == ["三门花色齐全，花猪"],
           "V5 花猪时只播提示", "\(SpokenSummary.segments(for: s))")
}

// V6 牌数不构成可分析手牌
do {
    vcheck(SpokenSummary.text(for: SpokenState(shanten: nil)) == "牌数不对，请核对",
           "V6 张数不对")
}

// V7 国标报番数不报金额
do {
    let s = SpokenState(mode: .mcr, shanten: 0, waits: [w("4m", nil, 24)])
    vcheck(SpokenSummary.segments(for: s) == ["已听", "四万", "24番"],
           "V7 国标报番", "\(SpokenSummary.segments(for: s))")
}

// V8 金额格式：整数不带小数点；带角时说「12块5」而不是「12.5块」
do {
    vcheck(SpokenSummary.moneyText(8) == "8块", "V8a 整数金额", SpokenSummary.moneyText(8))
    vcheck(SpokenSummary.moneyText(12.5) == "12块5", "V8b 带角金额", SpokenSummary.moneyText(12.5))
    vcheck(SpokenSummary.moneyText(0) == "0块", "V8c 零", SpokenSummary.moneyText(0))
}

// V9 已听但没算出金额（例如未设底分）→ 只报牌，不编数字
do {
    let s = SpokenState(shanten: 0, waits: [w("4m")])
    vcheck(SpokenSummary.segments(for: s) == ["已听", "四万"], "V9 无金额只报牌",
           "\(SpokenSummary.segments(for: s))")
}


// V10 听很多张：按金额归组，组内超过 3 张只报张数——九莲宝灯听 9 张，
//     逐张念要二十秒，没人听得下去
do {
    var waits = [w("1m", 16), w("9m", 16)]
    waits += ["2m","3m","4m","5m","6m","7m","8m"].map { w($0, 8) }
    let segs = SpokenSummary.segments(for: SpokenState(shanten: 0, waits: waits))
    vcheck(segs == ["已听9张", "一万、九万", "16块", "7张", "8块"],
           "V10 九张按金额归组", "segs=\(segs)")
}

// V11 值高的组排前面，不管它在原始顺序里排第几
do {
    let segs = SpokenSummary.segments(for: SpokenState(
        shanten: 0, waits: [w("2m", 8), w("5m", 32), w("8m", 8)]))
    vcheck(segs == ["已听", "五万", "32块", "二万、八万", "8块"],
           "V11 高金额优先", "segs=\(segs)")
}

// V12 恰好 3 张仍逐张报牌名（不该退化成「3张」）
do {
    let segs = SpokenSummary.segments(for: SpokenState(
        shanten: 0, waits: [w("1m", 8), w("2m", 8), w("3m", 8)]))
    vcheck(segs == ["已听", "一万、二万、三万", "8块"], "V12 三张仍报牌名", "segs=\(segs)")
}

print(vFails == 0 ? "\n播报全部通过 ✅" : "\n❌ 播报 \(vFails) 个失败")
