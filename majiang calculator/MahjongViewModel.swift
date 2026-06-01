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

    @Published private(set) var selectedTiles: [SelectedTile] = []
    @Published private(set) var waitingTiles: [MahjongCard] = []
    @Published var hintMessage: String?
    /// 张数合法但标准形下无任何听牌
    @Published private(set) var showsNoWaiting: Bool = false
    /// 正在调用 AI 识别照片
    @Published private(set) var isRecognizing: Bool = false

    private let maxTiles = 14

    var canAddMore: Bool { selectedTiles.count < maxTiles }

    /// 是否为 3n+1 张（可计算听牌）
    var canCalculateWaiting: Bool {
        let c = selectedTiles.count
        return c > 0 && c % 3 == 1
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
        waitingTiles = []
        hintMessage = nil
        showsNoWaiting = false
    }

    func completeCalculation() {
        guard !selectedTiles.isEmpty else {
            hintMessage = "请先选择手牌。"
            waitingTiles = []
            showsNoWaiting = false
            return
        }
        guard canCalculateWaiting else {
            waitingTiles = []
            showsNoWaiting = false
            hintMessage = "听牌计算需要 1、4、7、10 或 13 张牌（3n+1 张）。当前 \(selectedTiles.count) 张。"
            return
        }
        hintMessage = nil
        let cards = selectedTiles.map(\.card)

        // 缺一门：手牌已含三门花色（花猪），无论如何都不能胡
        if suitCount(handToFrequency27(cards)) >= 3 {
            waitingTiles = []
            showsNoWaiting = false
            hintMessage = "手牌含万、筒、条三门花色（花猪）。四川麻将需缺一门，请打缺其中一门后再算听牌。"
            return
        }

        waitingTiles = calculateWaiting(cards: cards)
        showsNoWaiting = waitingTiles.isEmpty
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
        hintMessage = nil
        waitingTiles = []
        showsNoWaiting = false
        defer { isRecognizing = false }

        do {
            let recognized = try await recognizer.recognize(imageData: imageData)
            let truncated = recognized.count > maxTiles
            setHand(recognized)

            if truncated {
                hintMessage = "识别到超过 14 张牌，已保留前 14 张，请核对后再计算。"
            } else if canCalculateWaiting {
                completeCalculation()
            } else {
                hintMessage = "已识别 \(selectedTiles.count) 张，请核对；听牌计算需 1、4、7、10 或 13 张。"
            }
        } catch {
            selectedTiles = []
            hintMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func clearResult() {
        waitingTiles = []
        hintMessage = nil
        showsNoWaiting = false
    }
}
