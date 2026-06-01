//
//  MahjongCard.swift
//  majiang calculator
//

import Foundation

/// 一张麻将牌：花色 + 点数（1–9）
struct MahjongCard: Hashable, Equatable, Identifiable {
    enum Suit: String, CaseIterable, Codable {
        case wan = "万"
        case tong = "筒"
        case tiao = "条"

        /// 界面与手牌排序：万 → 条 → 筒（与算法下标 万/筒/条 无关）
        static let displayOrder: [Suit] = [.wan, .tiao, .tong]

        var displaySortIndex: Int {
            switch self {
            case .wan: return 0
            case .tiao: return 1
            case .tong: return 2
            }
        }
    }

    var suit: Suit
    /// 1...9
    var rank: Int

    var id: String { "\(suit.rawValue)-\(rank)" }

    /// 0...8 万，9...17 筒，18...26 条
    var tileIndex: Int {
        let offset: Int
        switch suit {
        case .wan: offset = 0
        case .tong: offset = 9
        case .tiao: offset = 18
        }
        return offset + (rank - 1)
    }

    static func fromTileIndex(_ index: Int) -> MahjongCard {
        precondition((0..<27).contains(index))
        let rank = index % 9 + 1
        switch index / 9 {
        case 0: return MahjongCard(suit: .wan, rank: rank)
        case 1: return MahjongCard(suit: .tong, rank: rank)
        default: return MahjongCard(suit: .tiao, rank: rank)
        }
    }

    /// 中文点数（牌面更醒目）
    private static let rankHan = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

    var rankHanDigit: String {
        guard rank >= 1, rank <= 9 else { return "\(rank)" }
        return Self.rankHan[rank]
    }

    /// 单行：如 「三万」
    var displayText: String { "\(rankHanDigit)\(suit.rawValue)" }

    /// 键盘等：数字 + 花色，避免被裁切
    var displayTextCompact: String { "\(rank)\(suit.rawValue)" }

    static func allTilesInOrder() -> [MahjongCard] {
        var list: [MahjongCard] = []
        for suit in Suit.displayOrder {
            for r in 1...9 {
                list.append(MahjongCard(suit: suit, rank: r))
            }
        }
        return list
    }
}
