//
//  majiang_calculatorApp.swift
//  majiang calculator
//
//  Created by ChangFeiyu on 3/17/26.
//

import SwiftUI

@main
struct majiang_calculatorApp: App {
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
        }
    }
}
