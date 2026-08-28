//
//  SettingsView.swift
//  majiang calculator
//
//  麻将规则设置：各地规则差异在这里配置，持久化并即时影响算番/金额。
//  「番型一览」列出当前规则下支持的全部番型与番数。
//

import SwiftUI

struct SettingsView: View {
    /// 点击「从相册选择」后调用：关闭设置页并打开相册选择器（由 ContentView 负责实际弹出）
    var onPickFromLibrary: () -> Void = {}
    @EnvironmentObject private var store: RuleSettingsStore
    @Environment(\.dismiss) private var dismiss

    private var isMCR: Bool { store.settings.gameMode.isMCR }
    private static let windNames = ["东", "南", "西", "北"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("玩法", selection: $store.settings.gameMode) {
                        ForEach(GameMode.allCases, id: \.self) { mode in
                            Text(LocalizedStringKey(mode.label)).tag(mode)
                        }
                    }
                } header: {
                    Text("玩法")
                } footer: {
                    Text(LocalizedStringKey(store.settings.gameMode.summary))
                }

                if isMCR {
                    Section {
                        Picker("圈风", selection: $store.settings.mcrPrevalentWind) {
                            ForEach(0..<4, id: \.self) { i in
                                Text(LocalizedStringKey(Self.windNames[i])).tag(i)
                            }
                        }
                        Picker("门风", selection: $store.settings.mcrSeatWind) {
                            ForEach(0..<4, id: \.self) { i in
                                Text(LocalizedStringKey(Self.windNames[i])).tag(i)
                            }
                        }
                    } header: {
                        Text("圈风 / 门风")
                    } footer: {
                        Text("影响圈风刻、门风刻（各 2 分）。门风就是自己的座位风。")
                    }

                    Section {
                        NavigationLink {
                            MCRFanReferenceView()
                        } label: {
                            Label("番型一览（81 种）", systemImage: "list.bullet.rectangle")
                        }
                    } footer: {
                        Text("国标不按底分翻倍算钱，只算番分，起和 8 分。花牌每张 1 分，不计入起和分。拍照识别只认万/筒/条，风牌、箭牌、花牌需手动补入。")
                    }
                }

                if !isMCR {
                Section {
                    HStack {
                        Text("底分")
                        Spacer()
                        TextField("1", value: $store.settings.baseStake, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("元")
                            .foregroundStyle(.secondary)
                    }
                    Picker("封顶", selection: $store.settings.fanCap) {
                        ForEach(RuleSettings.fanCapChoices, id: \.self) { cap in
                            Text(LocalizedStringKey(RuleSettings.fanCapLabel(cap))).tag(cap)
                        }
                    }
                } header: {
                    Text("计钱")
                } footer: {
                    Text("金额 = 底分 × 2^番数（封顶截断），为单家输赢：点炮由放炮者付，自摸三家各付。")
                }

                Section {
                    Picker("自摸", selection: $store.settings.selfDrawAddsFan) {
                        Text("加番（+1 番）").tag(true)
                        Text("加底（+1 底分）").tag(false)
                    }
                    Picker("根", selection: $store.settings.genMode) {
                        ForEach(GenMode.allCases, id: \.self) { mode in
                            Text(LocalizedStringKey(mode.label)).tag(mode)
                        }
                    }
                    Toggle("只有杠才算根", isOn: $store.settings.onlyKongCountsAsGen)
                        .disabled(store.settings.genMode == .off)
                } header: {
                    Text("计法")
                } footer: {
                    Text("根 = 4 张同牌。默认「碰 + 手里第 4 张」「手握 4 张」也算根；开启「只有杠才算根」后仅明杠/暗杠算。加底/关闭时，杠只按刮风下雨即时结算，不再翻倍进胡牌金额。")
                }

                Section {
                    Toggle("碰碰胡（1 番）", isOn: $store.settings.pengPengHuEnabled)
                    Toggle("清一色（2 番）", isOn: $store.settings.qingYiSeEnabled)
                    Toggle("七小对（2 番）", isOn: $store.settings.qiXiaoDuiEnabled)
                    Toggle("豪华七小对（每龙 +1 番）", isOn: $store.settings.haoHuaEnabled)
                    Toggle("门清（+1 番）", isOn: $store.settings.menQingEnabled)
                    Toggle("断幺九（+1 番）", isOn: $store.settings.duanYaoJiuEnabled)
                    Picker("金钩钓", selection: $store.settings.goldenHookFan) {
                        Text("1 番").tag(1)
                        Text("2 番").tag(2)
                    }
                    Toggle("将对 / 将七对（3 / 4 番）", isOn: $store.settings.jiangEnabled)
                    Toggle("杠上开花（+1 番）", isOn: $store.settings.kongBloomEnabled)
                } header: {
                    Text("番型开关")
                } footer: {
                    Text("门清 = 没有碰、没有明杠（暗杠可），点炮/自摸都算。断幺九 = 整副牌完全没有 1 和 9。七小对关闭后，七对牌型不计基础 2 番；豪华关闭则龙七对按平七小对计。将对 = 碰碰胡且全是 2/5/8（关闭时按普通碰碰胡/七小对计）。金钩钓已含碰碰胡，不叠加。")
                }

                Section {
                    NavigationLink {
                        FanReferenceView(settings: store.settings)
                    } label: {
                        Label("番型一览", systemImage: "list.bullet.rectangle")
                    }
                }
                }   // end if !isMCR

                Section {
                    Button("恢复默认规则", role: .destructive) {
                        store.resetToDefaults()
                    }
                }

                Section {
                    Button {
                        onPickFromLibrary()
                    } label: {
                        Label("从相册选择识别手牌", systemImage: "photo.on.rectangle")
                    }
                } footer: {
                    Text("拍照识别在主界面底部；这里是从相册里选一张已有的照片来识别。")
                }
            }
            .navigationTitle("规则设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 番型一览

/// 当前规则下支持的全部番型与番数（随设置动态变化）
struct FanReferenceView: View {
    let settings: RuleSettings

    private struct Row: Identifiable {
        let id = UUID()
        let name: LocalizedStringKey
        let fan: LocalizedStringKey
        var note: LocalizedStringKey? = nil
        var enabled: Bool = true
    }

    private var patternRows: [Row] {
        [
            Row(name: "平胡", fan: "0 番", note: "兜底"),
            Row(name: "碰碰胡", fan: "1 番", enabled: settings.pengPengHuEnabled),
            Row(name: "清一色", fan: "2 番", enabled: settings.qingYiSeEnabled),
            Row(name: "七小对", fan: "2 番", enabled: settings.qiXiaoDuiEnabled),
            Row(name: "豪华七小对（豪七）", fan: "3 番", note: "每多一龙再 +1：双豪华 4 番、三豪华 5 番",
                enabled: settings.qiXiaoDuiEnabled && settings.haoHuaEnabled),
            Row(name: "金钩钓", fan: "\(settings.goldenHookFan) 番", note: "已含碰碰胡，不叠加"),
            Row(name: "将对", fan: "3 番", note: "碰碰胡且全是 2/5/8",
                enabled: settings.jiangEnabled),
            Row(name: "将七对", fan: "4 番", note: "七小对且全是 2/5/8",
                enabled: settings.jiangEnabled),
            Row(name: "十八罗汉", fan: "\(settings.goldenHookFan + 4) 番", note: "金钩钓 + 4 杠（含 4 根）",
                enabled: settings.genMode == .fan),
        ]
    }

    private var comboRows: [Row] {
        [
            Row(name: "清对（清一色 + 碰碰胡）", fan: "3 番"),
            Row(name: "清七对", fan: "4 番"),
            Row(name: "清豪七", fan: "5 番"),
            Row(name: "清金钩钓", fan: "\(settings.goldenHookFan + 2) 番"),
        ]
    }

    private var extraRows: [Row] {
        let genFan: LocalizedStringKey
        switch settings.genMode {
        case .fan: genFan = "每个 +1 番"
        case .base: genFan = "每个 +1 底"
        case .off: genFan = "不计"
        }
        return [
            Row(name: "门清", fan: "+1 番", note: "没有碰、没有明杠（暗杠可），点炮/自摸都算",
                enabled: settings.menQingEnabled),
            Row(name: "断幺九", fan: "+1 番", note: "整副牌完全没有 1 和 9",
                enabled: settings.duanYaoJiuEnabled),
            Row(name: "根", fan: genFan,
                note: settings.onlyKongCountsAsGen
                    ? "只有杠：明杠 / 暗杠"
                    : "4 张同牌：杠 / 手握 4 张 / 碰 + 手里第 4 张",
                enabled: settings.genMode != .off),
        ]
    }

    private var situationalRows: [Row] {
        [
            Row(name: "自摸", fan: settings.selfDrawAddsFan ? "+1 番" : "+1 底"),
            Row(name: "杠上开花", fan: "+1 番", note: "自摸侧", enabled: settings.kongBloomEnabled),
            Row(name: "海底捞月", fan: "+1 番", note: "自摸侧"),
            Row(name: "杠上炮", fan: "+1 番", note: "点炮侧"),
            Row(name: "抢杠胡", fan: "+1 番", note: "点炮侧"),
            Row(name: "天胡", fan: "+4 番", note: "庄家起手胡"),
            Row(name: "地胡", fan: "+4 番", note: "胡第一张打出的牌"),
        ]
    }

    var body: some View {
        List {
            section("基础牌型（自动识别，可叠加）", patternRows)
            section("常见组合（自动叠出，不单列）", comboRows)
            section("附加番", extraRows)
            section("场景番（胡牌时勾选）", situationalRows)
        }
        .navigationTitle("番型一览")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: LocalizedStringKey, _ rows: [Row]) -> some View {
        Section(title) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(row.name)
                        if !row.enabled {
                            Text("已关闭")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(row.fan)
                            .monospacedDigit()
                            .foregroundStyle(row.enabled ? Color.secondary : Color.secondary.opacity(0.5))
                    }
                    if let note = row.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .opacity(row.enabled ? 1 : 0.55)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(RuleSettingsStore())
}

// MARK: - 番型一览（国标 81 种）

/// 国标 81 种番型，按分值分档列出，点开看含义
struct MCRFanReferenceView: View {
    @State private var explainName: String?

    var body: some View {
        List {
            Section {
                Text("国标起和 8 分：一副牌的番分（不含花牌）达到 8 分才能和。番型之间遵守不重复计算原则——已经被高番型「包含」的低番型不再另计。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(MCRFanInfo.groups, id: \.points) { group in
                Section("\(group.points) 分") {
                    ForEach(group.names, id: \.self) { name in
                        Button {
                            explainName = name
                        } label: {
                            HStack(spacing: 6) {
                                Text(ContentView.localizedFanName(MCRFanInfo.displayKey(name)))
                                    .foregroundStyle(.primary)
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Text("\(group.points) 分")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("番型一览")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            explainName.map { ContentView.localizedFanName(MCRFanInfo.displayKey($0)) } ?? "",
            isPresented: Binding(get: { explainName != nil },
                                 set: { if !$0 { explainName = nil } })
        ) {
            Button("完成", role: .cancel) {}
        } message: {
            if let name = explainName, let text = MCRFanInfo.explanation(name) {
                Text(verbatim: text)
            }
        }
    }
}
