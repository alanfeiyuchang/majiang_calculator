//
//  Meld.swift
//  majiang calculator
//
//  桌上的牌（副露）：碰 / 明杠 / 暗杠。
//  四川麻将无吃，副露只有这三种，且都是同一张牌的 3 或 4 张。
//

import Foundation

/// 一组副露
struct Meld: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case pong = "碰"
        case exposedKong = "明杠"
        case concealedKong = "暗杠"

        /// 占用的实体牌张数
        var tileCount: Int { self == .pong ? 3 : 4 }

        var isKong: Bool { self != .pong }
    }

    let id = UUID()
    var kind: Kind
    var card: MahjongCard

    var tileCount: Int { kind.tileCount }
}

/// 副露占用的牌 → 长度 27 的频率数组（碰 3 张、杠 4 张）
func meldsToFrequency27(_ melds: [Meld]) -> [Int] {
    var c = Array(repeating: 0, count: 27)
    for m in melds {
        c[m.card.tileIndex] += m.tileCount
    }
    return c
}
