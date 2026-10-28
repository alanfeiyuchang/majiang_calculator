//
//  majiang_calculatorApp.swift
//  majiang calculator
//
//  Created by ChangFeiyu on 3/17/26.
//

import SwiftUI

/// 只有屏幕足够大才放开横屏。
///
/// Info.plist 里四个方向全写上了，但那是「允许」，不是「都要」：
/// 普通 iPhone 和 iPhone Duo 合起来的外屏横过来，底部键盘会把内容挤得只剩一条缝，
/// 所以在这里按窗口短边再筛一道——现役 iPhone 最宽 440pt、Duo 外屏 466pt 都挡在外面，
/// 只有 Duo 展开后的内屏（短边 669pt）放行。
final class OrientationGate: NSObject, UIApplicationDelegate {
    /// 窗口短边到这个数才算「大屏」
    static let wideScreenMinSide: CGFloat = 600

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        guard let size = window?.bounds.size else { return .portrait }
        let shortSide = min(size.width, size.height)
        // 窗口还没布局时短边是 0，先按竖屏答，布局完 UIKit 会再问一次
        guard shortSide >= Self.wideScreenMinSide else { return .portrait }
        return .all
    }
}

@main
struct majiang_calculatorApp: App {
    @UIApplicationDelegateAdaptor(OrientationGate.self) private var orientationGate
    /// 麻将规则设置（持久化），全局注入
    @StateObject private var ruleStore = RuleSettingsStore()
    /// 应用内语言（默认中文），全局注入
    @StateObject private var langManager = LanguageManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ruleStore)
                .environmentObject(langManager)
                .environment(\.locale, langManager.locale)
                .id(langManager.language)   // 切换语言时重建视图树，确保全部刷新
                #if DEBUG
                .task { if BoxEval.isRequested { await BoxEval.run() } }
                #endif
        }
    }
}
