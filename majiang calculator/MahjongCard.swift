//
//  MahjongCard.swift
//  majiang calculator
//

import Foundation

/// 一张麻将牌：花色 + 点数
///
/// - 数牌（万/筒/条）点数 1–9，四川麻将只用这三门。
/// - 国标（MCR）另需 风牌（东南西北）、箭牌（中发白）、花牌（春夏秋冬梅兰竹菊）。
///   风/箭的 `rank` 是该门内的序号（风 1–4 = 东南西北，箭 1–3 = 中发白），
///   花牌 `rank` 1–8 = 春夏秋冬梅兰竹菊。
struct MahjongCard: Hashable, Equatable, Identifiable {
    enum Suit: String, CaseIterable, Codable {
        case wan = "万"
        case tong = "筒"
        case tiao = "条"
        /// 风牌：东南西北（仅国标）
        case feng = "风"
        /// 箭牌：中发白（仅国标）
        case jian = "箭"
        /// 花牌：春夏秋冬梅兰竹菊（仅国标，不参与和牌）
        case hua = "花"

        /// 界面与手牌排序：万 → 条 → 筒（与算法下标 万/筒/条 无关）
        static let displayOrder: [Suit] = [.wan, .tiao, .tong]

        /// 国标键盘/排序顺序：万 → 条 → 筒 → 风 → 箭 → 花
        static let mcrDisplayOrder: [Suit] = [.wan, .tiao, .tong, .feng, .jian, .hua]

        var displaySortIndex: Int {
            switch self {
            case .wan: return 0
            case .tiao: return 1
            case .tong: return 2
            case .feng: return 3
            case .jian: return 4
            case .hua: return 5
            }
        }

        /// 数牌（万/筒/条）
        var isNumbered: Bool { self == .wan || self == .tong || self == .tiao }
        /// 字牌（风 + 箭）
        var isHonor: Bool { self == .feng || self == .jian }
        /// 花牌
        var isFlower: Bool { self == .hua }

        /// 该门内的点数上限
        var rankCount: Int {
            switch self {
            case .wan, .tong, .tiao: return 9
            case .feng: return 4
            case .jian: return 3
            case .hua: return 8
            }
        }
    }

    var suit: Suit
    /// 数牌 1...9；风 1...4；箭 1...3；花 1...8
    var rank: Int

    var id: String { "\(suit.rawValue)-\(rank)" }

    /// 0...8 万，9...17 筒，18...26 条；非数牌返回 -1（四川引擎不认字牌/花牌）
    var tileIndex: Int {
        let offset: Int
        switch suit {
        case .wan: offset = 0
        case .tong: offset = 9
        case .tiao: offset = 18
        default: return -1
        }
        return offset + (rank - 1)
    }

    /// 国标 34 张牌下标：0–8 万、9–17 筒、18–26 条、27–30 东南西北、31–33 中发白。
    /// 花牌不参与和牌，返回 -1。
    var mcrIndex: Int {
        switch suit {
        case .wan: return rank - 1
        case .tong: return 9 + rank - 1
        case .tiao: return 18 + rank - 1
        case .feng: return 27 + rank - 1
        case .jian: return 31 + rank - 1
        case .hua: return -1
        }
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

    /// 由国标 34 下标还原一张牌
    static func fromMCRIndex(_ index: Int) -> MahjongCard {
        precondition((0..<34).contains(index))
        if index < 27 { return fromTileIndex(index) }
        if index < 31 { return MahjongCard(suit: .feng, rank: index - 27 + 1) }
        return MahjongCard(suit: .jian, rank: index - 31 + 1)
    }

    /// 中文点数（牌面更醒目）
    private static let rankHan = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
    private static let fengHan = ["", "东", "南", "西", "北"]
    private static let jianHan = ["", "中", "发", "白"]
    private static let huaHan = ["", "春", "夏", "秋", "冬", "梅", "兰", "竹", "菊"]

    private static func han(_ table: [String], _ rank: Int) -> String {
        (rank >= 1 && rank < table.count) ? table[rank] : "\(rank)"
    }

    var rankHanDigit: String {
        switch suit {
        case .feng: return Self.han(Self.fengHan, rank)
        case .jian: return Self.han(Self.jianHan, rank)
        case .hua: return Self.han(Self.huaHan, rank)
        default: return Self.han(Self.rankHan, rank)
        }
    }

    /// 数牌有牌面图片资源；字牌/花牌没有，界面上用文字牌面代替
    var hasImageAsset: Bool { suit.isNumbered }

    /// 牌面图片资源名（对应 Assets.xcassets 中的 tile_<suit>_<rank>）
    var assetName: String {
        let suitKey: String
        switch suit {
        case .wan: suitKey = "man"
        case .tong: suitKey = "pin"
        case .tiao: suitKey = "sou"
        default: return ""
        }
        return "tile_\(suitKey)_\(rank)"
    }

    /// 单行：数牌如「三万」；字牌/花牌就是单字「东」「中」「春」
    var displayText: String {
        suit.isNumbered ? "\(rankHanDigit)\(suit.rawValue)" : rankHanDigit
    }

    /// 键盘等：数字 + 花色，避免被裁切；字牌/花牌仍用单字
    var displayTextCompact: String {
        suit.isNumbered ? "\(rank)\(suit.rawValue)" : rankHanDigit
    }

    /// 四川麻将全部牌张（万/条/筒 各 1–9）
    static func allTilesInOrder() -> [MahjongCard] {
        var list: [MahjongCard] = []
        for suit in Suit.displayOrder {
            for r in 1...9 {
                list.append(MahjongCard(suit: suit, rank: r))
            }
        }
        return list
    }

    /// 国标全部牌张（含风/箭/花）
    static func allMCRTilesInOrder() -> [MahjongCard] {
        var list: [MahjongCard] = []
        for suit in Suit.mcrDisplayOrder {
            for r in 1...suit.rankCount {
                list.append(MahjongCard(suit: suit, rank: r))
            }
        }
        return list
    }
}
