//
//  SpokenSummary.swift
//  majiang calculator
//
//  把分析结果说成中文。给「拍完照不看屏幕、直接听结果」用——
//  智能眼镜是主要场景，手机端拍照识别后也能用。
//
//  返回的是**分段**而不是一整句，因为牌名和金额直接相连必然被 TTS 念错：
//  「胡四万八块」会被读成「四万八千块」。分段之后由播报器逐段念、段间留停顿，
//  从结构上杜绝粘连，比在字符串里塞标点可靠。
//

import Foundation

/// 一张听牌的播报数据
struct SpokenWait {
    let card: MahjongCard
    /// 单家金额（四川）。国标下用番数，见 fan
    let money: Double?
    /// 番数（国标用；四川不播报番数，只播金额）
    let fan: Int?
}

/// 播报所需的状态快照。**只读值，不依赖 ViewModel**，便于单测。
struct SpokenState {
    var mode: GameMode = .sichuan
    /// 向听数。0 = 已听牌；nil = 牌数不构成可分析手牌
    var shanten: Int?
    /// 已听牌时的听牌与金额
    var waits: [SpokenWait] = []
    /// 3n+2（可打牌）时的最优弃牌
    var bestDiscard: MahjongCard?
    /// 打出 bestDiscard 后是否即听牌
    var discardLeadsToTenpai: Bool = false
    /// 空听：听的牌已经一张不剩
    var isDeadWait: Bool = false
    /// 阻断性提示（花猪、张数不对等）。有值时优先播报它
    var blockingHint: String?
}

enum SpokenSummary {

    /// 播报段落。逐段念，段间留停顿。
    static func segments(for s: SpokenState) -> [String] {
        // 阻断性提示优先：这种情况下算出来的结果本身不可信，先说问题
        if let hint = s.blockingHint, !hint.isEmpty {
            return [hint]
        }
        guard let shanten = s.shanten else {
            return ["牌数不对，请核对"]
        }

        if shanten == 0 {
            return tenpaiSegments(s)
        }
        return shantenSegments(s, shanten: shanten)
    }

    /// 拼成一句（写日志、单测、界面上显示用；真正播报请用 segments）
    static func text(for s: SpokenState) -> String {
        segments(for: s).joined(separator: "，")
    }

    // MARK: - 已听牌

    private static func tenpaiSegments(_ s: SpokenState) -> [String] {
        if s.isDeadWait {
            // 空听：听的牌已经摸不到了，说了金额反而误导
            let names = s.waits.map(\.card.displayText).joined(separator: "、")
            return names.isEmpty ? ["已听，但是空听"] : ["已听\(names)", "但是空听，牌已经没了"]
        }
        guard !s.waits.isEmpty else { return ["已听牌"] }

        // 逐张念不现实：九莲宝灯这种听 9 张，念完要二十秒。
        // 按「值一样的钱」归组，组内超过 3 张只报张数——听的人要的是
        // 「哪几张最值钱、其余多少」，不是把牌名背一遍。
        let groups = groupedByValue(s.waits)
        var out: [String] = s.waits.count > maxSpokenTiles
            ? ["已听\(s.waits.count)张"]
            : ["已听"]

        for g in groups.prefix(maxSpokenGroups) {
            // 牌名和金额必须分成两段：合起来「四万8块」会被念成「四万八千块」
            out.append(g.cards.count > maxSpokenTiles
                       ? "\(g.cards.count)张"
                       : g.cards.map(\.displayText).joined(separator: "、"))
            if let v = g.valueText { out.append(v) }
        }
        if groups.count > maxSpokenGroups { out.append("其余看屏幕") }
        return out
    }

    /// 一次最多念几张牌名；超过就只报张数
    private static let maxSpokenTiles = 3
    /// 一次最多念几组（按金额/番数分组）
    private static let maxSpokenGroups = 3

    private struct ValueGroup {
        var cards: [MahjongCard]
        var valueText: String?
        var sortKey: Double
    }

    /// 按金额（国标按番）归组，值高的在前。同值的牌保持原有次序。
    private static func groupedByValue(_ waits: [SpokenWait]) -> [ValueGroup] {
        var order: [String] = []
        var byKey: [String: ValueGroup] = [:]
        for w in waits {
            let text: String?
            let sort: Double
            if let fan = w.fan { text = "\(fan)番"; sort = Double(fan) }
            else if let money = w.money { text = moneyText(money); sort = money }
            else { text = nil; sort = 0 }
            let key = text ?? "—"
            if byKey[key] == nil {
                byKey[key] = ValueGroup(cards: [], valueText: text, sortKey: sort)
                order.append(key)
            }
            byKey[key]!.cards.append(w.card)
        }
        // 值降序——先说最值钱的那张，比按牌序背一遍有用。
        // 同值的组之间保持第一次出现的次序（也就是屏幕上的牌序）。
        return order.map { byKey[$0]! }
            .enumerated()
            .sorted { a, b in
                a.element.sortKey != b.element.sortKey
                    ? a.element.sortKey > b.element.sortKey
                    : a.offset < b.offset
            }
            .map(\.element)
    }

    // MARK: - 未听牌

    private static func shantenSegments(_ s: SpokenState, shanten: Int) -> [String] {
        var out = ["向听\(shanten)"]
        guard let discard = s.bestDiscard else { return out }
        if s.discardLeadsToTenpai {
            out.append("打\(discard.displayText)就听牌")
        } else {
            out.append("建议打\(discard.displayText)")
        }
        return out
    }

    // MARK: - 金额

    /// 8.0 → 「8块」；12.5 → 「12块5」。
    /// 不用「元」：口语里「八块」比「八元」自然，且不会和牌名粘连（已分段）。
    static func moneyText(_ money: Double) -> String {
        let rounded = (money * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return "\(Int(rounded))块"
        }
        // 只保留到角，「12块5」而不是「12.5块」——后者 TTS 念成「十二点五块」很别扭
        let jiao = Int((rounded * 10).rounded()) % 10
        return "\(Int(rounded))块\(jiao)"
    }
}
