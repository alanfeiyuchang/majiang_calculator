//
//  LanguageManager.swift
//  majiang calculator
//
//  应用内语言切换（中文 / 英文），默认中文，不跟随系统、无需重启。
//  做法：把 Bundle.main 的类换成 LanguageBundle，本地化查表时改用所选语言的 .lproj，
//  从而 SwiftUI `Text` 与 `String(localized:)` 都切到所选语言。
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class LanguageManager: ObservableObject {
    private static let storageKey = "appLanguage"

    /// "zh-Hans" 或 "en"
    @Published var language: String {
        didSet {
            UserDefaults.standard.set(language, forKey: Self.storageKey)
            Bundle.setAppLanguage(language)
        }
    }

    init() {
        // 默认中文（不读系统语言）
        var initial = UserDefaults.standard.string(forKey: Self.storageKey) ?? "zh-Hans"
#if DEBUG
        if let demo = ProcessInfo.processInfo.environment["DEMO_LANG"] { initial = demo }   // 截图调试用
#endif
        language = initial
        Bundle.setAppLanguage(initial)
    }

    var locale: Locale { Locale(identifier: language) }
    var isEnglish: Bool { language.hasPrefix("en") }

    /// 切换按钮上显示「要切去的那个语言」
    var toggleLabel: String { isEnglish ? "中文" : "EN" }

    func toggle() { language = isEnglish ? "zh-Hans" : "en" }
}

// MARK: - 运行期把 Bundle.main 指向所选语言的 .lproj

private var associatedLanguageBundleKey: UInt8 = 0

private final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(self, &associatedLanguageBundleKey) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    private static let swizzleOnce: Void = {
        object_setClass(Bundle.main, LanguageBundle.self)
    }()

    /// 关联所选语言的 .lproj；找不到（如源语言无独立 lproj）则回落到默认查表
    static func setAppLanguage(_ language: String) {
        _ = swizzleOnce
        let lproj = Bundle.main.path(forResource: language, ofType: "lproj").flatMap { Bundle(path: $0) }
        objc_setAssociatedObject(Bundle.main, &associatedLanguageBundleKey, lproj,
                                 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

/// 当前应用语言的 .lproj bundle。
/// `String(localized:)` 不走 Bundle swizzle，会跟随系统语言——所有 `String(localized:)`
/// 都要显式传 `bundle: appLanguageBundle()` 才跟随应用内语言。
func appLanguageBundle() -> Bundle {
    (objc_getAssociatedObject(Bundle.main, &associatedLanguageBundleKey) as? Bundle) ?? .main
}
