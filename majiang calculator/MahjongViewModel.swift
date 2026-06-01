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

    private func clearResult() {
        waitingTiles = []
        hintMessage = nil
        showsNoWaiting = false
    }
}
