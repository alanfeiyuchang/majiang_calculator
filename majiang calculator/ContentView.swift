//
//  ContentView.swift
//  majiang calculator
//

import SwiftUI
import PhotosUI
import AVFoundation
import CoreMotion
import Combine

// MARK: - Design

private enum Theme {
    static let accent = Color(red: 0.22, green: 0.48, blue: 0.96)
    static let cardRadius: CGFloat = 20
    static let sectionSpacing: CGFloat = 16
}

// MARK: - 手牌 / 听牌块

private struct MahjongTileChip: View {
    let card: MahjongCard
    var onTap: (() -> Void)? = nil
    var large: Bool = false

    /// 牌面宽度（高度按真实麻将牌 3:4 比例）
    private var width: CGFloat { large ? 46 : 38 }
    private var height: CGFloat { width * 4 / 3 }
    private var cornerRadius: CGFloat { width * 0.16 }

    var body: some View {
        Group {
            if card.hasImageAsset {
                Image(card.assetName)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
            } else {
                TileFaceText(card: card)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.28), lineWidth: 1.25)
        }
        .shadow(color: .black.opacity(0.2), radius: 2.5, x: 0, y: 1.5)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture { onTap?() }
        .accessibilityLabel(card.displayText)
    }
}

/// 字牌 / 花牌没有牌面图（YOLO 模型也认不出），用象牙底 + 单字画一张
private struct TileFaceText: View {
    let card: MahjongCard

    /// 中红、发绿、白蓝框；风牌墨黑；花牌用暖色
    private var inkColor: Color {
        switch card.suit {
        case .jian:
            switch card.rank {
            case 1: return Color(red: 0.80, green: 0.16, blue: 0.16)   // 中
            case 2: return Color(red: 0.10, green: 0.52, blue: 0.28)   // 发
            default: return Color(red: 0.20, green: 0.40, blue: 0.78)  // 白
            }
        case .hua: return Color(red: 0.85, green: 0.45, blue: 0.10)
        default: return Color(red: 0.16, green: 0.16, blue: 0.18)
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.99, green: 0.98, blue: 0.94),
                             Color(red: 0.94, green: 0.92, blue: 0.86)],
                    startPoint: .top, endPoint: .bottom
                )
                Text(verbatim: card.rankHanDigit)
                    .font(.system(size: geo.size.height * 0.5, weight: .bold))
                    .foregroundStyle(inkColor)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
    }
}

// MARK: - 分区卡片

private struct SectionCard<Content: View>: View {
    var title: LocalizedStringKey
    var systemImage: String?
    var accessory: Text?
    @ViewBuilder let content: Content

    init(
        title: LocalizedStringKey,
        systemImage: String? = nil,
        accessory: Text? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if let accessory {
                    accessory
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

// MARK: - 副露块

private struct MeldChipGroup: View {
    let meld: Meld
    var onRemove: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                ForEach(Array(meld.tiles.enumerated()), id: \.offset) { _, tile in
                    MahjongTileChip(card: tile, onTap: onRemove)
                }
            }
            Text(LocalizedStringKey(meld.kind.rawValue))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Self.deleteLabel(meld)))
    }

    /// 「删除 <碰/明杠/暗杠><牌>」，走应用内语言
    private static func deleteLabel(_ meld: Meld) -> String {
        let b = appLanguageBundle()
        let kind = String(localized: String.LocalizationValue(meld.kind.rawValue), bundle: b)
        return String(localized: "删除 \(kind)\(meld.card.displayText)", bundle: b)
    }
}

// MARK: - 键盘输入去向

private enum InputTarget: String, CaseIterable {
    case hand = "手牌"
    case chow = "吃"
    case pong = "碰"
    case exposedKong = "明杠"
    case concealedKong = "暗杠"

    var meldKind: Meld.Kind? {
        switch self {
        case .hand: return nil
        case .chow: return .chow
        case .pong: return .pong
        case .exposedKong: return .exposedKong
        case .concealedKong: return .concealedKong
        }
    }

    /// 该玩法下可选的输入去向（吃只在国标出现）
    static func cases(for mode: GameMode) -> [InputTarget] {
        mode.isMCR ? allCases : allCases.filter { $0 != .chow }
    }
}

// MARK: - 主界面

struct ContentView: View {
    @StateObject private var viewModel = MahjongViewModel()
    @EnvironmentObject private var ruleStore: RuleSettingsStore
    @EnvironmentObject private var langManager: LanguageManager
    @State private var keyboardSuit: MahjongCard.Suit = .wan
    /// 底部键盘点牌加到哪：手牌 / 碰 / 明杠 / 暗杠
    @State private var inputTarget: InputTarget = .hand
    @State private var showSettings = false
    /// 听牌金额按 点炮 / 自摸 显示
    @State private var showSelfDraw = false
    // 场景番勾选（自摸侧：杠上开花 / 海底捞月 / 天胡；点炮侧：杠上炮 / 抢杠胡 / 地胡）
    @State private var kongBloom = false
    @State private var lastTileDraw = false
    @State private var heavenly = false
    @State private var kongDischargeWin = false
    @State private var robbingKong = false
    @State private var earthly = false
    // 国标场景番勾选（自摸侧：杠上开花 / 妙手回春；点炮侧：海底捞月 / 抢杠和；两侧通用：和绝张）
    @State private var mcrLastTileDraw = false
    @State private var mcrLastDiscard = false
    @State private var mcrRobbingKong = false
    @State private var mcrLastTileOfKind = false
    /// 点击听牌弹出番型明细
    @State private var breakdownCard: MahjongCard?
    /// DEBUG 截图用：直接以 sheet 呈现番型一览
    @State private var demoShowFanReference = false

    // AI 识别相关（本地 ONNX 模型）
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    /// 选中/拍摄后待裁剪的图片（裁剪到只剩自己的手牌再识别）
    @State private var pendingCrop: PendingImage?

    private let handColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    /// 当前玩法（四川 / 国标）
    private var gameMode: GameMode { ruleStore.settings.gameMode }

    /// 标题：「听牌计算器 · 川麻 / 国标」。
    /// 拼好整句再交给 Text，是为了让 xcstrings 里存的是完整句子——
    /// 英文里 "Tenpai Calculator · Sichuan" 的语序和中文一致，但别的语言未必。
    private var titleKey: LocalizedStringKey {
        gameMode.isMCR ? "听牌计算器 · 国标" : "听牌计算器 · 川麻"
    }

    /// 标题行本身就是切玩法的按钮。
    /// 两种玩法都带后缀——只有一边有后缀的话，「没后缀」本身成了一种状态，看不出能切。
    /// 用自绘而不是 .toolbarTitleMenu：后者在大标题上不给任何可点提示。
    private var titleMenu: some View {
        Menu {
            ForEach(GameMode.allCases, id: \.self) { mode in
                Button {
                    ruleStore.settings.gameMode = mode
                } label: {
                    if gameMode == mode {
                        Label(LocalizedStringKey(mode.label), systemImage: "checkmark")
                    } else {
                        Text(LocalizedStringKey(mode.label))
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(titleKey)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)
                    // 英文标题（Tenpai Calculator · Sichuan）比中文长得多，
                    // 不锁一行会折成两行、箭头吊在第一行旁边。
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Image(systemName: "chevron.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("切换玩法"))
        .accessibilityValue(Text(LocalizedStringKey(gameMode.label)))
    }

    /// 切玩法后把只属于上一个玩法的键盘状态收回来
    private func syncGameMode(_ mode: GameMode) {
        viewModel.gameMode = mode
        if !mode.suits.contains(keyboardSuit) { keyboardSuit = .wan }
        if !InputTarget.cases(for: mode).contains(inputTarget) { inputTarget = .hand }
    }

    // 返回 LocalizedStringKey 而不是 String：Text(String) 不查本地化表，
    // 英文界面下会一直显示中文。
    private var countHint: (LocalizedStringKey, Color) {
        let n = viewModel.handTiles.count
        let green = Color(red: 0.2, green: 0.72, blue: 0.45)
        if n == 0 { return ("选入手牌", .secondary) }
        switch n % 3 {
        case 1: return ("可算向听 / 听牌", green)
        case 2: return ("可给打牌建议", green)
        default: return ("再选 1 张", .orange)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Theme.sectionSpacing) {
                        titleMenu
                        handSection
                        meldSection
                        analyzeButton
                        recognitionNoticeBanner
                        resultSection
                            .id("result")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
                .onChange(of: viewModel.hasAnalyzed) { _, analyzed in
                    if analyzed {
                        scrollToResult(proxy)
                        SpeechAnnouncer.shared.speak(SpokenSummary.segments(for: spokenState))
                    } else {
                        // 手牌变了：上一局的场景番勾选作废
                        kongBloom = false; lastTileDraw = false; heavenly = false
                        kongDischargeWin = false; robbingKong = false; earthly = false
                        mcrLastTileDraw = false; mcrLastDiscard = false
                        mcrRobbingKong = false; mcrLastTileOfKind = false
                    }
                }
                .onChange(of: ruleStore.settings.gameMode) { _, mode in
                    syncGameMode(mode)
                }
                .onChange(of: viewModel.hintMessage) { _, hint in
                    if hint != nil { scrollToResult(proxy) }
                }
                .onAppear {
                    syncGameMode(ruleStore.settings.gameMode)
                    if viewModel.hasAnalyzed { scrollToResult(proxy) }
#if DEBUG
                    // UI 调试（配合 MahjongViewModel 的 DEMO_HAND）：
                    // DEMO_SETTINGS=1 直接打开设置页（=fans 再进番型一览）；
                    // DEMO_SHEET=8s 弹出听某张牌的番型明细
                    let env = ProcessInfo.processInfo.environment
                    if env["DEMO_SETTINGS"] == "fans" {
                        demoShowFanReference = true
                    } else if env["DEMO_SETTINGS"] == "1" {
                        showSettings = true
                    } else if let spec = env["DEMO_SHEET"], spec.count >= 2,
                              let rank = spec.first?.wholeNumberValue {
                        let suit: MahjongCard.Suit = spec.hasSuffix("m") ? .wan
                            : (spec.hasSuffix("p") ? .tong : .tiao)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            breakdownCard = MahjongCard(suit: suit, rank: rank)
                        }
                    }
#endif
                }
            }
            .scrollIndicators(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
            // 标题由 titleMenu 自绘（见下），这里把系统标题让开。
            // 试过 .toolbarTitleMenu，大标题上不显示任何可点提示，用户看不出来能点。
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.medium))
                    }
                    .accessibilityLabel("规则设置")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { langManager.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                            Text(verbatim: langManager.toggleLabel)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityLabel(Text("切换语言"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.reset()
                    } label: {
                        Image(systemName: "trash")
                            .font(.body.weight(.medium))
                    }
                    .disabled(viewModel.selectedTiles.isEmpty && viewModel.melds.isEmpty
                              && viewModel.waitingTiles.isEmpty)
                    .accessibilityLabel("清空全部")
                }
            }
            .overlay { if viewModel.isRecognizing { recognizingOverlay } }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(onPickFromLibrary: {
                showSettings = false
                // 等设置页关闭后再打开相册选择器，避免「已在展示」冲突
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showPhotoPicker = true
                }
            })
        }
        .sheet(isPresented: $demoShowFanReference) {
            NavigationStack {
                if gameMode.isMCR {
                    MCRFanReferenceView()
                } else {
                    FanReferenceView(settings: ruleStore.settings)
                }
            }
        }
        .sheet(item: $breakdownCard) { card in
            if gameMode.isMCR {
                MCRFanBreakdownSheet(
                    card: card,
                    scoreDiscard: mcrScore(adding: card, selfDrawn: false),
                    scoreSelf: mcrScore(adding: card, selfDrawn: true)
                )
                .presentationDetents([.medium, .large])
            } else {
                FanBreakdownSheet(
                    card: card,
                    scoreDiscard: winScore(adding: card, selfDrawn: false),
                    scoreSelf: winScore(adding: card, selfDrawn: true)
                )
                .presentationDetents([.medium, .large])
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                let data = try? await newItem.loadTransferable(type: Data.self)
                photoItem = nil
                if let data, let image = UIImage(data: data) {
                    pendingCrop = PendingImage(image: image, source: .library)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { image in
                showCamera = false
                pendingCrop = PendingImage(image: image, source: .camera)
            } onCancel: {
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $pendingCrop) { item in
            CropView(image: item.image, source: item.source,
                     suggestRegion: { await viewModel.suggestHandRegion(for: $0) }) {
                pendingCrop = nil
            } onRetake: {
                let source = item.source
                pendingCrop = nil
                // 等裁剪页关闭后再重新打开来源，避免「已在展示」冲突
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    switch source {
                    case .camera: showCamera = true
                    case .library: showPhotoPicker = true
                    }
                }
            } onCrop: { cropped in
                pendingCrop = nil
                if let data = cropped.jpegData(compressionQuality: 0.9) {
                    Task { await viewModel.recognizeAndCalculate(imageData: data) }
                }
            }
        }
    }

    /// 分析结束后把结果区滚进视野（等布局稳定后再滚）
    private func scrollToResult(_ proxy: ScrollViewProxy) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["DEMO_NOSCROLL"] == "1" { return }
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo("result", anchor: .top)
            }
        }
    }

    private var recognizingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("AI 正在识别牌面…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }

    // MARK: 手牌区

    private var handSection: some View {
        SectionCard(
            title: "手里的牌",
            systemImage: "square.grid.3x3.fill",
            accessory: Text("\(viewModel.handTiles.count) / \(viewModel.maxConcealed)")
                .monospacedDigit()
        ) {
            let (hint, hintColor) = countHint
            HStack {
                Text(hint)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hintColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule()
                            .fill(hintColor.opacity(0.12))
                    }
                Spacer()
                Button {
                    viewModel.sortSelected()
                } label: {
                    Label("自动排序", systemImage: "arrow.up.arrow.down.circle")
                        .font(.caption.weight(.semibold))
                }
                .disabled(viewModel.selectedTiles.count <= 1)
                .buttonStyle(.borderless)
                .tint(Theme.accent)
                Button {
                    viewModel.undoLast()
                } label: {
                    Label("撤销", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                }
                .disabled(viewModel.selectedTiles.isEmpty)
                .buttonStyle(.borderless)
                .tint(.secondary)
            }

            if viewModel.selectedTiles.isEmpty {
                ContentUnavailableView {
                    Label("尚未选牌", systemImage: "hand.tap")
                } description: {
                    Text("在底部选择花色与点数加入；点击已选牌可删除")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: handColumns, spacing: 8) {
                    ForEach(viewModel.selectedTiles) { item in
                        MahjongTileChip(card: item.card, onTap: {
                            viewModel.removeTile(item)
                        }, large: true)
                    }
                }
            }
        }
    }

    // MARK: 分析按钮（手牌区 + 桌上副露区之后，结果区之前）

    private var analyzeButton: some View {
        Button {
            viewModel.completeCalculation()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text("分析手牌")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .disabled(viewModel.selectedTiles.isEmpty || viewModel.isRecognizing)
    }

    /// 拍照识别后的非阻塞提示（不挡结果，只是提醒核对）
    @ViewBuilder
    private var recognitionNoticeBanner: some View {
        if let notice = viewModel.recognitionNotice {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.orange)
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
            }
        }
    }

    // MARK: 桌上副露区

    private var meldSection: some View {
        SectionCard(
            title: gameMode.isMCR ? "桌上的牌（吃 / 碰 / 杠）" : "桌上的牌（碰 / 杠）",
            systemImage: "square.stack.3d.up.fill",
            accessory: Text("\(viewModel.melds.count) / 4 组").monospacedDigit()
        ) {
            if viewModel.melds.isEmpty {
                Text(gameMode.isMCR
                     ? "已吃、已碰、已杠的牌放这里：底部切到「吃 / 碰 / 明杠 / 暗杠」后点牌加入。吃只能吃上家，但本工具不强制这一条——请自行确认这副吃是合法的。"
                     : "已碰、已杠的牌放这里：底部切到「碰 / 明杠 / 暗杠」后点牌加入。")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            } else {
                FlowWaitingLayout(spacing: 14) {
                    ForEach(viewModel.melds) { meld in
                        MeldChipGroup(meld: meld) {
                            viewModel.removeMeld(meld)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: 算番（听牌金额 / 已和结算随规则设置即时刷新）

    private var hasKongMeld: Bool {
        viewModel.melds.contains { $0.kind.isKong }
    }

    private var kongBloomAvailable: Bool {
        hasKongMeld && ruleStore.settings.kongBloomEnabled
    }

    /// 当前勾选的场景番组成胡牌上下文
    private func winContext(selfDrawn: Bool) -> WinContext {
        WinContext(
            selfDrawn: selfDrawn,
            kongBloom: selfDrawn && kongBloom && kongBloomAvailable,
            lastTileDraw: selfDrawn && lastTileDraw,
            kongDischargeWin: !selfDrawn && kongDischargeWin,
            robbingKong: !selfDrawn && robbingKong,
            heavenly: selfDrawn && heavenly,
            earthly: !selfDrawn && earthly
        )
    }

    /// 手牌补上 card 后这副胡牌的番与钱
    private func winScore(adding card: MahjongCard, selfDrawn: Bool? = nil) -> WinScore {
        var freq = handToFrequency27(viewModel.handTiles)
        if card.tileIndex >= 0 { freq[card.tileIndex] += 1 }
        return scoreWinningHand(
            concealed: freq,
            melds: viewModel.melds,
            settings: ruleStore.settings,
            context: winContext(selfDrawn: selfDrawn ?? showSelfDraw)
        )
    }

    // MARK: - 语音播报

    /// 播报用的状态快照。番/钱走界面同一套算法与排序，
    /// 免得「说出来的」和「屏幕上显示的」对不上。
    private var spokenState: SpokenState {
        var st = SpokenState(mode: gameMode, shanten: viewModel.shantenValue)
        st.isDeadWait = viewModel.isDeadWait
        if let hint = viewModel.hintMessage { st.blockingHint = hint }

        if viewModel.shantenValue == 0 {
            st.waits = viewModel.waitingTiles.map { card in
                gameMode.isMCR
                    ? SpokenWait(card: card, money: nil, fan: mcrScore(adding: card).totalPoints)
                    : SpokenWait(card: card, money: winScore(adding: card).money, fan: nil)
            }
        } else if !viewModel.discards.isEmpty {
            // 取界面上排第一的那条建议
            let top: DiscardSuggestion? = gameMode.isMCR
                ? mcrEvaluateDiscards(viewModel.discards, cards: viewModel.handTiles,
                                      melds: viewModel.melds, settings: ruleStore.settings,
                                      flowers: viewModel.flowerTiles.count).first?.suggestion
                : evaluateDiscards(viewModel.discards, cards: viewModel.handTiles,
                                   melds: viewModel.melds,
                                   settings: ruleStore.settings).first?.suggestion
            if let top {
                st.bestDiscard = top.discard
                st.discardLeadsToTenpai = top.resultingShanten == 0
            }
        }
        return st
    }

    /// 3n+2 已和时整副牌的番与钱
    private func wonScore(selfDrawn: Bool) -> WinScore {
        scoreWinningHand(
            concealed: handToFrequency27(viewModel.handTiles),
            melds: viewModel.melds,
            settings: ruleStore.settings,
            context: winContext(selfDrawn: selfDrawn)
        )
    }

    // MARK: 算番（国标）

    /// 当前勾选的场景番组成国标和牌上下文
    private func mcrContext(selfDrawn: Bool, winningTile: Int) -> MCRContext {
        MCRContext(
            selfDrawn: selfDrawn,
            winningTile: winningTile,
            prevalentWind: ruleStore.settings.mcrPrevalentWind,
            seatWind: ruleStore.settings.mcrSeatWind,
            kongBloom: selfDrawn && kongBloom && hasKongMeld,
            lastTileDraw: selfDrawn && mcrLastTileDraw,
            lastDiscard: !selfDrawn && mcrLastDiscard,
            robbingKong: !selfDrawn && mcrRobbingKong,
            lastTileOfKind: mcrLastTileOfKind,
            flowers: viewModel.flowerTiles.count
        )
    }

    /// 手牌补上 card 后这副国标和牌的番分
    private func mcrScore(adding card: MahjongCard, selfDrawn: Bool? = nil) -> MCRScore {
        var freq = handToFrequency34(viewModel.handTiles)
        let i = card.mcrIndex
        if i >= 0 { freq[i] += 1 }
        return scoreMCRHand(
            concealed: freq,
            melds: viewModel.melds,
            context: mcrContext(selfDrawn: selfDrawn ?? showSelfDraw, winningTile: i),
            options: ruleStore.settings.mcrOptions
        )
    }

    /// 3n+2 已和时整副国标牌的番分。和牌张未知（用户直接输入了整手），按最优解读。
    private func mcrWonScore(selfDrawn: Bool) -> MCRScore {
        scoreMCRHand(
            concealed: handToFrequency34(viewModel.handTiles),
            melds: viewModel.melds,
            context: mcrContext(selfDrawn: selfDrawn, winningTile: -1),
            options: ruleStore.settings.mcrOptions
        )
    }

    // MARK: 结果区

    @ViewBuilder
    private var resultSection: some View {
        if let hint = viewModel.hintMessage {
            SectionCard(title: "提示", systemImage: "exclamationmark.triangle.fill") {
                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if viewModel.hasAnalyzed {
            analysisResult
        } else {
            SectionCard(title: "分析结果", systemImage: "questionmark.circle") {
                Text(gameMode.isMCR
                     ? "选牌后点「分析手牌」：手牌 3n+1 张算听牌/向听，3n+2 张给打牌建议；已吃、已碰、已杠的牌用底部「吃 / 碰 / 明杠 / 暗杠」加到桌上。国标起和 8 分，花牌另计不进起和分。"
                     : "选牌后点「分析手牌」：手牌 3n+1 张算听牌/向听，3n+2 张给打牌建议；已碰、已杠的牌用底部「碰 / 明杠 / 暗杠」加到桌上。")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var analysisResult: some View {
        let sh = viewModel.shantenValue ?? 99
        if sh == -1 {
            wonCard
        } else if !viewModel.discards.isEmpty {
            discardCard
        } else if sh == 0 {
            tenpaiCard
        } else {
            shantenCard
        }
    }

    private static let moneyGreen = Color(red: 0.16, green: 0.65, blue: 0.40)

    // MARK: 番型文字本地化

    /// 番型名（中文 key → 本地化）。走应用内语言 bundle。
    static func localizedFanName(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: appLanguageBundle())
    }
    /// 单项加成文字（+N 番 / +N 底 / 0 番）本地化
    static func fanItemText(_ item: FanItem) -> String {
        let b = appLanguageBundle()
        if item.baseAdd > 0 { return String(localized: "+\(item.baseAdd) 底", bundle: b) }
        if item.fan == 0 { return String(localized: "0 番", bundle: b) }
        return String(localized: "+\(item.fan) 番", bundle: b)
    }
    /// 「N 番」或「N 番·封顶 M」本地化
    static func fanTotalText(_ score: WinScore) -> String {
        let b = appLanguageBundle()
        return score.isCapped
            ? String(localized: "\(score.totalFan) 番·封顶 \(score.cappedFan)", bundle: b)
            : String(localized: "\(score.totalFan) 番", bundle: b)
    }
    /// 一行番型明细：「名 +N 番」
    static func fanLine(_ item: FanItem) -> String {
        "\(localizedFanName(item.name)) \(fanItemText(item))"
    }

    /// 一项国标番型的文字：「名 ×N 8 分」
    static func mcrFanLine(_ item: FanItem) -> String {
        let b = appLanguageBundle()
        let name = localizedFanName(MCRFanInfo.displayKey(item.name))
        let head = item.count > 1 ? "\(name)×\(item.count)" : name
        return "\(head) \(String(localized: "\(item.fan) 分", bundle: b))"
    }

    @ViewBuilder
    private var wonCard: some View {
        if gameMode.isMCR { mcrWonCard } else { sichuanWonCard }
    }

    /// 手牌 + 副露是否凑够真正的一副牌（14 张）。不满时只判牌型，不算番。
    private var isFullMCRHand: Bool {
        viewModel.handTiles.count + 3 * viewModel.melds.count == 14
    }

    /// 3n+1 侧：手牌 + 副露是否凑够 13 张。不满时听牌成立但算不出番分。
    private var isFullMCRTenpai: Bool {
        viewModel.handTiles.count + 3 * viewModel.melds.count == 13
    }

    /// 国标下这次分析能不能给出可信的番分（部分手牌不能）
    private var mcrScoringAvailable: Bool { isFullMCRHand || isFullMCRTenpai }

    // 已和（国标）：番型明细 + 总分 + 起和判定
    @ViewBuilder
    private var mcrWonCard: some View {
        if !isFullMCRHand {
            SectionCard(title: "牌型成立", systemImage: "checkmark.seal.fill") {
                Text("这副牌的牌型能和，但手牌加副露还不满 14 张——缺的面子按「能凑成」处理，所以不算番分。补齐 14 张后才会给出番分与起和判定。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            mcrWonScoreCard
        }
    }

    private var mcrWonScoreCard: some View {
        SectionCard(title: "已和！", systemImage: "checkmark.seal.fill") {
            let scoreDiscard = mcrWonScore(selfDrawn: false)
            let scoreSelf = mcrWonScore(selfDrawn: true)

            mcrSpecialFanChips(selfDrawn: false)
            mcrSpecialFanChips(selfDrawn: true)

            HStack(spacing: 24) {
                mcrPointsColumn("点炮和", scoreDiscard)
                mcrPointsColumn("自摸和", scoreSelf)
            }

            Divider()
            Text(verbatim: scoreDiscard.items.map { Self.mcrFanLine($0) }.joined(separator: " · "))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Self.moneyGreen)
                .fixedSize(horizontal: false, vertical: true)

            Text("国标起和 8 分；花牌每张 1 分但不计入起和分。番型明细按「点炮和」列出。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func mcrPointsColumn(_ titleKey: LocalizedStringKey, _ score: MCRScore) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titleKey)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: Self.mcrTotalText(score))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(score.meetsMinimum ? Self.moneyGreen : .orange)
            if !score.meetsMinimum {
                Text("不够起和")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    /// 「N 分」，含花牌时写成「N 分（含花 M）」
    static func mcrTotalText(_ score: MCRScore) -> String {
        let b = appLanguageBundle()
        let flowers = score.totalPoints - score.scoringPoints
        return flowers > 0
            ? String(localized: "\(score.totalPoints) 分（含花 \(flowers)）", bundle: b)
            : String(localized: "\(score.totalPoints) 分", bundle: b)
    }

    // 已和（四川）：番型 + 结算金额
    private var sichuanWonCard: some View {
        SectionCard(title: "已和！", systemImage: "checkmark.seal.fill") {
            let scoreDiscard = wonScore(selfDrawn: false)
            let scoreSelf = wonScore(selfDrawn: true)

            Text(verbatim: scoreDiscard.items.map { Self.fanLine($0) }.joined(separator: " · "))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Self.moneyGreen)
                .fixedSize(horizontal: false, vertical: true)

            specialFanChips(selfDrawn: false)
            specialFanChips(selfDrawn: true)

            HStack(spacing: 24) {
                settleColumn("点炮（放炮者付）", scoreDiscard)
                settleColumn("自摸（三家各付）", scoreSelf)
            }
        }
    }

    private func settleColumn(_ titleKey: LocalizedStringKey, _ score: WinScore) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titleKey)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: "\(Self.fanTotalText(score)) \(moneyText(score.money))")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Self.moneyGreen)
        }
    }

    /// 一行场景番勾选胶囊（点炮侧 / 自摸侧各一组）
    @ViewBuilder
    private func specialFanChips(selfDrawn: Bool) -> some View {
        HStack(spacing: 8) {
            Text(selfDrawn ? LocalizedStringKey("自摸时") : LocalizedStringKey("点炮时"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            if selfDrawn {
                if kongBloomAvailable { fanChip("杠上开花", $kongBloom) }
                fanChip("海底捞月", $lastTileDraw)
                fanChip("天胡", $heavenly)
            } else {
                fanChip("杠上炮", $kongDischargeWin)
                fanChip("抢杠胡", $robbingKong)
                fanChip("地胡", $earthly)
            }
            Spacer(minLength: 0)
        }
    }

    /// 一行国标场景番勾选胶囊
    @ViewBuilder
    private func mcrSpecialFanChips(selfDrawn: Bool) -> some View {
        HStack(spacing: 8) {
            Text(selfDrawn ? LocalizedStringKey("自摸时") : LocalizedStringKey("点炮时"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            if selfDrawn {
                if hasKongMeld { fanChip("杠上开花", $kongBloom) }
                fanChip("妙手回春", $mcrLastTileDraw)
            } else {
                fanChip("海底捞月（和最后一张打出的牌）", $mcrLastDiscard)
                fanChip("抢杠和", $mcrRobbingKong)
            }
            fanChip("和绝张", $mcrLastTileOfKind)
            Spacer(minLength: 0)
        }
    }

    private func fanChip(_ title: LocalizedStringKey, _ isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule().fill(isOn.wrappedValue ? Theme.accent.opacity(0.16) : Color.primary.opacity(0.05))
                }
                .overlay {
                    Capsule().strokeBorder(
                        isOn.wrappedValue ? Theme.accent : Color.primary.opacity(0.12),
                        lineWidth: 1.2
                    )
                }
                .foregroundStyle(isOn.wrappedValue ? Theme.accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    // 听牌（含空听）：每张听牌标注番数与单家金额
    @ViewBuilder
    private var tenpaiCard: some View {
        if viewModel.isDeadWait {
            SectionCard(title: "听牌（空听）", systemImage: "exclamationmark.triangle.fill") {
                Text("已听牌，但可胡的牌都已在手中（4 张用尽），无法再胡——空听。")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            SectionCard(
                title: "听牌",
                systemImage: "checkmark.seal.fill",
                accessory: Text("共 \(viewModel.waitingTiles.count) 门").monospacedDigit()
            ) {
                Picker("结算方式", selection: $showSelfDraw) {
                    Text(gameMode.isMCR ? "点炮和" : "点炮").tag(false)
                    Text(gameMode.isMCR ? "自摸和" : "自摸").tag(true)
                }
                .pickerStyle(.segmented)

                if gameMode.isMCR {
                    if mcrScoringAvailable { mcrSpecialFanChips(selfDrawn: showSelfDraw) }
                } else {
                    specialFanChips(selfDrawn: showSelfDraw)
                }

                FlowWaitingLayout(spacing: 10) {
                    ForEach(Array(viewModel.waitingTiles.enumerated()), id: \.offset) { _, card in
                        VStack(spacing: 3) {
                            MahjongTileChip(card: card, onTap: {
                                if !gameMode.isMCR || mcrScoringAvailable { breakdownCard = card }
                            }, large: true)
                            if gameMode.isMCR {
                                if mcrScoringAvailable {
                                    let score = mcrScore(adding: card)
                                    Text("\(score.totalPoints) 分")
                                        .font(.caption.weight(.bold).monospacedDigit())
                                        .foregroundStyle(score.meetsMinimum ? Self.moneyGreen : .orange)
                                    if !score.meetsMinimum {
                                        Text("不够起和")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.orange)
                                    }
                                }
                            } else {
                                let score = winScore(adding: card)
                                Text("\(score.totalFan) 番")
                                    .font(.caption2.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(moneyText(score.money))
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Self.moneyGreen)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if gameMode.isMCR {
                    Text(mcrScoringAvailable
                         ? "国标起和 8 分：橙色的听牌即使和了也不够起和。点牌可看番型明细。"
                         : "手牌加副露不满 13 张，缺的面子按「能凑成」处理，所以这里只列听牌不算番分。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(showSelfDraw ? "金额为单家：自摸后三家各付这个数。点牌可看番型明细。"
                                      : "金额为单家：点炮时放炮那家付这个数。点牌可看番型明细。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // 向听 + 进张（3n+1 未听牌）
    private var shantenCard: some View {
        SectionCard(
            title: "向听 \(viewModel.shantenValue ?? 0)",
            systemImage: "target",
            accessory: Text("进张 \(acceptanceTotal) 张").monospacedDigit()
        ) {
            if viewModel.acceptance.isEmpty {
                Text(gameMode.isMCR ? "无有效进张。" : "无有效进张（受缺一门所限）。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                FlowWaitingLayout(spacing: 8) {
                    ForEach(viewModel.acceptance) { item in
                        VStack(spacing: 2) {
                            MahjongTileChip(card: item.card, large: true)
                            Text("剩\(item.remaining)")
                                .font(.caption2.weight(.medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var acceptanceTotal: Int {
        viewModel.acceptance.reduce(0) { $0 + $1.remaining }
    }

    // 打牌建议（3n+2）：每个候选弃牌 → 弃后听牌 + 各自番数，能到的最高番在前
    private var discardCard: some View {
        SectionCard(
            title: "打牌建议",
            systemImage: "hand.point.up.left.fill",
            accessory: Text("\(viewModel.discards.count) 种").monospacedDigit()
        ) {
            if gameMode.isMCR {
                let evaluated = mcrEvaluateDiscards(
                    viewModel.discards,
                    cards: viewModel.handTiles,
                    melds: viewModel.melds,
                    settings: ruleStore.settings,
                    flowers: viewModel.flowerTiles.count
                )
                VStack(spacing: 12) {
                    ForEach(Array(evaluated.prefix(6).enumerated()), id: \.element.id) { index, e in
                        if index > 0 { Divider() }
                        mcrDiscardRow(e)
                    }
                }
                if evaluated.contains(where: { $0.maxPoints >= 0 }) {
                    Text(mcrScoringAvailable
                         ? "分数按点炮和计；自摸、场景番另加。国标起和 8 分。"
                         : "手牌加副露不满 14 张，缺的面子按「能凑成」处理，所以只排向听/进张，不算番分。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                let evaluated = evaluateDiscards(
                    viewModel.discards,
                    cards: viewModel.handTiles,
                    melds: viewModel.melds,
                    settings: ruleStore.settings
                )
                VStack(spacing: 12) {
                    ForEach(Array(evaluated.prefix(6).enumerated()), id: \.element.id) { index, e in
                        if index > 0 { Divider() }
                        discardRow(e)
                    }
                }
                if evaluated.contains(where: { $0.maxFan >= 0 }) {
                    Text("番数与金额按点炮胡、当前规则计；自摸另加。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// 打牌建议单行（国标）：弃牌 + 概览，下面列弃后听牌与各自分数
    @ViewBuilder
    private func mcrDiscardRow(_ e: MCREvaluatedDiscard) -> some View {
        let s = e.suggestion
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("打")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                MahjongTileChip(card: s.discard)
                VStack(alignment: .leading, spacing: 2) {
                    if s.resultingShanten == 0 && e.waitScores.isEmpty {
                        Text("听牌（空听）")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else {
                        Text(s.resultingShanten == 0 ? "听牌" : "向听 \(s.resultingShanten)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(s.resultingShanten == 0 ? Self.moneyGreen : .primary)
                    }
                    Text("进张 \(s.acceptanceCount) 张 · \(s.acceptance.count) 门")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if e.maxPoints >= 0, mcrScoringAvailable {
                    Text("最高 \(e.maxPoints) 分")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(e.maxPoints >= mcrMinimumPoints ? Self.moneyGreen : .orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule().fill((e.maxPoints >= mcrMinimumPoints
                                            ? Self.moneyGreen : Color.orange).opacity(0.12))
                        }
                }
            }
            if !e.waitScores.isEmpty {
                FlowWaitingLayout(spacing: 8) {
                    ForEach(Array(e.waitScores.enumerated()), id: \.offset) { _, ws in
                        VStack(spacing: 2) {
                            MahjongTileChip(card: ws.card)
                            if mcrScoringAvailable {
                                Text("\(ws.score.totalPoints) 分")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(ws.score.meetsMinimum ? Self.moneyGreen : .orange)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 30)
            }
        }
    }

    /// 打牌建议单行：弃牌 + 概览，下面列弃后听牌与各自番数/金额
    @ViewBuilder
    private func discardRow(_ e: EvaluatedDiscard) -> some View {
        let s = e.suggestion
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("打")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                MahjongTileChip(card: s.discard)
                VStack(alignment: .leading, spacing: 2) {
                    if s.resultingShanten == 0 && e.waitScores.isEmpty {
                        Text("听牌（空听）")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else {
                        Text(s.resultingShanten == 0 ? "听牌" : "向听 \(s.resultingShanten)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(s.resultingShanten == 0 ? Self.moneyGreen : .primary)
                    }
                    Text("进张 \(s.acceptanceCount) 张 · \(s.acceptance.count) 门")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if e.maxFan >= 0 {
                    Text("最高 \(e.maxFan) 番")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Self.moneyGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule().fill(Self.moneyGreen.opacity(0.12))
                        }
                }
            }
            if !e.waitScores.isEmpty {
                FlowWaitingLayout(spacing: 8) {
                    ForEach(Array(e.waitScores.enumerated()), id: \.offset) { _, ws in
                        VStack(spacing: 2) {
                            MahjongTileChip(card: ws.card)
                            Text("\(ws.score.totalFan) 番")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(moneyText(ws.score.money))
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(Self.moneyGreen)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 30)
            }
        }
    }

    // MARK: 底部：操作 + 键盘

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    // 直接开相机；没有相机硬件时（模拟器）退回相册，避免黑屏死路
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showCamera = true
                    } else {
                        showPhotoPicker = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                        Text("拍照识别手牌")
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
                .disabled(viewModel.isRecognizing)

                HStack(spacing: 10) {
                    Text("点选加入")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .padding(.horizontal, 4)
                    Spacer(minLength: 0)
                    Picker("加入到", selection: $inputTarget) {
                        ForEach(InputTarget.cases(for: gameMode), id: \.self) { target in
                            Text(LocalizedStringKey(target.rawValue)).tag(target)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: gameMode.isMCR ? 320 : 270)
                }

                suitPicker

                if inputTarget == .chow {
                    Text("吃：点起始牌，自动配成连续三张（如点「3万」= 吃 345 万）。分析工具不限制只能吃上家。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    ForEach(1...keyboardSuit.rankCount, id: \.self) { r in
                        let card = MahjongCard(suit: keyboardSuit, rank: r)
                        let enabled = keyboardCanAdd(card)
                        Button {
                            if let kind = inputTarget.meldKind {
                                viewModel.addMeld(kind, of: card)
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    inputTarget = .hand
                                }
                            } else {
                                viewModel.addCard(card)
                            }
                        } label: {
                            Group {
                                if card.hasImageAsset {
                                    Image(card.assetName)
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                                } else {
                                    TileFaceText(card: card)
                                }
                            }
                            .frame(height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color.black.opacity(0.28), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                            .frame(maxWidth: .infinity)
                            .opacity(enabled ? 1 : 0.35)
                        }
                        .buttonStyle(.plain)
                        .disabled(!enabled)
                    }
                    // 风(4)/箭(3) 比数牌少，补空位撑住等宽布局
                    if keyboardSuit.rankCount < 9 {
                        ForEach(0..<(9 - keyboardSuit.rankCount), id: \.self) { _ in
                            Color.clear.frame(height: 52).frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
        }
    }

    private var suitPicker: some View {
        HStack(spacing: 8) {
            ForEach(gameMode.suits, id: \.self) { suit in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        keyboardSuit = suit
                    }
                } label: {
                    Text(suit.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(keyboardSuit == suit ? suitColor(suit).opacity(0.22) : Color.clear)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    keyboardSuit == suit ? suitColor(suit) : Color.primary.opacity(0.08),
                                    lineWidth: keyboardSuit == suit ? 2 : 1
                                )
                        }
                        .foregroundStyle(keyboardSuit == suit ? suitColor(suit) : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 当前输入去向下，键盘上这张牌能不能点
    private func keyboardCanAdd(_ card: MahjongCard) -> Bool {
        if let kind = inputTarget.meldKind {
            return viewModel.canAddMeld(kind, of: card)
        }
        // 花牌不占手牌名额（手牌满了也还能补花），每种只有一张
        if card.suit.isFlower {
            return gameMode.isMCR && viewModel.usedCount(of: card) < 1
        }
        return viewModel.canAddMore && viewModel.usedCount(of: card) < 4
    }

    private func suitColor(_ suit: MahjongCard.Suit) -> Color {
        switch suit {
        case .wan: return Color(red: 0.88, green: 0.28, blue: 0.24)
        case .tong: return Color(red: 0.18, green: 0.48, blue: 0.88)
        case .tiao: return Color(red: 0.15, green: 0.62, blue: 0.36)
        case .feng: return Color(red: 0.36, green: 0.36, blue: 0.42)
        case .jian: return Color(red: 0.70, green: 0.30, blue: 0.62)
        case .hua: return Color(red: 0.85, green: 0.55, blue: 0.10)
        }
    }
}

// MARK: - 番型含义

/// 番型 → 一句话含义（key 为中文，随应用内语言本地化）
enum FanInfo {
    private static let table: [String: String.LocalizationValue] = [
        "平胡": "普通牌型，没有特殊番型，0 番。",
        "碰碰胡": "四副面子全是刻子（碰 / 杠），没有顺子。",
        "清一色": "整副牌只用一种花色（全万 / 全筒 / 全条）。",
        "七小对": "由 7 个对子组成（非标准面子牌型）。",
        "豪华七小对": "七小对里有 1 个「龙」（4 张相同），每多一龙再 +1 番。",
        "双豪华七小对": "七小对里有 2 个「龙」（各 4 张相同）。",
        "三豪华七小对": "七小对里有 3 个「龙」（各 4 张相同）。",
        "门清": "没有碰、没有明杠（暗杠可以），点炮或自摸都算。",
        "断幺九": "整副牌完全没有 1 和 9。",
        "金钩钓": "四副都已碰 / 杠，手里只剩一对单钓将；已含碰碰胡。",
        "将对": "碰碰胡，且所有牌都是 2 / 5 / 8。",
        "将七对": "七小对，且所有牌都是 2 / 5 / 8。",
        "十八罗汉": "金钩钓且四副都是杠（4 个杠 = 4 根）。",
        "根": "凑齐 4 张相同的牌（杠 / 手握 4 张 / 碰 + 第 4 张）。",
        "自摸": "自己摸到胡的那张牌。",
        "杠上开花": "开杠后补摸到的那张牌自摸胡。",
        "海底捞月": "摸走最后一张牌自摸胡。",
        "天胡": "庄家起手（发完牌）即胡。",
        "杠上炮": "别家开杠后打出的牌被你胡。",
        "抢杠胡": "别家补杠的那张牌正是你要胡的，抢过来胡。",
        "地胡": "闲家胡第一圈打出的第一张牌。",
    ]

    /// 番型名（如「根」）的含义；未知则 nil
    static func explanation(_ name: String) -> String? {
        guard let value = table[name] else { return nil }
        return String(localized: value, bundle: appLanguageBundle())
    }
}

// MARK: - 番型明细

private struct FanBreakdownSheet: View {
    let card: MahjongCard
    /// 点炮结算（其番型项即基础番型）
    let scoreDiscard: WinScore
    /// 自摸结算（含自摸/杠上开花加成）
    let scoreSelf: WinScore
    @Environment(\.dismiss) private var dismiss
    /// 点开番型的解释
    @State private var explainItem: FanItem?

    private static let moneyGreen = Color(red: 0.16, green: 0.65, blue: 0.40)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        MahjongTileChip(card: card, large: true)
                        Text("胡「\(card.displayText)」")
                            .font(.headline)
                    }
                    .listRowBackground(Color.clear)
                }

                Section("结算（单家）") {
                    settleRow("点炮 · 放炮者付", scoreDiscard)
                    settleRow("自摸 · 三家各付", scoreSelf)
                }

                Section {
                    ForEach(scoreDiscard.items) { item in
                        let hasInfo = FanInfo.explanation(item.name) != nil
                        Button {
                            if hasInfo { explainItem = item }
                        } label: {
                            HStack(spacing: 6) {
                                Text(ContentView.localizedFanName(item.name))
                                    .foregroundStyle(.primary)
                                if hasInfo {
                                    Image(systemName: "info.circle")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Text(ContentView.fanItemText(item))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())   // 整行（含中间空白）都可点
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasInfo)
                    }
                } header: {
                    Text("番型")
                } footer: {
                    Text("点番型看含义")
                }
            }
            .navigationTitle("番型明细")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert(
                explainItem.map { ContentView.localizedFanName($0.name) } ?? "",
                isPresented: Binding(get: { explainItem != nil },
                                     set: { if !$0 { explainItem = nil } })
            ) {
                Button("完成", role: .cancel) {}
            } message: {
                if let item = explainItem, let text = FanInfo.explanation(item.name) {
                    Text(verbatim: text)
                }
            }
        }
    }

    private func settleRow(_ titleKey: LocalizedStringKey, _ score: WinScore) -> some View {
        HStack {
            Text(titleKey)
            Spacer()
            Text(verbatim: "\(ContentView.fanTotalText(score)) \(moneyText(score.money))")
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(Self.moneyGreen)
        }
    }
}

// MARK: - 番型明细（国标）

private struct MCRFanBreakdownSheet: View {
    let card: MahjongCard
    /// 点炮和
    let scoreDiscard: MCRScore
    /// 自摸和
    let scoreSelf: MCRScore
    @Environment(\.dismiss) private var dismiss
    @State private var explainItem: FanItem?

    private static let moneyGreen = Color(red: 0.16, green: 0.65, blue: 0.40)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        MahjongTileChip(card: card, large: true)
                        Text("和「\(card.displayText)」")
                            .font(.headline)
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    pointsRow("点炮和", scoreDiscard)
                    pointsRow("自摸和", scoreSelf)
                } header: {
                    Text("番分")
                } footer: {
                    Text("国标起和 8 分；花牌每张 1 分但不计入起和分。")
                }

                Section {
                    ForEach(scoreDiscard.items) { item in
                        let hasInfo = MCRFanInfo.explanation(item.name) != nil
                        Button {
                            if hasInfo { explainItem = item }
                        } label: {
                            HStack(spacing: 6) {
                                Text(ContentView.localizedFanName(MCRFanInfo.displayKey(item.name)))
                                    .foregroundStyle(.primary)
                                if item.count > 1 {
                                    Text(verbatim: "×\(item.count)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                if hasInfo {
                                    Image(systemName: "info.circle")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Text("\(item.fan) 分")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasInfo)
                    }
                } header: {
                    Text("番型（按点炮和）")
                } footer: {
                    Text("点番型看含义")
                }
            }
            .navigationTitle("番型明细")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert(
                explainItem.map { ContentView.localizedFanName(MCRFanInfo.displayKey($0.name)) } ?? "",
                isPresented: Binding(get: { explainItem != nil },
                                     set: { if !$0 { explainItem = nil } })
            ) {
                Button("完成", role: .cancel) {}
            } message: {
                if let item = explainItem, let text = MCRFanInfo.explanation(item.name) {
                    Text(verbatim: text)
                }
            }
        }
    }

    private func pointsRow(_ titleKey: LocalizedStringKey, _ score: MCRScore) -> some View {
        HStack {
            Text(titleKey)
            Spacer()
            Text(verbatim: ContentView.mcrTotalText(score))
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(score.meetsMinimum ? Self.moneyGreen : .orange)
            if !score.meetsMinimum {
                Text("不够起和")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - 听牌流式换行

private struct FlowWaitingLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (i, frame) in result.frames.enumerated() {
            subviews[i].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var frames: [CGRect] = []

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxW, x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }

        let totalH = y + rowH
        return (CGSize(width: maxW, height: totalH), frames)
    }
}

// MARK: - 相机（AVFoundation 自定义拍摄，拍完直接进裁剪，无「重拍/使用照片」确认步骤）

private final class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "camera.session")
    private var configured = false

    var onCapture: ((UIImage) -> Void)?
    /// 拍摄时的旋转角度
    var captureAngle: CGFloat = 90

    // 用重力（加速度计）判断手机实际朝向——即使界面锁定竖屏也有效
    private let motion = CMMotionManager()
    /// 由重力推得的拍摄旋转角（0 / 90 / 180 / 270）
    private(set) var gravityCaptureAngle: CGFloat = 90

    func startMotion() {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive else { return }
        motion.accelerometerUpdateInterval = 0.1
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let a = data?.acceleration else { return }
            // 平放时 |x|、|y| 都很小 → 保持上一次朝向，避免乱跳
            if abs(a.y) >= abs(a.x) {
                if abs(a.y) > 0.4 { self?.gravityCaptureAngle = a.y < 0 ? 90 : 270 }   // 竖握 / 倒握
            } else {
                if abs(a.x) > 0.4 { self?.gravityCaptureAngle = a.x < 0 ? 0 : 180 }    // 横握两方向（如颠倒，把 0/180 对调）
            }
        }
    }

    func stopMotion() { motion.stopAccelerometerUpdates() }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.run() }
            }
        default:
            break   // 被拒绝：预览为黑，用户需到系统设置开启
        }
    }

    private func run() {
        queue.async {
            if !self.configured { self.configure(); self.configured = true }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
    }

    func capture() {
        queue.async {
            if let conn = self.output.connection(with: .video),
               conn.isVideoRotationAngleSupported(self.captureAngle) {
                conn.videoRotationAngle = self.captureAngle
            }
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { self.onCapture?(image) }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        // .resizeAspect：完整显示拍摄画幅（按比例留黑边），避免 .resizeAspectFill 裁边导致
        // 取景框比实际拍到的画面「更窄」——之前拍完看裁剪页会发现四周多出内容，就是这个不一致。
        v.videoPreviewLayer.videoGravity = .resizeAspect
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

private struct CameraView: View {
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void
    @StateObject private var model = CameraModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: model.session)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button { onCancel() } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    Spacer()
                }
                .padding()

                Spacer()

                Button {
                    model.captureAngle = model.gravityCaptureAngle
                    model.capture()
                } label: {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 5).frame(width: 76, height: 76)
                        Circle().fill(.white).frame(width: 62, height: 62)
                    }
                }
                .padding(.bottom, 36)
                .accessibilityLabel("拍照")
            }
        }
        .onAppear {
            model.onCapture = { onCapture($0) }
            model.start()
            model.startMotion()
        }
        .onDisappear {
            model.stopMotion()
            model.stop()
        }
    }
}

// MARK: - 裁剪到手牌

enum ImageSource { case camera, library }

struct PendingImage: Identifiable {
    let id = UUID()
    let image: UIImage
    let source: ImageSource
}

/// 进页面先跑一遍粗检，自动把选框画在「自己的牌」上（含碰/杠），
/// 框得不准用户可以拖动四角调整或重画——避免把牌桌上其他人的牌、牌墙、弃牌也识别进来。
private struct CropView: View {
    let image: UIImage
    let source: ImageSource
    /// 返回「自己的牌」区域的相对位置（0…1，左上原点）；nil = 没定位到，退回手动框选
    var suggestRegion: (UIImage) async -> CGRect?
    var onCancel: () -> Void
    var onRetake: () -> Void
    var onCrop: (UIImage) -> Void

    @State private var working: UIImage? = nil        // 当前（可旋转后）的图片
    @State private var containerSize: CGSize = .zero
    @State private var imageRect: CGRect = .zero    // 图片在视图中的实际显示区域
    @State private var cropRect: CGRect? = nil        // 裁剪框；nil = 未框选，识别整张
    @State private var dragBase: CGRect? = nil        // 移动/缩放手势开始时的快照

    @State private var isSuggesting = false           // 正在自动定位
    @State private var suggestedUnitRect: CGRect? = nil   // 自动定位结果（相对坐标），待 layout 后落到视图坐标
    @State private var didAutoFrame = false           // 本张图是否已自动画过框（用于文案提示）
    @State private var frameToken = 0                 // 自动定位的代次，丢弃被旋转作废的旧结果

    @AppStorage("hasSeenCropTutorial") private var hasSeenCropTutorial = false
    @State private var showTutorialPopup = false

    private let handleSize: CGFloat = 28
    private let minCrop: CGFloat = 44

    private var current: UIImage { working ?? image }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()
                    Image(uiImage: current)
                        .resizable()
                        .scaledToFit()

                    // 在图片上拖动以画出选区；未框选前整张可拖。
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(createGesture)

                    if let rect = cropRect {
                        dimming(rect)
                        cropBox(rect)
                    }
                }
                .onAppear {
                    setup(in: geo.size)
                    autoFrame()
                }
                .onChange(of: geo.size) { _, newSize in
                    containerSize = newSize
                    layout()
                    applySuggestionIfPossible()
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .top) { topBanner }
            .overlay(alignment: .bottom) { bottomBar }
            .navigationTitle(cropRect == nil ? "框选自己的手牌 · 可旋转" : "调整选区")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { rotate() }
                    } label: {
                        Image(systemName: "rotate.left")
                    }
                    .accessibilityLabel("旋转")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(source == .camera ? "重拍" : "换一张") { onRetake() }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .overlay { if showTutorialPopup { cropTutorialPopup } }
            .onAppear {
                if !hasSeenCropTutorial { showTutorialPopup = true }
            }
        }
    }

    // 顶部常驻提示：定位中 / 已自动框好（可调整）/ 没定位到（请手动框）
    @ViewBuilder
    private var topBanner: some View {
        if isSuggesting {
            banner(icon: "viewfinder", text: "正在自动框选你的牌…", showsSpinner: true)
        } else if cropRect != nil, didAutoFrame {
            banner(icon: "checkmark.viewfinder", text: "已自动框出你的牌，框不准可拖四角或四边调整")
        } else if cropRect == nil {
            banner(icon: "hand.draw.fill", text: "圈出自己的手牌（含碰/杠），排除别人的牌和弃牌堆，识别更准")
        }
    }

    // text 必须是 LocalizedStringKey：换成普通 String 的话 Text 不会查本地化表，
    // 界面会一直显示中文（之前重构横幅时就踩过这个坑）。
    private func banner(icon: String, text: LocalizedStringKey, showsSpinner: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if showsSpinner {
                ProgressView().controlSize(.mini).tint(.white)
            } else {
                Image(systemName: icon)
                    .font(.subheadline)
            }
            Text(text)
                .font(.caption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.black.opacity(0.55))
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .allowsHitTesting(false)   // 不挡住下面的拖拽画框手势
    }

    // 首次进入裁剪页时弹出一次：说明会自动画框，以及框不准时怎么改
    private var cropTutorialPopup: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "checkmark.viewfinder")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accent)
                Text("会自动框出你的牌")
                    .font(.headline)
                Text("拍完会自动框住你自己的牌（含碰/杠），排除别人的牌和弃牌堆。框得不准就拖四角或四边调整，或在照片上重新拖一个框。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    hasSeenCropTutorial = true
                    withAnimation { showTutorialPopup = false }
                } label: {
                    Text("知道了")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
            }
            .padding(.horizontal, 32)
        }
        .transition(.opacity)
    }

    // 底部：清除框选（有框时）+ 大号识别按钮
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if cropRect != nil {
                Button {
                    didAutoFrame = false
                    withAnimation { cropRect = nil }
                } label: {
                    Label("清除框选", systemImage: "xmark.circle")
                        .font(.subheadline.weight(.medium))
                }
                .tint(.secondary)
            }

            // 未框选时降为次要样式，引导优先框选；已框选则是推荐操作，用主色实心
            if cropRect == nil {
                Button {
                    performCrop()
                } label: {
                    recognizeButtonLabel
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            } else {
                Button {
                    performCrop()
                } label: {
                    recognizeButtonLabel
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }

            if cropRect == nil {
                Text("不划区域也能识别，但整桌入镜时牌小、易混入别人的牌，准确率会下降；建议先圈出自己的手牌。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var recognizeButtonLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
            Text(cropRect == nil ? "识别整张照片" : "识别选中区域")
        }
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // 框外压暗（与裁剪框、手势同处 GeometryReader 坐标系，不能 ignoresSafeArea，否则会错位）
    private func dimming(_ rect: CGRect) -> some View {
        Rectangle()
            .fill(.black.opacity(0.55))
            .mask {
                Rectangle()
                    .overlay(alignment: .topLeading) {
                        Rectangle()
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
            .allowsHitTesting(false)
    }

    // 裁剪框 + 四角把手
    private func cropBox(_ rect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(Color.white, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .contentShape(Rectangle())
                .gesture(moveGesture)

            // 四边在前、四角在后：ZStack 里后画的在上层，小框时四角压住四边不抢手势
            ForEach(Handle.allCases, id: \.self) { h in
                handleView(h)
                    .position(point(for: h, in: rect))
                    .gesture(resizeGesture(h))
            }
        }
    }

    /// 四角画圆点、四边画胶囊条——形状本身就提示这个把手只动一条边还是两条
    private func handleView(_ h: Handle) -> some View {
        ZStack {
            Color.clear                                   // 撑开触摸区，比可见图形大一圈
                .frame(width: handleSize + 16, height: handleSize + 16)
            Group {
                if h.isCorner {
                    Circle().frame(width: handleSize, height: handleSize)
                } else {
                    Capsule().frame(width: h.isHorizontalEdge ? 36 : 10,
                                    height: h.isHorizontalEdge ? 10 : 36)
                }
            }
            .foregroundStyle(.white)
            .shadow(radius: 2)
        }
        .contentShape(Rectangle())
    }

    /// 可拖动的把手：四角 + 四边中点。每个把手只记录自己牵动哪几条边，
    /// 缩放逻辑因此对角和边是同一套，不用分情况写。
    private enum Handle: CaseIterable {
        case top, bottom, left, right
        case topLeft, topRight, bottomLeft, bottomRight

        var movesLeft: Bool   { self == .left  || self == .topLeft  || self == .bottomLeft }
        var movesRight: Bool  { self == .right || self == .topRight || self == .bottomRight }
        var movesTop: Bool    { self == .top    || self == .topLeft    || self == .topRight }
        var movesBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }

        var isCorner: Bool { (movesLeft || movesRight) && (movesTop || movesBottom) }
        var isHorizontalEdge: Bool { self == .top || self == .bottom }
    }

    private func point(for h: Handle, in rect: CGRect) -> CGPoint {
        CGPoint(x: h.movesLeft ? rect.minX : (h.movesRight ? rect.maxX : rect.midX),
                y: h.movesTop  ? rect.minY : (h.movesBottom ? rect.maxY : rect.midY))
    }

    // MARK: 手势

    /// 在图片上拖动从无到有画出选区
    private var createGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { v in
                let a = clamp(v.startLocation)
                let b = clamp(v.location)
                cropRect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                  width: abs(a.x - b.x), height: abs(a.y - b.y))
            }
            .onEnded { _ in
                // 太小当作误触，回到「未框选」
                if let r = cropRect, r.width < minCrop || r.height < minCrop {
                    cropRect = nil
                }
                didAutoFrame = false   // 用户自己画过了，顶部不再显示「已自动框出」
            }
    }

    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                guard let cur = cropRect else { return }
                let base = dragBase ?? cur
                if dragBase == nil { dragBase = base }
                var r = base.offsetBy(dx: v.translation.width, dy: v.translation.height)
                r.origin.x = min(max(r.minX, imageRect.minX), imageRect.maxX - r.width)
                r.origin.y = min(max(r.minY, imageRect.minY), imageRect.maxY - r.height)
                cropRect = r
            }
            .onEnded { _ in dragBase = nil }
    }

    private func resizeGesture(_ h: Handle) -> some Gesture {
        DragGesture()
            .onChanged { v in
                guard let cur = cropRect else { return }
                let base = dragBase ?? cur
                if dragBase == nil { dragBase = base }
                var minX = base.minX, minY = base.minY, maxX = base.maxX, maxY = base.maxY
                let tx = v.translation.width, ty = v.translation.height
                // 只动这个把手牵着的边：四边把手动一条，四角动两条
                if h.movesLeft   { minX += tx }
                if h.movesRight  { maxX += tx }
                if h.movesTop    { minY += ty }
                if h.movesBottom { maxY += ty }
                // 限制在图片范围内
                minX = max(minX, imageRect.minX); minY = max(minY, imageRect.minY)
                maxX = min(maxX, imageRect.maxX); maxY = min(maxY, imageRect.maxY)
                // 最小尺寸（防止翻转/过小）：把没被拖的那条边固定住
                if maxX - minX < minCrop {
                    if h.movesLeft { minX = maxX - minCrop }
                    else if h.movesRight { maxX = minX + minCrop }
                }
                if maxY - minY < minCrop {
                    if h.movesTop { minY = maxY - minCrop }
                    else if h.movesBottom { maxY = minY + minCrop }
                }
                cropRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }
            .onEnded { _ in dragBase = nil }
    }

    // MARK: 布局 / 裁剪

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, imageRect.minX), imageRect.maxX),
                y: min(max(p.y, imageRect.minY), imageRect.maxY))
    }

    /// 首次出现：照片已按拍摄时手机的实际朝向（重力）摆正，这里不再按宽高猜测旋转；
    /// 若个别照片方向仍不对，用右上角「旋转」按钮手动纠正。
    private func setup(in container: CGSize) {
        containerSize = container
        layout()
    }

    private func layout() {
        let iw = current.size.width, ih = current.size.height
        let container = containerSize
        guard iw > 0, ih > 0, container.width > 0, container.height > 0 else { return }
        let scale = min(container.width / iw, container.height / ih)
        let w = iw * scale, h = ih * scale
        imageRect = CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    private func rotate() {
        working = current.rotated90(clockwise: false)   // 逆时针
        cropRect = nil
        layout()
        autoFrame()   // 旋转后原来的框没有意义了，按新朝向重新定位
    }

    // MARK: 自动框选

    /// 跑一遍粗检定位「自己的牌」，把选框预先画好。用户随后可以拖动调整或清除。
    private func autoFrame() {
        let target = current
        frameToken &+= 1
        let token = frameToken
        isSuggesting = true
        didAutoFrame = false
        Task {
            let unit = await suggestRegion(target)
            guard token == frameToken else { return }   // 期间又转了一次图，这次结果作废
            isSuggesting = false
            // 期间用户已经自己拖了框 → 不覆盖他的操作
            guard let unit, cropRect == nil else { return }
            suggestedUnitRect = unit
            applySuggestionIfPossible()
        }
    }

    /// 把相对坐标（0…1）的定位结果换算到当前显示区域并落成选框。
    /// layout() 之后才有 imageRect，所以尺寸变化时会再调一次。
    private func applySuggestionIfPossible() {
        guard let unit = suggestedUnitRect, imageRect.width > 0, imageRect.height > 0 else { return }
        var r = CGRect(x: imageRect.minX + unit.minX * imageRect.width,
                       y: imageRect.minY + unit.minY * imageRect.height,
                       width: unit.width * imageRect.width,
                       height: unit.height * imageRect.height)
            .intersection(imageRect)
        guard r.width >= minCrop, r.height >= minCrop else {
            suggestedUnitRect = nil
            return
        }
        r = r.standardized
        suggestedUnitRect = nil
        didAutoFrame = true
        withAnimation(.easeOut(duration: 0.25)) { cropRect = r }
    }

    private func performCrop() {
        let up = current.normalizedUp()
        // 未框选：识别整张
        guard let rect = cropRect, let cg = up.cgImage,
              imageRect.width > 0, imageRect.height > 0 else {
            onCrop(up)
            return
        }
        let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
        let relX = (rect.minX - imageRect.minX) / imageRect.width
        let relY = (rect.minY - imageRect.minY) / imageRect.height
        let relW = rect.width / imageRect.width
        let relH = rect.height / imageRect.height
        let px = CGRect(x: relX * iw, y: relY * ih, width: relW * iw, height: relH * ih).integral
        guard let cropped = cg.cropping(to: px) else { onCrop(up); return }
        onCrop(UIImage(cgImage: cropped))
    }
}

#Preview {
    ContentView()
        .environmentObject(RuleSettingsStore())
        .environmentObject(LanguageManager())
}
