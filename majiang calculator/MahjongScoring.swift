//
//  MahjongScoring.swift
//  majiang calculator
//
//  传统四川麻将算番与计钱。
//  金额 = 底分 × 2^min(总番, 封顶)，显示为「单家」输赢：
//  点炮 = 放炮那家付这个数；自摸 = 其余三家各付这个数。
//  杠的即时结算（刮风下雨）是杠时另算的账，不计入胡牌金额；
//  设置里的「杠计根番」只控制杠要不要作为根进入胡牌倍数。
//

import Foundation
import Combine

// MARK: - 规则设置

/// 根的计法：加番（每根 +1 番）/ 加底（每根 +1 底分）/ 关闭（不计入胡牌倍数）
enum GenMode: String, Codable, CaseIterable {
    case fan   // 加番
    case base  // 加底
    case off   // 关闭

    var label: String {
        switch self {
        case .fan: return "加番（+1 番）"
        case .base: return "加底（+1 底分）"
        case .off: return "关闭"
        }
    }
}

/// 可因地区而异的规则项，全部持久化
struct RuleSettings: Codable, Equatable {
    /// 玩法：四川麻将（血战到底）/ 国标麻将（MCR）。默认四川，保持老用户不变。
    var gameMode: GameMode = .sichuan

    // MARK: 国标专用
    /// 圈风 0–3 = 东南西北
    var mcrPrevalentWind: Int = 0
    /// 门风（自己的座位风）0–3 = 东南西北
    var mcrSeatWind: Int = 0

    // MARK: 国标规则细则（各地规则书有分歧的 5 处，默认值 = 一直以来的算法）
    /// 字一色是否同时计混幺九（+32）
    var mcrZiYiSeCountsHunYaoJiu: Bool = false
    /// 九莲宝灯是否同时计双暗刻（+2）
    var mcrJiuLianCountsShuangAnKe: Bool = false
    /// 七对里「四张相同」是否可以当两对
    var mcrSevenPairsAllowsQuadAsTwoPairs: Bool = true
    /// 三杠时是否再单独计每个杠（明杠 1 / 暗杠 2）
    var mcrPerKongFanWithThreeKongs: Bool = false
    /// 边张 / 坎张 / 单钓将：true = 跨解法就高不就低；false = 只有听法唯一时才计
    var mcrWaitFanHighestReading: Bool = true
    /// 一明杠 + 一暗杠算「明暗杠」5 分（现行通行）；关掉则按严格 98 拆成明杠 1 + 暗杠 2
    var mcrOneOpenOneConcealedKong: Bool = true

    /// 打包成算番引擎用的选项
    var mcrOptions: MCROptions {
        MCROptions(
            mcrZiYiSeCountsHunYaoJiu: mcrZiYiSeCountsHunYaoJiu,
            mcrJiuLianCountsShuangAnKe: mcrJiuLianCountsShuangAnKe,
            mcrSevenPairsAllowsQuadAsTwoPairs: mcrSevenPairsAllowsQuadAsTwoPairs,
            mcrPerKongFanWithThreeKongs: mcrPerKongFanWithThreeKongs,
            mcrWaitFanHighestReading: mcrWaitFanHighestReading,
            mcrOneOpenOneConcealedKong: mcrOneOpenOneConcealedKong
        )
    }

    /// 底分（0 番平胡的单家金额）
    var baseStake: Double = 1
    /// 封顶番数；0 = 不封顶（默认）
    var fanCap: Int = 0
    /// true = 自摸加番（+1 番）；false = 自摸加底（+1 个底分）
    var selfDrawAddsFan: Bool = true

    // 基础牌型开关（默认全开）：关闭则该番型不计番
    /// 平胡（0 番，兜底；开关对金额无实际影响）
    var pingHuEnabled: Bool = true
    /// 碰碰胡 +1 番
    var pengPengHuEnabled: Bool = true
    /// 清一色 +2 番
    var qingYiSeEnabled: Bool = true
    /// 七小对 +2 番（含豪华家族的基础）
    var qiXiaoDuiEnabled: Bool = true
    /// 豪华七小对：每龙 +1 番。关闭则龙七对按平七小对 2 番计
    var haoHuaEnabled: Bool = true
    /// 门清（无碰、无明杠；暗杠可）+1 番
    var menQingEnabled: Bool = true
    /// 断幺九（整副牌完全不含 1 和 9）+1 番
    var duanYaoJiuEnabled: Bool = true

    /// 金钩钓番数（1 或 2；含碰碰胡，不再叠加）
    var goldenHookFan: Int = 2
    /// 将对（碰碰胡全 2/5/8，3 番）/ 将七对（七小对全 2/5/8，4 番）
    var jiangEnabled: Bool = false

    /// 根的计法：加番 / 加底 / 关闭
    var genMode: GenMode = .fan
    /// true = 只有杠（明杠/暗杠）算根；false（默认）= 碰+第4张、手握4张 也算根
    var onlyKongCountsAsGen: Bool = false

    /// 杠上开花 +1 番
    var kongBloomEnabled: Bool = true

    static let fanCapChoices = [0, 3, 4, 5]

    static func fanCapLabel(_ cap: Int) -> String {
        cap == 0 ? "不封顶" : "\(cap) 番（\(1 << cap) 倍）"
    }

    init() {}

    // 手写解码：旧版本存档缺新键时用默认值补齐，不整体回退
    private enum CodingKeys: String, CodingKey {
        case baseStake, fanCap, selfDrawAddsFan
        case pingHuEnabled, pengPengHuEnabled, qingYiSeEnabled
        case qiXiaoDuiEnabled, haoHuaEnabled, menQingEnabled, duanYaoJiuEnabled
        case goldenHookFan, jiangEnabled, genMode, onlyKongCountsAsGen, kongBloomEnabled
        case gameMode, mcrPrevalentWind, mcrSeatWind
        case mcrZiYiSeCountsHunYaoJiu, mcrJiuLianCountsShuangAnKe
        case mcrSevenPairsAllowsQuadAsTwoPairs, mcrPerKongFanWithThreeKongs
        case mcrOneOpenOneConcealedKong
        case mcrWaitFanHighestReading
        case kongCountsAsGen  // 旧键，仅用于迁移
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gameMode = try c.decodeIfPresent(GameMode.self, forKey: .gameMode) ?? .sichuan
        mcrPrevalentWind = try c.decodeIfPresent(Int.self, forKey: .mcrPrevalentWind) ?? 0
        mcrSeatWind = try c.decodeIfPresent(Int.self, forKey: .mcrSeatWind) ?? 0
        mcrZiYiSeCountsHunYaoJiu =
            try c.decodeIfPresent(Bool.self, forKey: .mcrZiYiSeCountsHunYaoJiu) ?? false
        mcrJiuLianCountsShuangAnKe =
            try c.decodeIfPresent(Bool.self, forKey: .mcrJiuLianCountsShuangAnKe) ?? false
        mcrSevenPairsAllowsQuadAsTwoPairs =
            try c.decodeIfPresent(Bool.self, forKey: .mcrSevenPairsAllowsQuadAsTwoPairs) ?? true
        mcrPerKongFanWithThreeKongs =
            try c.decodeIfPresent(Bool.self, forKey: .mcrPerKongFanWithThreeKongs) ?? false
        mcrWaitFanHighestReading =
            try c.decodeIfPresent(Bool.self, forKey: .mcrWaitFanHighestReading) ?? true
        mcrOneOpenOneConcealedKong =
            try c.decodeIfPresent(Bool.self, forKey: .mcrOneOpenOneConcealedKong) ?? true
        baseStake = try c.decodeIfPresent(Double.self, forKey: .baseStake) ?? 1
        fanCap = try c.decodeIfPresent(Int.self, forKey: .fanCap) ?? 0
        selfDrawAddsFan = try c.decodeIfPresent(Bool.self, forKey: .selfDrawAddsFan) ?? true
        pingHuEnabled = try c.decodeIfPresent(Bool.self, forKey: .pingHuEnabled) ?? true
        pengPengHuEnabled = try c.decodeIfPresent(Bool.self, forKey: .pengPengHuEnabled) ?? true
        qingYiSeEnabled = try c.decodeIfPresent(Bool.self, forKey: .qingYiSeEnabled) ?? true
        qiXiaoDuiEnabled = try c.decodeIfPresent(Bool.self, forKey: .qiXiaoDuiEnabled) ?? true
        haoHuaEnabled = try c.decodeIfPresent(Bool.self, forKey: .haoHuaEnabled) ?? true
        menQingEnabled = try c.decodeIfPresent(Bool.self, forKey: .menQingEnabled) ?? true
        duanYaoJiuEnabled = try c.decodeIfPresent(Bool.self, forKey: .duanYaoJiuEnabled) ?? true
        goldenHookFan = try c.decodeIfPresent(Int.self, forKey: .goldenHookFan) ?? 2
        jiangEnabled = try c.decodeIfPresent(Bool.self, forKey: .jiangEnabled) ?? false
        kongBloomEnabled = try c.decodeIfPresent(Bool.self, forKey: .kongBloomEnabled) ?? true
        onlyKongCountsAsGen = try c.decodeIfPresent(Bool.self, forKey: .onlyKongCountsAsGen) ?? false
        if let mode = try c.decodeIfPresent(GenMode.self, forKey: .genMode) {
            genMode = mode
        } else if let legacy = try c.decodeIfPresent(Bool.self, forKey: .kongCountsAsGen) {
            genMode = legacy ? .fan : .off   // 旧「杠计根番」布尔迁移
        } else {
            genMode = .fan
        }
    }

    // 显式编码（CodingKeys 含仅解码用的旧键，故不能用自动合成）
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(gameMode, forKey: .gameMode)
        try c.encode(mcrPrevalentWind, forKey: .mcrPrevalentWind)
        try c.encode(mcrSeatWind, forKey: .mcrSeatWind)
        try c.encode(mcrZiYiSeCountsHunYaoJiu, forKey: .mcrZiYiSeCountsHunYaoJiu)
        try c.encode(mcrJiuLianCountsShuangAnKe, forKey: .mcrJiuLianCountsShuangAnKe)
        try c.encode(mcrSevenPairsAllowsQuadAsTwoPairs, forKey: .mcrSevenPairsAllowsQuadAsTwoPairs)
        try c.encode(mcrPerKongFanWithThreeKongs, forKey: .mcrPerKongFanWithThreeKongs)
        try c.encode(mcrWaitFanHighestReading, forKey: .mcrWaitFanHighestReading)
        try c.encode(mcrOneOpenOneConcealedKong, forKey: .mcrOneOpenOneConcealedKong)
        try c.encode(baseStake, forKey: .baseStake)
        try c.encode(fanCap, forKey: .fanCap)
        try c.encode(selfDrawAddsFan, forKey: .selfDrawAddsFan)
        try c.encode(pingHuEnabled, forKey: .pingHuEnabled)
        try c.encode(pengPengHuEnabled, forKey: .pengPengHuEnabled)
        try c.encode(qingYiSeEnabled, forKey: .qingYiSeEnabled)
        try c.encode(qiXiaoDuiEnabled, forKey: .qiXiaoDuiEnabled)
        try c.encode(haoHuaEnabled, forKey: .haoHuaEnabled)
        try c.encode(menQingEnabled, forKey: .menQingEnabled)
        try c.encode(duanYaoJiuEnabled, forKey: .duanYaoJiuEnabled)
        try c.encode(goldenHookFan, forKey: .goldenHookFan)
        try c.encode(jiangEnabled, forKey: .jiangEnabled)
        try c.encode(genMode, forKey: .genMode)
        try c.encode(onlyKongCountsAsGen, forKey: .onlyKongCountsAsGen)
        try c.encode(kongBloomEnabled, forKey: .kongBloomEnabled)
    }
}

/// 设置存取：UserDefaults 持久化，变更即保存
@MainActor
final class RuleSettingsStore: ObservableObject {
    private static let storageKey = "ruleSettings.v1"

    @Published var settings: RuleSettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: Self.storageKey)
            }
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(RuleSettings.self, from: data) {
            settings = saved
        } else {
            settings = RuleSettings()
        }
#if DEBUG
        // 截图/调试用：DEMO_MODE=mcr 直接进国标玩法
        if let demo = ProcessInfo.processInfo.environment["DEMO_MODE"],
           let mode = GameMode(rawValue: demo) {
            settings.gameMode = mode
        }
#endif
    }

    /// 恢复默认规则——保留当前「玩法」，只把规则项打回默认
    func resetToDefaults() {
        var fresh = RuleSettings()
        fresh.gameMode = settings.gameMode
        settings = fresh
    }
}

// MARK: - 胡牌场景

/// 胡牌瞬间的场景信息，决定场景番。
/// 自摸侧：杠上开花 / 海底捞月 / 天胡；点炮侧：杠上炮 / 抢杠胡 / 地胡。
struct WinContext {
    var selfDrawn: Bool
    /// 杠上开花（自摸 +1 番，受规则开关控制）
    var kongBloom = false
    /// 海底捞月（摸最后一张自摸，+1 番）
    var lastTileDraw = false
    /// 杠上炮（胡别家杠后打出的牌，+1 番）
    var kongDischargeWin = false
    /// 抢杠胡（+1 番）
    var robbingKong = false
    /// 天胡（庄家起手胡，+4 番）
    var heavenly = false
    /// 地胡（胡第一张打出的牌，+4 番）
    var earthly = false
}

// MARK: - 算番结果

/// 一项番型
struct FanItem: Identifiable {
    let id = UUID()
    /// 番型名（中文，同时作本地化 key）
    let name: String
    /// 番数（进胡牌倍数）
    let fan: Int
    /// 额外加底单位数（加底类：根加底 / 自摸加底，进金额不进番）
    var baseAdd: Int = 0
    /// 同一番型命中的次数（国标用：箭刻 ×2、幺九刻 ×3、花牌 ×n…）。四川一律 1。
    var count: Int = 1

    /// 中文加成文字（日志/测试用；UI 显示走本地化格式，见 ContentView）
    var fanText: String {
        if baseAdd > 0 { return "+\(baseAdd) 底" }
        return fan == 0 ? "0 番" : "+\(fan) 番"
    }
}

struct WinScore {
    let items: [FanItem]
    let totalFan: Int
    /// 封顶后的番数
    let cappedFan: Int
    var isCapped: Bool { cappedFan < totalFan }
    /// 单家金额
    let money: Double
}

// MARK: - 牌型拆解

/// 暗牌能否拆成「1 将对 + 若干刻子」（全刻子，无顺子）——判碰碰胡 / 将对
private func canBeAllTriplets(_ freq: [Int]) -> Bool {
    var c = freq

    func rec(_ start: Int) -> Bool {
        var j = start
        while j < 27 && c[j] == 0 { j += 1 }
        if j == 27 { return true }
        guard c[j] >= 3 else { return false }   // 剩零散牌无法成刻子
        c[j] -= 3
        let ok = rec(j)
        c[j] += 3
        return ok
    }

    for i in 0..<27 where c[i] >= 2 {
        c[i] -= 2
        let ok = rec(0)
        c[i] += 2
        if ok { return true }
    }
    return false
}

// MARK: - 算番

/// 对一副完整胡牌算番与金额。
/// - Parameters:
///   - concealed: 暗牌部分频率数组（含所胡那张，共 14 − 3 × 副露组数 张）
///   - context: 胡牌瞬间的场景（自摸/点炮、杠上开花、海底捞月、天地胡等）
func scoreWinningHand(
    concealed: [Int],
    melds: [Meld],
    settings: RuleSettings,
    context: WinContext
) -> WinScore {
    var combined = concealed
    let meldFreq27 = meldsToFrequency27(melds)
    for i in 0..<27 { combined[i] += meldFreq27[i] }
    let sum = concealed.reduce(0, +)

    var items: [FanItem] = []
    func add(_ name: String, _ fan: Int) {
        items.append(FanItem(name: name, fan: fan))
    }

    /// 按 genMode 结算 count 个根：加番记番、加底记底、关闭不计
    func applyGen(_ count: Int) {
        guard count > 0 else { return }
        switch settings.genMode {
        case .fan:
            items.append(FanItem(name: "根", fan: count))
        case .base:
            items.append(FanItem(name: "根", fan: 0, baseAdd: count))
        case .off:
            break
        }
    }

    let isQingYiSe = suitCount(combined) == 1
    // 门清：无碰、无明杠（暗杠可，空副露也算）
    let isMenQing = melds.allSatisfy { $0.kind == .concealedKong }
    // 断幺九 / 将牌都按整副牌（暗牌 + 副露）判
    let ranksPresent = (0..<27).filter { combined[$0] > 0 }.map { $0 % 9 + 1 }
    let noTerminals = ranksPresent.allSatisfy { $0 != 1 && $0 != 9 }
    let allJiangRanks = ranksPresent.allSatisfy { $0 == 2 || $0 == 5 || $0 == 8 }  // 将牌 2/5/8

    if melds.isEmpty, sum == 14, (0..<27).allSatisfy({ concealed[$0] % 2 == 0 }) {
        // 七小对家族：4 张同牌算一「龙」
        let dragons = concealed.filter { $0 == 4 }.count
        if settings.jiangEnabled, allJiangRanks {
            add("将七对", 4)
            applyGen(dragons)               // 龙作根，按 genMode 结算
        } else if settings.qiXiaoDuiEnabled {
            if settings.haoHuaEnabled, dragons > 0 {
                let names = ["", "豪华七小对", "双豪华七小对", "三豪华七小对"]
                add(names[min(dragons, 3)], 2 + dragons)
            } else {
                add("七小对", 2)             // 豪华关或无龙 → 平七小对
            }
        }
        // 七小对关且非将七对：七对牌型不计基础番（门清 / 断幺九 等仍照常叠加）
    } else {
        // 标准形
        let isGoldenHook = melds.count == 4   // 金钩钓：单钓将，手里只剩 2 张
        let isAllTriplets = canBeAllTriplets(concealed) && !isGoldenHook  // 金钩钓已含碰碰胡
        let pengFanValue = (settings.jiangEnabled && allJiangRanks) ? 3 : 1

        // 根：默认「凑齐 4 张同牌」（杠 / 手握 4 张 / 碰 + 手里第 4 张）；
        // 开启「只有杠才算根」时仅数明杠/暗杠
        var genCount = settings.onlyKongCountsAsGen
            ? melds.filter(\.kind.isKong).count
            : (0..<27).filter { combined[$0] == 4 }.count

        // 十八罗汉：金钩钓 + 4 个杠，且根计加番时才合并命名（4 根并入名内）
        let isEighteenArhats = isGoldenHook && melds.allSatisfy(\.kind.isKong)
            && settings.genMode == .fan
        if isEighteenArhats {
            add("十八罗汉", settings.goldenHookFan + 4)
            genCount = max(0, genCount - melds.filter(\.kind.isKong).count)
        } else if isGoldenHook {
            add("金钩钓", settings.goldenHookFan)
        }
        if isAllTriplets {
            if pengFanValue == 3 {
                add("将对", 3)                              // 将对：将牌 2/5/8 的碰碰胡
            } else if settings.pengPengHuEnabled {
                add("碰碰胡", 1)
            }
        }
        applyGen(genCount)
    }

    if isQingYiSe, settings.qingYiSeEnabled { add("清一色", 2) }
    if isMenQing, settings.menQingEnabled { add("门清", 1) }
    if noTerminals, settings.duanYaoJiuEnabled { add("断幺九", 1) }

    // 场景番
    if context.selfDrawn {
        if context.kongBloom && settings.kongBloomEnabled { add("杠上开花", 1) }
        if context.lastTileDraw { add("海底捞月", 1) }
        if context.heavenly { add("天胡", 4) }
        if settings.selfDrawAddsFan {
            add("自摸", 1)
        } else {
            items.append(FanItem(name: "自摸", fan: 0, baseAdd: 1))   // 自摸加底
        }
    } else {
        if context.kongDischargeWin { add("杠上炮", 1) }
        if context.robbingKong { add("抢杠胡", 1) }
        if context.earthly { add("地胡", 4) }
    }

    if items.isEmpty {
        add("平胡", 0)   // 兜底；平胡开关对金额无影响
    }

    let totalFan = items.reduce(0) { $0 + $1.fan }
    let totalBaseAdd = items.reduce(0) { $0 + $1.baseAdd }
    let cappedFan = settings.fanCap > 0 ? min(totalFan, settings.fanCap) : totalFan
    var money = settings.baseStake * pow(2, Double(cappedFan))
    money += settings.baseStake * Double(totalBaseAdd)   // 加底类（根加底 / 自摸加底）

    return WinScore(items: items, totalFan: totalFan, cappedFan: cappedFan, money: money)
}

// MARK: - 打牌建议评估

/// 一个候选弃牌的完整评估：弃后听哪些牌、各自番数、能达到的最高番
struct EvaluatedDiscard: Identifiable {
    var id: UUID { suggestion.id }
    let suggestion: DiscardSuggestion
    /// 弃后听牌 → 各自算番（仅弃后听牌时非空；顺序同 suggestion.acceptance）
    let waitScores: [(card: MahjongCard, score: WinScore)]
    /// 听牌里能达到的最大番数；弃后未听牌（或空听）= -1
    let maxFan: Int
}

/// 给打牌建议补上「弃后听牌 + 各自番数」，并按
/// 「最高番数降序 → 向听升序 → 进张降序 → 花色/点数」重排。
/// 番数按点炮基线（不含自摸/杠上开花等场景番），随当前规则设置变化。
func evaluateDiscards(
    _ suggestions: [DiscardSuggestion],
    cards: [MahjongCard],
    melds: [Meld],
    settings: RuleSettings
) -> [EvaluatedDiscard] {
    let baseFreq = handToFrequency27(cards)
    let context = WinContext(selfDrawn: false)

    let evaluated = suggestions.map { s -> EvaluatedDiscard in
        guard s.resultingShanten == 0, !s.acceptance.isEmpty else {
            return EvaluatedDiscard(suggestion: s, waitScores: [], maxFan: -1)
        }
        var afterDiscard = baseFreq
        afterDiscard[s.discard.tileIndex] -= 1
        let waitScores = s.acceptance.map { wait -> (card: MahjongCard, score: WinScore) in
            var winning = afterDiscard
            winning[wait.tileIndex] += 1
            return (card: wait, score: scoreWinningHand(
                concealed: winning, melds: melds, settings: settings, context: context))
        }
        return EvaluatedDiscard(
            suggestion: s,
            waitScores: waitScores,
            maxFan: waitScores.map { $0.score.totalFan }.max() ?? -1
        )
    }

    return evaluated.sorted { a, b in
        if a.maxFan != b.maxFan { return a.maxFan > b.maxFan }
        if a.suggestion.resultingShanten != b.suggestion.resultingShanten {
            return a.suggestion.resultingShanten < b.suggestion.resultingShanten
        }
        if a.suggestion.acceptanceCount != b.suggestion.acceptanceCount {
            return a.suggestion.acceptanceCount > b.suggestion.acceptanceCount
        }
        if a.suggestion.discard.suit.displaySortIndex != b.suggestion.discard.suit.displaySortIndex {
            return a.suggestion.discard.suit.displaySortIndex < b.suggestion.discard.suit.displaySortIndex
        }
        return a.suggestion.discard.rank < b.suggestion.discard.rank
    }
}

/// 金额显示：整数不带小数，非整数按需保留（如 ¥0.5）
func moneyText(_ value: Double) -> String {
    "¥\(String(format: "%g", value))"
}
