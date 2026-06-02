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

    private let maxTiles = 14

    var canAddMore: Bool { selectedTiles.count < maxTiles }

    /// 是否可分析：非空且为 3n+1 或 3n+2 张
    var canAnalyze: Bool {
        let c = selectedTiles.count
        return c > 0 && c % 3 != 0
    }

    func addCard(_ card: MahjongCard) {
        guard selectedTiles.count < maxTiles else { return }
        selectedTiles.append(SelectedTile(card: card))
        clearResult()
    }

    func removeTile(_ tile: SelectedTile) {
        selectedTiles.removeAll { $0.id == tile.id }
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
        clearResult()
    }

    func completeCalculation() {
        clearResult()
        guard !selectedTiles.isEmpty else {
            hintMessage = "请先选择手牌。"
            return
        }
        let cards = selectedTiles.map(\.card)

        // 缺一门：手牌已含三门花色（花猪），无论如何都不能胡
        if suitCount(handToFrequency27(cards)) >= 3 {
            hintMessage = "手牌含万、筒、条三门花色（花猪）。四川麻将需缺一门，请打缺其中一门。"
            return
        }

        let r = cards.count % 3
        if r == 1 {
            // 3n+1：算向听 / 听牌
            let sh = handShanten(cards)
            shantenValue = sh
            hasAnalyzed = true
            if sh == 0 {
                waitingTiles = calculateWaiting(cards: cards)
                isDeadWait = waitingTiles.isEmpty       // 听牌但可胡牌已摸完 → 空听
            } else {
                acceptance = acceptanceTiles(cards: cards)
                    .map { AcceptanceTile(card: $0.card, remaining: $0.remaining) }
            }
        } else if r == 2 {
            // 3n+2（带摸牌）：判断是否已和，否则给打牌建议
            let sh = handShanten(cards)
            shantenValue = sh
            hasAnalyzed = true
            if sh != -1 {
                discards = discardSuggestions(cards: cards)
            }
        } else {
            // 3n：张数不构成可分析手牌
            hintMessage = "请凑成 1/4/7/10/13 张（听牌），或 2/5/8/11/14 张（带摸牌打牌建议）。当前 \(cards.count) 张。"
        }
    }

    /// 直接用一组牌替换当前手牌（用于 AI 识别结果回填），超过 14 张时截断
    func setHand(_ cards: [MahjongCard]) {
        let ordered = cards.sorted { a, b in
            if a.suit.displaySortIndex != b.suit.displaySortIndex {
                return a.suit.displaySortIndex < b.suit.displaySortIndex
            }
            return a.rank < b.rank
        }
        selectedTiles = ordered.prefix(maxTiles).map { SelectedTile(card: $0) }
        clearResult()
    }

    private let recognizer = LocalTileRecognizer()

    /// 本地 AI 识别照片中的麻将牌，回填手牌并（若张数合法）直接算听
    func recognizeAndCalculate(imageData: Data) async {
        guard !isRecognizing else { return }
        isRecognizing = true
        clearResult()
        defer { isRecognizing = false }

        do {
            let recognized = try await recognizer.recognize(imageData: imageData)
            let truncated = recognized.count > maxTiles
            setHand(recognized)

            if truncated {
                hintMessage = "识别到超过 14 张牌，已保留前 14 张，请核对后再计算。"
            } else if canAnalyze {
                completeCalculation()
            } else {
                hintMessage = "已识别 \(selectedTiles.count) 张，请核对后再分析。"
            }
        } catch {
            selectedTiles = []
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
