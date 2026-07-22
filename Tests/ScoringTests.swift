
//
//  ScoringTests.swift
//  四川川麻算番引擎断言（独立可运行，不进 App 编译目标）。
//  运行：./Tests/run.sh
//  覆盖：基础番开关、门清、断幺九、根三选一、十八罗汉/金钩钓、将对/将七对、
//        场景番、清一色回归、封顶、综合叠加。
//
func tiles(_ s: String) -> [MahjongCard] {
    var out: [MahjongCard] = []; var digits: [Int] = []
    for ch in s {
        if let d = ch.wholeNumberValue { digits.append(d) }
        else if ch != " " {
            let suit: MahjongCard.Suit = ch == "m" ? .wan : (ch == "p" ? .tong : .tiao)
            out += digits.map { MahjongCard(suit: suit, rank: $0) }; digits = []
        }
    }
    return out
}
func freq(_ s: String) -> [Int] { handToFrequency27(tiles(s)) }
func M(_ k: Meld.Kind, _ s: String) -> Meld { Meld(kind: k, card: tiles(s).first!) }
func names(_ s: WinScore) -> [String] { s.items.map(\.name) }

var fails = 0
func check(_ cond: Bool, _ label: String, _ detail: @autoclosure () -> String = "") {
    if cond { print("  ✓ \(label)") }
    else { fails += 1; print("  ✗ FAIL \(label)  \(detail())") }
}
func sc(_ hand: String, melds: [Meld] = [], _ tweak: (inout RuleSettings) -> Void = { _ in },
        ctx: WinContext = WinContext(selfDrawn: false)) -> WinScore {
    var s = RuleSettings(); tweak(&s)
    return scoreWinningHand(concealed: freq(hand), melds: melds, settings: s, context: ctx)
}
func expect(_ label: String, _ s: WinScore, fan: Int, money: Double,
            has: [String] = [], hasnt: [String] = []) {
    var ok = s.totalFan == fan && s.money == money
    for n in has where !names(s).contains(n) { ok = false }
    for n in hasnt where names(s).contains(n) { ok = false }
    check(ok, label, "got \(s.totalFan)番 ¥\(s.money) \(names(s))")
}
let point = WinContext(selfDrawn: false)
let draw = WinContext(selfDrawn: true)

print("— 默认值 —")
let d = RuleSettings()
check(d.fanCap == 0 && d.selfDrawAddsFan && d.genMode == .fan && d.goldenHookFan == 2
      && !d.jiangEnabled && d.kongBloomEnabled, "T1 计钱/根/金钩钓/将/杠花默认")
check(d.pingHuEnabled && d.pengPengHuEnabled && d.qingYiSeEnabled && d.qiXiaoDuiEnabled
      && d.haoHuaEnabled && d.menQingEnabled && d.duanYaoJiuEnabled, "T1 基础番+门清+断幺 默认全开")

print("— 基础番开关 —")
expect("T2 平胡基线", sc("123456789m55s", melds:[M(.pong,"7s")]), fan:0, money:1, has:["平胡"])
expect("T3 碰碰胡", sc("222333m999s88s", melds:[M(.pong,"1m")]), fan:1, money:2, has:["碰碰胡"])
expect("T3a 碰碰胡关", sc("222333m999s88s", melds:[M(.pong,"1m")]){ $0.pengPengHuEnabled=false }, fan:0, money:1, has:["平胡"], hasnt:["碰碰胡"])
expect("T4 清一色", sc("234567m234m99m", melds:[M(.pong,"1m")]), fan:2, money:4, has:["清一色"])
expect("T4a 清一色关", sc("234567m234m99m", melds:[M(.pong,"1m")]){ $0.qingYiSeEnabled=false }, fan:0, money:1, hasnt:["清一色"])
expect("T5 七小对", sc("11m88m99m22s55s66s77s"), fan:3, money:8, has:["七小对","门清"])
expect("T5a 七小对关", sc("11m88m99m22s55s66s77s"){ $0.qiXiaoDuiEnabled=false }, fan:1, money:2, has:["门清"], hasnt:["七小对"])
expect("T6 豪华七小对", sc("1111m88m99m22s55s66s"), fan:4, money:16, has:["豪华七小对","门清"])
expect("T6a 豪华关(七小对开)", sc("1111m88m99m22s55s66s"){ $0.haoHuaEnabled=false }, fan:3, money:8, has:["七小对","门清"], hasnt:["豪华七小对"])

print("— 门清 —")
expect("T7 门清标准", sc("123456789m234s55s"), fan:1, money:2, has:["门清"], hasnt:["平胡"])
expect("T8 带碰无门清", sc("123456789m22s", melds:[M(.pong,"5s")]), fan:0, money:1, hasnt:["门清"])
expect("T9 明杠无门清(根关)", sc("123456789m22m", melds:[M(.exposedKong,"5s")]){ $0.genMode = .off }, fan:0, money:1, hasnt:["门清"])
expect("T10 仅暗杠有门清(根关)", sc("123456789m22m", melds:[M(.concealedKong,"5s")]){ $0.genMode = .off }, fan:1, money:2, has:["门清"])
expect("T11 门清关", sc("123456789m234s55s"){ $0.menQingEnabled=false }, fan:0, money:1, hasnt:["门清"])
expect("T12 门清自摸", sc("123456789m234s55s", ctx:draw), fan:2, money:4, has:["门清","自摸"])

print("— 断幺九 —")
expect("T13 断幺九", sc("234m567m234s567s88m"), fan:2, money:4, has:["门清","断幺九"])
expect("T13a 断幺关", sc("234m567m234s567s88m"){ $0.duanYaoJiuEnabled=false }, fan:1, money:2, hasnt:["断幺九"])

print("— 根 三选一 —")
let genHand = "234567m234s88s"; let genMeld = [M(.concealedKong,"5s")]
expect("T14 根加番", sc(genHand, melds:genMeld), fan:3, money:8, has:["门清","断幺九","根"])
expect("T14b 根加底", sc(genHand, melds:genMeld){ $0.genMode = .base }, fan:2, money:5, has:["门清","断幺九","根"])
expect("T14c 根关闭", sc(genHand, melds:genMeld){ $0.genMode = .off }, fan:2, money:4, hasnt:["根"])

print("— 十八罗汉 / 金钩钓 —")
let arhat = [M(.concealedKong,"1m"),M(.concealedKong,"2m"),M(.concealedKong,"3m"),M(.concealedKong,"4m")]
expect("T15 十八罗汉(根加番)", sc("55m", melds:arhat), fan:9, money:512, has:["十八罗汉","清一色","门清"])
expect("T15b 根关闭降级", sc("55m", melds:arhat){ $0.genMode = .off }, fan:5, money:32, has:["金钩钓","清一色","门清"], hasnt:["十八罗汉"])
expect("T15c 根加底", sc("55m", melds:arhat){ $0.genMode = .base }, fan:5, money:36, has:["金钩钓","清一色","门清"])
let gold = [M(.pong,"1m"),M(.pong,"2m"),M(.pong,"3m"),M(.pong,"4m")]
expect("T16 金钩钓", sc("55m", melds:gold), fan:4, money:16, has:["金钩钓","清一色"], hasnt:["碰碰胡"])
expect("T16a 金钩钓番=1", sc("55m", melds:gold){ $0.goldenHookFan=1 }, fan:3, money:8, has:["金钩钓","清一色"])

print("— 将对 / 将七对 —")
expect("T17 将对关", sc("222555888m555s22s"), fan:3, money:8, has:["碰碰胡","门清","断幺九"])
expect("T17b 将对开", sc("222555888m555s22s"){ $0.jiangEnabled=true }, fan:5, money:32, has:["将对","门清","断幺九"], hasnt:["碰碰胡"])
expect("T18 将七对关", sc("2222m55m88m22s55s88s"), fan:5, money:32, has:["豪华七小对","门清","断幺九"])
expect("T18b 将七对开", sc("2222m55m88m22s55s88s"){ $0.jiangEnabled=true }, fan:7, money:128, has:["将七对","根","门清","断幺九"])

print("— 只有杠才算根 / 龙七对不重复 —")
// 用户示例：碰 555万 + 手里第 4 张 5万（在 345 顺子里）→ 默认算 1 根
let userMeld = [M(.pong,"5m")]
expect("T31 碰+第4张=根(默认)", sc("12334566677m", melds:userMeld), fan:3, money:8, has:["根","清一色"])
expect("T31b 只有杠才算根→无根", sc("12334566677m", melds:userMeld){ $0.onlyKongCountsAsGen=true }, fan:2, money:4, hasnt:["根"])
// 暗杠两种模式都算根
expect("T31c 暗杠始终算根", sc("234567m234s88s", melds:[M(.concealedKong,"5s")]){ $0.onlyKongCountsAsGen=true }, fan:3, money:8, has:["根"])
// 龙七对：龙走「豪华」命名，不另计根（不与根重复）
expect("T32 龙七对无重复根", sc("1111m22m33m44m55m66m"), fan:6, money:64, has:["豪华七小对","清一色"], hasnt:["根"])
expect("T32b 龙七对+只有杠 仍无根", sc("1111m22m33m44m55m66m"){ $0.onlyKongCountsAsGen=true }, fan:6, money:64, has:["豪华七小对"], hasnt:["根"])

print("— 场景番 —")
let base = "123456789m234s55s"
expect("T19 点炮", sc(base), fan:1, money:2, has:["门清"])
expect("T20 自摸加番", sc(base, ctx:draw), fan:2, money:4, has:["门清","自摸"])
expect("T20a 自摸加底", sc(base, { $0.selfDrawAddsFan=false }, ctx:draw), fan:1, money:3, has:["门清"])
expect("T21 杠上开花", sc(base, ctx:WinContext(selfDrawn:true, kongBloom:true)), fan:3, money:8, has:["门清","杠上开花","自摸"])
expect("T22 海底捞月", sc(base, ctx:WinContext(selfDrawn:true, lastTileDraw:true)), fan:3, money:8, has:["门清","海底捞月","自摸"])
expect("T23 天胡", sc(base, ctx:WinContext(selfDrawn:true, heavenly:true)), fan:6, money:64, has:["门清","天胡","自摸"])
expect("T24 杠上炮", sc(base, ctx:WinContext(selfDrawn:false, kongDischargeWin:true)), fan:2, money:4, has:["门清","杠上炮"])
expect("T25 抢杠胡", sc(base, ctx:WinContext(selfDrawn:false, robbingKong:true)), fan:2, money:4, has:["门清","抢杠胡"])
expect("T26 地胡", sc(base, ctx:WinContext(selfDrawn:false, earthly:true)), fan:5, money:32, has:["门清","地胡"])

print("— 清一色回归 / 封顶 / 综合 —")
check(names(sc("111222333p55p", melds:[M(.concealedKong,"9p")])).contains("清一色"), "T27a 清一色暗杠副露")
check(names(sc("55m", melds:gold)).contains("清一色"), "T27b 清一色金钩钓")
check(names(sc("11p22p33p44p55p66p77p")).contains("清一色"), "T27c 清一色七对")
expect("T28 封顶3(十八罗汉)", sc("55m", melds:arhat){ $0.fanCap=3 }, fan:9, money:8)
expect("T28b 封顶4", sc("55m", melds:arhat){ $0.fanCap=4 }, fan:9, money:16)
expect("T30 清对", sc("222333888m99m", melds:[M(.pong,"1m")]), fan:3, money:8, has:["清一色","碰碰胡"])

print(fails == 0 ? "\n全部通过 ✅" : "\n❌ \(fails) 个失败")
