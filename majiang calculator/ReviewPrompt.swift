//
//  ReviewPrompt.swift
//  majiang calculator
//
//  什么时候找用户要评分。
//
//  系统那个弹窗一年最多弹 3 次，超了 StoreKit 直接静默吞掉——所以不能一装上就问，
//  得等用户真的从这个 App 拿到过东西。这里的规则：
//    · 只有**分析成功**才计数（出提示、张数不对的那些不算）
//    · 累计到第 8 次成功时才问
//    · 同一个版本只问一次，升级到新版本才会再有一次机会
//  用户主动去设置页点「给这个 App 评分」是另一条路，不受这些限制。
//

import Foundation

enum ReviewPrompt {
    private static let successCountKey = "reviewPrompt.successCount"
    private static let askedVersionKey = "reviewPrompt.askedVersion"

    /// 第几次成功分析时开口。太早问会浪费掉一年 3 次的额度。
    private static let threshold = 8

    /// App Store 上的 id，用于设置页里的「写评价」直达链接
    static let appStoreID = "6776462266"

    static var writeReviewURL: URL? {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// 记一次成功的分析，返回「现在该弹了吗」。
    /// 只在真的算出结果时调用——用户被卡住的那几次不该拿来讨好评。
    @discardableResult
    static func recordSuccessAndShouldAsk(defaults: UserDefaults = .standard) -> Bool {
        let count = defaults.integer(forKey: successCountKey) + 1
        defaults.set(count, forKey: successCountKey)

        guard count >= threshold else { return false }
        // 同一个版本只问一次
        guard defaults.string(forKey: askedVersionKey) != currentVersion else { return false }
        defaults.set(currentVersion, forKey: askedVersionKey)
        return true
    }

    /// 供测试用：把计数与「已问过的版本」清掉
    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: successCountKey)
        defaults.removeObject(forKey: askedVersionKey)
    }
}
