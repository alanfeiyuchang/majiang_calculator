//
//  MahjongViewModel.swift
//  majiang calculator
//

import Foundation
import Combine

@MainActor
final class MahjongViewModel: ObservableObject {
    /// 每次选中的实例可区分（同点数同花色多张）
    struct SelectedTile: Identifiable, Equatable {
        let id = UUID()
        let card: MahjongCard
    }

    /// 一张进张牌及其剩余张数
    struct AcceptanceTile: Identifiable {
        let id = UUID()
        let card: MahjongCard
        let remaining: Int
    }

    @Published private(set) var selectedTiles: [SelectedTile] = []
    /// 桌上的牌（碰 / 明杠 / 暗杠）
    @Published private(set) var melds: [Meld] = []
    @Published private(set) var waitingTiles: [MahjongCard] = []
    @Published var hintMessage: String?
    /// 正在调用 AI 识别照片
    @Published private(set) var isRecognizing: Bool = false

    // 分析结果
    /// nil = 未计算；-1 = 已和；0 = 听牌；>0 = 向听数
    @Published private(set) var shantenValue: Int? = nil
    /// 3n+1 且未听牌时的进张
    @Published private(set) var acceptance: [AcceptanceTile] = []
    /// 3n+2（带摸牌）时的打牌建议
    @Published private(set) var discards: [DiscardSuggestion] = []
    /// 听牌但所有可胡牌都已在手中（空听）
    @Published private(set) var isDeadWait: Bool = false
    /// 是否已计算过（用于结果区展示）
    @Published private(set) var hasAnalyzed: Bool = false

    private let maxMelds = 4

#if DEBUG
    // UI 调试入口（仅 DEBUG 构建）：无头模拟器里注入演示手牌直接出分析结果。
    // 用法：SIMCTL_CHILD_DEMO_HAND="3456799s" SIMCTL_CHILD_DEMO_MELDS="p1m,K2p" simctl launch …
    // 手牌格式：数字+花色字母（m 万 / s 条 / p 筒）；副露前缀 p 碰、k 明杠、K 暗杠。
    init() {
        let env = ProcessInfo.processInfo.environment
        guard let hand = env["DEMO_HAND"] else { return }
        func parse(_ s: String) -> [MahjongCard] {
            var out: [MahjongCard] = []
            var digits: [Int] = []
            for ch in s {
                if let d = ch.wholeNumberValue { digits.append(d) }
                else {
                    let suit: MahjongCard.Suit = ch == "m" ? .wan : (ch == "p" ? .tong : .tiao)
                    out += digits.map { MahjongCard(suit: suit, rank: $0) }
                    digits = []
                }
            }
            return out
        }
        if let meldSpec = env["DEMO_MELDS"] {
            for part in meldSpec.split(separator: ",") {
                let kind: Meld.Kind = part.hasPrefix("p") ? .pong : (part.hasPrefix("k") ? .exposedKong : .concealedKong)
                if let card = parse(String(part.dropFirst())).first {
                    melds.append(Meld(kind: kind, card: card))
                }
            }
        }
        selectedTiles = parse(hand).map { SelectedTile(card: $0) }
        if env["DEMO_ANALYZE"] != "0" { completeCalculation() }
    }
#endif

    /// 每组副露占掉 3 张的名额，手牌（暗牌）上限随之减少
    var maxConcealed: Int { 14 - 3 * melds.count }

    var canAddMore: Bool { selectedTiles.count < maxConcealed }

    /// 是否可分析：暗牌非空且为 3n+1 或 3n+2 张
    var canAnalyze: Bool {
        let c = selectedTiles.count
        return c > 0 && c % 3 != 0
    }

    /// 某张牌在手牌 + 副露里合计已用张数
    func usedCount(of card: MahjongCard) -> Int {
        selectedTiles.count(where: { $0.card == card })
            + melds.reduce(0) { $0 + ($1.card == card ? $1.tileCount : 0) }
    }

    func addCard(_ card: MahjongCard) {
        guard selectedTiles.count < maxConcealed else { return }
        guard usedCount(of: card) < 4 else {
            hintMessage = String(localized: "「\(card.displayText)」在手牌和副露里已用满 4 张。", bundle: appLanguageBundle())
            return
        }
        selectedTiles.append(SelectedTile(card: card))
        clearResult()
    }

    func removeTile(_ tile: SelectedTile) {
        selectedTiles.removeAll { $0.id == tile.id }
        clearResult()
    }

    // MARK: 副露

    /// 能否加一组该牌的副露（用于键盘禁用态）
    func canAddMeld(_ kind: Meld.Kind, of card: MahjongCard) -> Bool {
        melds.count < maxMelds
            && selectedTiles.count <= 14 - 3 * (melds.count + 1)
            && usedCount(of: card) + kind.tileCount <= 4
    }

    func addMeld(_ kind: Meld.Kind, of card: MahjongCard) {
        let b = appLanguageBundle()
        guard melds.count < maxMelds else {
            hintMessage = String(localized: "最多 4 组副露。", bundle: b)
            return
        }
        guard selectedTiles.count <= 14 - 3 * (melds.count + 1) else {
            hintMessage = String(localized: "手牌太多，放不下这组副露——先删几张手牌（碰/杠会占掉 3 张名额）。", bundle: b)
            return
        }
        guard usedCount(of: card) + kind.tileCount <= 4 else {
            let kindName = String(localized: String.LocalizationValue(kind.rawValue), bundle: b)
            hintMessage = String(localized: "「\(card.displayText)」总数会超过 4 张，无法\(kindName)。", bundle: b)
            return
        }
        melds.append(Meld(kind: kind, card: card))
        clearResult()
    }

    func removeMeld(_ meld: Meld) {
        melds.removeAll { $0.id == meld.id }
        clearResult()
    }

    /// 撤销最近一次选入的牌
    func undoLast() {
        guard !selectedTiles.isEmpty else { return }
        selectedTiles.removeLast()
        clearResult()
    }

    /// 按 万 → 条 → 筒，同花色按点数 1–9 排序
    func sortSelected() {
        guard selectedTiles.count > 1 else { return }
        selectedTiles.sort { a, b in
            let ca = a.card, cb = b.card
            if ca.suit.displaySortIndex != cb.suit.displaySortIndex {
                return ca.suit.displaySortIndex < cb.suit.displaySortIndex
            }
            return ca.rank < cb.rank
        }
        clearResult()
    }

    func reset() {
        selectedTiles = []
        melds = []
        clearResult()
    }

    func completeCalculation() {
        clearResult()
        guard !selectedTiles.isEmpty else {
            hintMessage = String(localized: "请先选择手牌。", bundle: appLanguageBundle())
            return
        }
        let cards = selectedTiles.map(\.card)

        // 缺一门：手牌 + 副露已含三门花色（花猪），无论如何都不能胡
        var combined = handToFrequency27(cards)
        let meldFreq = meldsToFrequency27(melds)
        for i in 0..<27 { combined[i] += meldFreq[i] }
        if suitCount(combined) >= 3 {
            hintMessage = String(localized: "手牌与副露合计含万、筒、条三门花色（花猪）。四川麻将需缺一门，请打缺其中一门。", bundle: appLanguageBundle())
            return
        }

        let r = cards.count % 3
        if r == 1 {
            // 3n+1：算向听 / 听牌
            let sh = handShanten(cards, melds: melds)
            shantenValue = sh
            hasAnalyzed = true
            if sh == 0 {
                waitingTiles = calculateWaiting(cards: cards, melds: melds)
                isDeadWait = waitingTiles.isEmpty       // 听牌但可胡牌已摸完 → 空听
            } else {
                acceptance = acceptanceTiles(cards: cards, melds: melds)
                    .map { AcceptanceTile(card: $0.card, remaining: $0.remaining) }
            }
        } else if r == 2 {
            // 3n+2（带摸牌）：判断是否已和，否则给打牌建议
            let sh = handShanten(cards, melds: melds)
            shantenValue = sh
            hasAnalyzed = true
            if sh != -1 {
                discards = discardSuggestions(cards: cards, melds: melds)
            }
        } else {
            // 3n：张数不构成可分析手牌
            let m = melds.count
            let listenCounts = (0...4 - m).map { "\(3 * $0 + 1)" }.joined(separator: "/")
            hintMessage = String(localized: "当前副露 \(m) 组，手牌需为 \(listenCounts) 张（听牌）或再多 1 张（打牌建议）。当前手牌 \(cards.count) 张。", bundle: appLanguageBundle())
        }
    }

    /// 万 → 条 → 筒，同花色按点数排序
    private func sortedCards(_ cards: [MahjongCard]) -> [MahjongCard] {
        cards.sorted { a, b in
            if a.suit.displaySortIndex != b.suit.displaySortIndex {
                return a.suit.displaySortIndex < b.suit.displaySortIndex
            }
            return a.rank < b.rank
        }
    }

    /// 直接用一组牌替换当前手牌（用于 AI 识别结果回填），超过上限时截断
    func setHand(_ cards: [MahjongCard]) {
        selectedTiles = sortedCards(cards).prefix(maxConcealed).map { SelectedTile(card: $0) }
        clearResult()
    }

    /// 回填拍照识别的分组结果：先放副露（限 4 组），再放手牌
    /// （限剩余名额、且每张牌手牌+副露合计 ≤ 4）。返回是否发生截断。
    @discardableResult
    func applyRecognition(_ result: RecognitionResult) -> Bool {
        melds = Array(result.melds.prefix(maxMelds))
        var freq = meldsToFrequency27(melds)
        let cap = maxConcealed
        var kept: [MahjongCard] = []
        for card in sortedCards(result.hand) {
            guard kept.count < cap else { break }
            guard freq[card.tileIndex] < 4 else { continue }
            freq[card.tileIndex] += 1
            kept.append(card)
        }
        selectedTiles = kept.map { SelectedTile(card: $0) }
        clearResult()
        return kept.count < result.hand.count || result.melds.count > maxMelds
    }

    private let recognizer = LocalTileRecognizer()

    /// 本地 AI 识别照片中的麻将牌，回填手牌并（若张数合法）直接算听
    func recognizeAndCalculate(imageData: Data) async {
        guard !isRecognizing else { return }
        isRecognizing = true
        clearResult()
        defer { isRecognizing = false }

        do {
            let result = try await recognizer.recognize(imageData: imageData)
            let truncated = applyRecognition(result)

            let b = appLanguageBundle()
            if !melds.isEmpty {
                // 检测到副露：不自动分析，先让用户核对「桌上的牌」（暗杠靠猜，尤其要看）
                let kongNote = result.guessedConcealedKong
                    ? String(localized: "（含暗杠——只露一张、靠猜，尤其请核对）", bundle: b) : ""
                hintMessage = String(localized: "已自动分组：\(selectedTiles.count) 张手牌 + \(melds.count) 副露\(kongNote)。请核对「桌上的牌」无误后，点『分析手牌』。", bundle: b)
            } else if truncated {
                hintMessage = String(localized: "识别到超过 \(maxConcealed) 张牌，已保留前 \(maxConcealed) 张，请核对后再计算。", bundle: b)
            } else if canAnalyze {
                completeCalculation()
            } else {
                hintMessage = String(localized: "已识别 \(selectedTiles.count) 张，请核对后再分析。", bundle: b)
            }
        } catch {
            selectedTiles = []
            melds = []
            hintMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func clearResult() {
        waitingTiles = []
        hintMessage = nil
        shantenValue = nil
        acceptance = []
        discards = []
        isDeadWait = false
        hasAnalyzed = false
    }
}
