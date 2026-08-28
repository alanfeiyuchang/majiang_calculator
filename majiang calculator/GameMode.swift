//
//  GameMode.swift
//  majiang calculator
//
//  玩法选择：四川麻将（血战到底）/ 国标麻将（MCR）。
//  玩法决定牌张集合、副露种类、和牌牌型与算番引擎，界面随之变化。
//

import Foundation

enum GameMode: String, Codable, CaseIterable {
    /// 四川麻将（血战到底）：只有万/筒/条，缺一门，无吃
    case sichuan
    /// 国标麻将（MCR）：全套牌张 + 花牌，有吃，81 种番型，起和 8 分
    case mcr

    /// 设置页/标题上的名字（中文 key，走本地化）
    var label: String {
        switch self {
        case .sichuan: return "四川麻将（血战到底）"
        case .mcr: return "国标麻将"
        }
    }

    /// 一句话说明
    var summary: String {
        switch self {
        case .sichuan: return "只用万/筒/条，必须缺一门，无吃；按番数翻倍算钱。"
        case .mcr: return "含风/箭/花，可吃，81 种番型，起和 8 分。"
        }
    }

    /// 键盘上可用的花色
    var suits: [MahjongCard.Suit] {
        self == .mcr ? MahjongCard.Suit.mcrDisplayOrder : MahjongCard.Suit.displayOrder
    }

    /// 可用的副露种类
    var meldKinds: [Meld.Kind] {
        self == .mcr ? Meld.Kind.mcrCases : Meld.Kind.sichuanCases
    }

    var isMCR: Bool { self == .mcr }
}
