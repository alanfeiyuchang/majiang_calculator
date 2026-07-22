//
//  DiscardEvalTests.swift
//  打牌建议评估（evaluateDiscards）断言：弃后听牌算番 + 最高番优先排序。
//  运行：./Tests/run.sh（与 ScoringTests 拼接执行，复用其 tiles()/M() 等帮手）
//

var dFails = 0
func dcheck(_ cond: Bool, _ label: String, _ detail: @autoclosure () -> String = "") {
    if cond { print("  ✓ \(label)") }
    else { dFails += 1; print("  ✗ FAIL \(label)  \(detail())") }
}

func dEval(_ hand: String, melds: [Meld] = [],
           _ tweak: (inout RuleSettings) -> Void = { _ in }) -> [EvaluatedDiscard] {
    var s = RuleSettings(); tweak(&s)
    let cards = tiles(hand)
    return evaluateDiscards(discardSuggestions(cards: cards, melds: melds),
                            cards: cards, melds: melds, settings: s)
}

print("— 打牌建议评估 —")

// D1 门清清一色：打九条 → 最高 6 番（八条 = 七小对+清一色+门清+断幺九）应排第一，
//    虽然打七条进张更多（8 张 vs 7 张）——最高番数是主排序键
let e1 = dEval("22334455667789s")
dcheck(e1[0].suggestion.discard == tiles("9s")[0] && e1[0].maxFan == 6,
       "D1 打九条最高6番排第一", "got 打\(e1[0].suggestion.discard.displayText) 最高\(e1[0].maxFan)")
dcheck(e1[1].suggestion.discard == tiles("8s")[0] && e1[1].maxFan == 5,
       "D1a 打八条最高5番第二", "got 打\(e1[1].suggestion.discard.displayText)")
dcheck(e1[2].suggestion.discard == tiles("7s")[0] && e1[2].maxFan == 3,
       "D1b 3番组内按进张降序（打七条 8 张在前）", "got 打\(e1[2].suggestion.discard.displayText)")

// D1c 打九条的听牌明细：二条 4 番、五条 4 番、八条 6 番
let w1 = e1[0].waitScores
dcheck(w1.map(\.card) == tiles("258s") && w1.map(\.score.totalFan) == [4, 4, 6],
       "D1c 打九条听 2/5/8 条 = 4/4/6 番",
       "got \(w1.map { "\($0.card.displayText)=\($0.score.totalFan)" })")
dcheck(w1[2].score.money == 64, "D1d 八条不封顶 ¥64", "got \(w1[2].score.money)")

// D2 排序不变式：最高番单调不增；未听牌(-1)排在所有听牌之后
dcheck(zip(e1, e1.dropFirst()).allSatisfy { $0.maxFan >= $1.maxFan }, "D2 最高番降序")
let e2 = dEval("22334455566s", melds: [M(.pong, "9m")])
dcheck(zip(e2, e2.dropFirst()).allSatisfy { $0.maxFan >= $1.maxFan }, "D2a 带副露仍降序")
let firstNoWait = e2.firstIndex { $0.maxFan < 0 } ?? e2.count
dcheck(e2.suffix(from: firstNoWait).allSatisfy { $0.maxFan < 0 }, "D2b 未听牌全部殿后")

// D3 一致性：听牌数与建议 acceptance 一致；每张听牌番数与独立算番一致
for e in e2 where e.suggestion.resultingShanten == 0 {
    dcheck(e.waitScores.count == e.suggestion.acceptance.count,
           "D3 打\(e.suggestion.discard.displayText) 听牌数一致")
    var after = handToFrequency27(tiles("22334455566s"))
    after[e.suggestion.discard.tileIndex] -= 1
    for ws in e.waitScores {
        var f = after; f[ws.card.tileIndex] += 1
        let ref = scoreWinningHand(concealed: f, melds: [M(.pong, "9m")],
                                   settings: RuleSettings(),
                                   context: WinContext(selfDrawn: false))
        dcheck(ref.totalFan == ws.score.totalFan && ref.money == ws.score.money,
               "D3a 打\(e.suggestion.discard.displayText)听\(ws.card.displayText) 与独立算番一致")
    }
}

// D4 跟随规则设置：关断幺九后，打九条的八条从 6 番降到 5 番
let e4 = dEval("22334455667789s") { $0.duanYaoJiuEnabled = false }
dcheck(e4[0].suggestion.discard == tiles("9s")[0] && e4[0].maxFan == 5,
       "D4 关断幺九 → 最高降为 5 番", "got 最高\(e4[0].maxFan)")

// D5 封顶影响金额不影响排序键（番数仍为原始总番）
let e5 = dEval("22334455667789s") { $0.fanCap = 3 }
dcheck(e5[0].maxFan == 6 && e5[0].waitScores.last?.score.money == 8,
       "D5 封顶3 → 八条仍6番但¥8", "got 最高\(e5[0].maxFan) ¥\(e5[0].waitScores.last?.score.money ?? -1)")

print(dFails == 0 ? "\n打牌建议全部通过 ✅" : "\n❌ 打牌建议 \(dFails) 个失败")
