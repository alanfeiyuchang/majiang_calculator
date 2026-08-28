//
//  Meld.swift
//  majiang calculator
//
//  桌上的牌（副露）：碰 / 明杠 / 暗杠 / 吃。
//  四川麻将无吃，副露只有前三种，且都是同一张牌的 3 或 4 张；
//  国标（MCR）另有「吃」——同花色连续三张的顺子副露，`card` 存最小的那张。
//

import Foundation

/// 一组副露
struct Meld: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case pong = "碰"
        case exposedKong = "明杠"
        case concealedKong = "暗杠"
        /// 吃：同花色连续三张（仅国标）。`Meld.card` 是顺子起始牌。
        case chow = "吃"

        /// 占用的实体牌张数
        var tileCount: Int {
            switch self {
            case .pong, .chow: return 3
            case .exposedKong, .concealedKong: return 4
            }
        }

        var isKong: Bool { self == .exposedKong || self == .concealedKong }

        /// 顺子副露（吃）
        var isChow: Bool { self == .chow }

        /// 四川麻将可用的副露类型（无吃）
        static let sichuanCases: [Kind] = [.pong, .exposedKong, .concealedKong]
        /// 国标可用的副露类型
        static let mcrCases: [Kind] = [.chow, .pong, .exposedKong, .concealedKong]
    }

    let id = UUID()
    var kind: Kind
    var card: MahjongCard

    var tileCount: Int { kind.tileCount }

    /// 这组副露实际占用的牌：吃是三张连号，其余是同一张牌重复
    var tiles: [MahjongCard] {
        guard kind.isChow else {
            return Array(repeating: card, count: tileCount)
        }
        return (0..<3).map { MahjongCard(suit: card.suit, rank: card.rank + $0) }
    }
}

/// 副露占用的牌 → 长度 27 的频率数组（碰 3 张、杠 4 张）。
/// 字牌/花牌没有 27 下标，直接跳过（四川麻将本来就不用）。
func meldsToFrequency27(_ melds: [Meld]) -> [Int] {
    var c = Array(repeating: 0, count: 27)
    for m in melds {
        for tile in m.tiles {
            let i = tile.tileIndex
            guard i >= 0, i < 27 else { continue }
            c[i] += 1
        }
    }
    return c
}
