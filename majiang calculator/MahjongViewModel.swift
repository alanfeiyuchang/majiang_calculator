//
//  MahjongViewModel.swift
//  majiang calculator
//

import Foundation
import Combine
import UIKit

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

    /// 当前玩法（由 ContentView 从 RuleSettingsStore 同步进来）
    @Published var gameMode: GameMode = .sichuan {
        didSet {
            guard oldValue != gameMode else { return }
            // 切玩法时清空：四川的牌在国标下含义没变，但副露种类/牌张集合变了，
            // 留着上一局的牌容易算出对不上的结果。
            selectedTiles = []
            melds = []
            clearResult()
        }
    }

    @Published private(set) var selectedTiles: [SelectedTile] = []
    /// 桌上的牌（碰 / 明杠 / 暗杠）
    @Published private(set) var melds: [Meld] = []
    @Published private(set) var waitingTiles: [MahjongCard] = []
    @Published var hintMessage: String?
    /// 拍照识别后的非阻塞提示（如「已自动分组 N 副露，请核对」）；不阻断已算出的结果显示
    @Published private(set) var recognitionNotice: String?
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
    // SIMCTL_CHILD_DEMO_RECOGNIZE=<图片绝对路径> 直接跑拍照识别管线（验证分组/二次放大）。
    init() {
        let env = ProcessInfo.processInfo.environment
        if env["DEMO_MODE"] == "mcr" { gameMode = .mcr }   // 截图/调试用：直接进国标
        if let path = env["DEMO_RECOGNIZE"],
           let data = FileManager.default.contents(atPath: path) {
            Task { await self.recognizeAndCalculate(imageData: data) }
            return
        }
        guard let hand = env["DEMO_HAND"] else { return }
        func parse(_ s: String) -> [MahjongCard] {
            var out: [MahjongCard] = []
            var digits: [Int] = []
            for ch in s {
                if let d = ch.wholeNumberValue { digits.append(d) }
                else {
                    if ch == "z" {
                        out += digits.map { $0 <= 4 ? MahjongCard(suit: .feng, rank: $0)
                                                    : MahjongCard(suit: .jian, rank: $0 - 4) }
                    } else if ch == "f" {
                        out += digits.map { MahjongCard(suit: .hua, rank: $0) }
                    } else {
                        let suit: MahjongCard.Suit = ch == "m" ? .wan : (ch == "p" ? .tong : .tiao)
                        out += digits.map { MahjongCard(suit: suit, rank: $0) }
                    }
                    digits = []
                }
            }
            return out
        }
        if let meldSpec = env["DEMO_MELDS"] {
            for part in meldSpec.split(separator: ",") {
                let kind: Meld.Kind
                switch part.first {
                case "p": kind = .pong
                case "k": kind = .exposedKong
                case "c": kind = .chow
                default: kind = .concealedKong
                }
                if let card = parse(String(part.dropFirst())).first {
                    melds.append(Meld(kind: kind, card: card))
                }
            }
        }
        selectedTiles = parse(hand).map { SelectedTile(card: $0) }
        if env["DEMO_ANALYZE"] != "0" { completeCalculation() }
    }
#endif

    /// 参与和牌的手牌（国标里花牌不参与，单独计分）
    var handTiles: [MahjongCard] { selectedTiles.map(\.card).filter { !$0.suit.isFlower } }
    /// 花牌（仅国标）
    var flowerTiles: [MahjongCard] { selectedTiles.map(\.card).filter { $0.suit.isFlower } }

    /// 每组副露占掉 3 张的名额，手牌（暗牌）上限随之减少
    var maxConcealed: Int { 14 - 3 * melds.count }

    var canAddMore: Bool { handTiles.count < maxConcealed }

    /// 是否可分析：暗牌非空且为 3n+1 或 3n+2 张（花牌不算）
    var canAnalyze: Bool {
        let c = handTiles.count
        return c > 0 && c % 3 != 0
    }

    /// 某张牌在手牌 + 副露里合计已用张数。花牌每种只有一张。
    func usedCount(of card: MahjongCard) -> Int {
        selectedTiles.count(where: { $0.card == card })
            + melds.reduce(0) { $0 + $1.tiles.count(where: { $0 == card }) }
    }

    func addCard(_ card: MahjongCard) {
        if card.suit.isFlower {
            guard gameMode.isMCR else { return }
            guard usedCount(of: card) < 1 else {
                hintMessage = String(localized: "「\(card.displayText)」只有一张。", bundle: appLanguageBundle())
                return
            }
            selectedTiles.append(SelectedTile(card: card))
            clearResult()
            return
        }
        guard handTiles.count < maxConcealed else { return }
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
        guard gameMode.meldKinds.contains(kind) else { return false }
        guard melds.count < maxMelds, handTiles.count <= 14 - 3 * (melds.count + 1) else { return false }
        if kind.isChow {
            // 吃：只能是数牌 1–7 起头，且三张各自都还有剩
            guard card.suit.isNumbered, card.rank <= 7 else { return false }
            return Meld(kind: .chow, card: card).tiles.allSatisfy { usedCount(of: $0) < 4 }
        }
        return usedCount(of: card) + kind.tileCount <= 4
    }

    func addMeld(_ kind: Meld.Kind, of card: MahjongCard) {
        let b = appLanguageBundle()
        guard melds.count < maxMelds else {
            hintMessage = String(localized: "最多 4 组副露。", bundle: b)
            return
        }
        guard handTiles.count <= 14 - 3 * (melds.count + 1) else {
            hintMessage = String(localized: "手牌太多，放不下这组副露——先删几张手牌（碰/杠会占掉 3 张名额）。", bundle: b)
            return
        }
        guard canAddMeld(kind, of: card) else {
            let kindName = String(localized: String.LocalizationValue(kind.rawValue), bundle: b)
            if kind.isChow {
                hintMessage = String(localized: "吃只能用数牌，且要从 1–7 起头凑连续三张。", bundle: b)
            } else {
                hintMessage = String(localized: "「\(card.displayText)」总数会超过 4 张，无法\(kindName)。", bundle: b)
            }
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

    /// 万 → 条 → 筒 →（国标）风 → 箭 → 花，同门按点数排序
    func sortSelected() {
        guard selectedTiles.count > 1 else { return }
        selectedTiles.sort { mcrCardOrder($0.card, $1.card) }
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
        if gameMode.isMCR { calculateMCR() } else { calculateSichuan() }
    }

    // MARK: 四川（血战到底）

    private func calculateSichuan() {
        let cards = handTiles

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
            hintMessage = countHintMessage(cards.count)
        }
    }

    // MARK: 国标（MCR）

    private func calculateMCR() {
        let cards = handTiles
        guard !cards.isEmpty else {
            hintMessage = String(localized: "只有花牌——请再选入参与和牌的牌。", bundle: appLanguageBundle())
            return
        }
        let r = cards.count % 3
        if r == 1 {
            let sh = mcrHandShanten(cards, melds: melds)
            shantenValue = sh
            hasAnalyzed = true
            if sh == 0 {
                waitingTiles = mcrCalculateWaiting(cards: cards, melds: melds)
                isDeadWait = waitingTiles.isEmpty
            } else {
                acceptance = mcrAcceptanceTiles(cards: cards, melds: melds)
                    .map { AcceptanceTile(card: $0.card, remaining: $0.remaining) }
            }
        } else if r == 2 {
            let sh = mcrHandShanten(cards, melds: melds)
            shantenValue = sh
            hasAnalyzed = true
            if sh != -1 {
                discards = mcrDiscardSuggestions(cards: cards, melds: melds)
            }
        } else {
            hintMessage = countHintMessage(cards.count)
        }
    }

    /// 3n 张（张数不构成可分析手牌）时的提示
    private func countHintMessage(_ count: Int) -> String {
        let m = melds.count
        let listenCounts = (0...4 - m).map { "\(3 * $0 + 1)" }.joined(separator: "/")
        return String(localized: "当前副露 \(m) 组，手牌需为 \(listenCounts) 张（听牌）或再多 1 张（打牌建议）。当前手牌 \(count) 张。", bundle: appLanguageBundle())
    }

    /// 万 → 条 → 筒 →（国标）风 → 箭 → 花，同门按点数排序
    private func sortedCards(_ cards: [MahjongCard]) -> [MahjongCard] {
        cards.sorted(by: mcrCardOrder)
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
        // 国标模式：花牌用识别到的那些。识别不到花时（照片里本来就没有，或没框进去）
        // 退回用户已经手动补的，免得一次识别把他刚点好的花清空。
        let keptFlowers = gameMode.isMCR ? (result.flowers.isEmpty ? flowerTiles : result.flowers) : []
        melds = Array(result.melds.prefix(maxMelds))

        // 「同一张牌最多 4 张」的计数下标要按玩法选：tileIndex 只覆盖万/筒/条（0…26），
        // 字牌在它那里是 -1——直接用会把识别到的风/箭**整批静默丢掉**。
        // 国标要用 mcrIndex（0…33，含东南西北中发白）。花牌不参与，两边都是 -1。
        let tileSlot: (MahjongCard) -> Int = gameMode.isMCR ? { $0.mcrIndex } : { $0.tileIndex }
        var freq = [Int](repeating: 0, count: 34)
        for m in melds {
            for t in m.tiles {
                let i = tileSlot(t)
                if i >= 0 { freq[i] += 1 }
            }
        }

        let cap = maxConcealed
        var kept: [MahjongCard] = []
        for card in sortedCards(result.hand) {
            let i = tileSlot(card)
            guard kept.count < cap else { break }
            guard i >= 0, freq[i] < 4 else { continue }
            freq[i] += 1
            kept.append(card)
        }
        selectedTiles = (kept + keptFlowers).map { SelectedTile(card: $0) }
        clearResult()
        return kept.count < result.hand.count || result.melds.count > maxMelds
    }

    /// 外部（眼镜拍照等）设置提示语
    func setHint(_ message: String?) { hintMessage = message }

    private let recognizer = LocalTileRecognizer()

    /// 拍照/选图后自动定位「自己的牌」所在区域（相对坐标 0…1，左上原点），
    /// 供裁剪页预先把选框画好。失败返回 nil——裁剪页退回不画框，用户仍可手动拖。
    func suggestHandRegion(for image: UIImage) async -> CGRect? {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        return try? await recognizer.suggestHandRegion(imageData: data)
    }

    /// 本地 AI 识别照片中的麻将牌，回填手牌并自动分析——不需要用户确认。
    /// 检测到副露/暗杠靠猜/张数截断时，分析结果照常算出，另附一条不阻断显示的提示。
    func recognizeAndCalculate(imageData: Data) async {
        guard !isRecognizing else { return }
        isRecognizing = true
        clearResult()
        defer { isRecognizing = false }

        do {
            let result = try await recognizer.recognize(imageData: imageData, mode: gameMode)
            let truncated = applyRecognition(result)   // 内部会 clearResult()
            let b = appLanguageBundle()

            // 国标模式的已知短板：吃和手牌里的顺子牌面完全一样，只能靠「摆得分开」区分，
            // 摆得紧就会判错边；平摊在桌面上的散牌还容易南/北互认。
            let mcrNotice = gameMode.isMCR
                ? String(localized: "国标模式：吃靠「摆得分开」认，和手牌里的顺子容易判错边；平摊的风牌也容易认错，请核对后再算。", bundle: b)
                : nil

            // 张数不变量：手牌 + 3×副露 必须是 13 或 14。对不上说明混进了桌上其他人的牌、
            // 或者有漏识别——这种情况下算出来的番数一定是错的，所以回填让用户改，但不自动分析。
            guard result.hasValidTileCount else {
                if let mcrNotice {
                    hintMessage = String(localized: "识别到 \(result.effectiveTileCount) 张牌（应为 13 或 14）。", bundle: b) + mcrNotice
                } else {
                    hintMessage = String(localized: "识别到 \(result.effectiveTileCount) 张牌（应为 13 或 14），可能混入了桌上其他人的牌，或有漏识别。已回填识别结果，请核对后再分析。", bundle: b)
                }
                return
            }

            if canAnalyze {
                completeCalculation()   // 内部先 clearResult() 再算；花猪/空手牌等仍会设 hintMessage 阻断
                if hintMessage == nil {
                    var notes: [String] = []
                    if let mcrNotice { notes.append(mcrNotice) }
                    if result.guessedConcealedKong {
                        notes.append(String(localized: "已自动分组：\(melds.count) 副露（含暗杠——只露一张、靠猜，建议核对「桌上的牌」）。", bundle: b))
                    } else if !melds.isEmpty {
                        notes.append(String(localized: "已自动分组：\(melds.count) 副露，建议核对「桌上的牌」。", bundle: b))
                    } else if truncated {
                        notes.append(String(localized: "识别到超过 \(maxConcealed) 张牌，已保留前 \(maxConcealed) 张。", bundle: b))
                    }
                    if !notes.isEmpty { recognitionNotice = notes.joined(separator: " ") }
                }
            } else {
                hintMessage = String(localized: "已识别 \(selectedTiles.count) 张，张数不构成可分析手牌，请核对后再分析。", bundle: b)
                if let mcrNotice { hintMessage = (hintMessage ?? "") + mcrNotice }
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
        recognitionNotice = nil
        shantenValue = nil
        acceptance = []
        discards = []
        isDeadWait = false
        hasAnalyzed = false
    }
}
