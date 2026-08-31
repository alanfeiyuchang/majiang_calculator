//
//  ReviewPrompt.swift
//  majiang calculator
//
//  什么时候找用户要评分。
//
//  系统那个弹窗一年最多弹 3 次，超了 StoreKit 直接静默吞掉——所以不能一装上就问，
//  得等用户真的从这个 App 拿到过东西。规则分两步：
//
//  **攒**：只有分析成功才计数（出提示、张数不对的那些不算），够 8 次就上膛。
//  **打**：不在出结果那一刻弹——那时候用户正盯着结果看，弹窗盖上去等于打断他
//         正在用的东西。等他**看完了、动手清空要开下一手**的时候再弹，
//         那会儿屏幕上没有他要读的内容，打断成本最低。
//
//  同一个版本只问一次，升级到新版本才会再有一次机会。
//  用户主动去设置页点「给这个 App 评分」是另一条路，不受这些限制。
//

import Foundation

enum ReviewPrompt {
    private static let successCountKey = "reviewPrompt.successCount"
    private static let askedVersionKey = "reviewPrompt.askedVersion"
    private static let pendingKey = "reviewPrompt.pending"

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

    /// 记一次成功的分析。只在真的算出结果时调用——用户被卡住的那几次不该拿来讨好评。
    /// 够次数了就上膛，但**不在这里弹**：这会儿用户正在读结果。
    static func recordSuccess(defaults: UserDefaults = .standard) {
        let count = defaults.integer(forKey: successCountKey) + 1
        defaults.set(count, forKey: successCountKey)

        guard count >= threshold,
              defaults.string(forKey: askedVersionKey) != currentVersion else { return }
        defaults.set(true, forKey: pendingKey)
    }

    /// 用户看完结果、要开下一手了——这时候才问。
    /// 返回 true 表示现在该弹，并且把「这个版本已经问过」记下来。
    static func consumePendingAsk(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: pendingKey) else { return false }
        defaults.set(false, forKey: pendingKey)
        defaults.set(currentVersion, forKey: askedVersionKey)
        return true
    }

    /// 供测试用：把计数、上膛状态与「已问过的版本」清掉
    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: successCountKey)
        defaults.removeObject(forKey: askedVersionKey)
        defaults.removeObject(forKey: pendingKey)
    }
}
