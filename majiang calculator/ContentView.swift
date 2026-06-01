//
//  ContentView.swift
//  majiang calculator
//

import SwiftUI
import PhotosUI

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

    private var backgroundColor: Color {
        switch card.suit {
        case .wan: return Color(red: 0.90, green: 0.30, blue: 0.26)
        case .tong: return Color(red: 0.20, green: 0.50, blue: 0.90)
        case .tiao: return Color(red: 0.16, green: 0.65, blue: 0.40)
        }
    }

    var body: some View {
        VStack(spacing: large ? 2 : 1) {
            Text(card.rankHanDigit)
                .font(.system(size: large ? 20 : 17, weight: .bold, design: .rounded))
            Text(card.suit.rawValue)
                .font(.system(size: large ? 12 : 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .frame(minWidth: large ? 44 : 38, minHeight: large ? 52 : 46)
        .padding(.horizontal, large ? 6 : 4)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(backgroundColor.gradient)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: backgroundColor.opacity(0.35), radius: 4, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

// MARK: - 分区卡片

private struct SectionCard<Content: View>: View {
    var title: String
    var systemImage: String?
    var accessory: Text?
    @ViewBuilder let content: Content

    init(
        title: String,
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

// MARK: - 主界面

struct ContentView: View {
    @StateObject private var viewModel = MahjongViewModel()
    @State private var keyboardSuit: MahjongCard.Suit = .wan

    // AI 识别相关（本地 ONNX 模型）
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showSourceDialog = false

    private let handColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    private var countHint: (String, Color) {
        let n = viewModel.selectedTiles.count
        if n == 0 { return ("选入手牌", .secondary) }
        if n >= 14 { return ("已满 14 张", .orange) }
        if n % 3 == 1 { return ("可算听牌", Color(red: 0.2, green: 0.72, blue: 0.45)) }
        let need = (4 - (n % 3)) % 3
        if need == 1 { return ("再选 1 张", .orange) }
        return ("再选 2 张", .orange)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.sectionSpacing) {
                    handSection
                    resultSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
            .navigationTitle("听牌计算器")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.reset()
                    } label: {
                        Image(systemName: "trash")
                            .font(.body.weight(.medium))
                    }
                    .disabled(viewModel.selectedTiles.isEmpty && viewModel.waitingTiles.isEmpty)
                    .accessibilityLabel("清空全部")
                }
            }
            .overlay { if viewModel.isRecognizing { recognizingOverlay } }
        }
        .confirmationDialog("选择图片来源", isPresented: $showSourceDialog, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("拍照") { showCamera = true }
            }
            Button("从相册选择") { showPhotoPicker = true }
            Button("取消", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                let data = try? await newItem.loadTransferable(type: Data.self)
                photoItem = nil
                if let data {
                    await viewModel.recognizeAndCalculate(imageData: data)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.9) {
                    Task { await viewModel.recognizeAndCalculate(imageData: data) }
                }
            }
            .ignoresSafeArea()
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
            title: "手牌",
            systemImage: "square.grid.3x3.fill",
            accessory: Text("\(viewModel.selectedTiles.count) / 14")
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

            Button {
                viewModel.completeCalculation()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("计算听牌")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(viewModel.selectedTiles.isEmpty || viewModel.isRecognizing)
            .padding(.top, 4)

            Button {
                showSourceDialog = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                    Text("拍照识别手牌")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .disabled(viewModel.isRecognizing)
        }
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
        } else if viewModel.showsNoWaiting {
            SectionCard(title: "听牌结果", systemImage: "xmark.circle.fill") {
                Label {
                    Text("无可胡听牌（标准形 / 七对，且缺一门）")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
            }
        } else if !viewModel.waitingTiles.isEmpty {
            SectionCard(
                title: "听牌",
                systemImage: "checkmark.seal.fill",
                accessory: Text("共 \(viewModel.waitingTiles.count) 门").monospacedDigit()
            ) {
                FlowWaitingLayout(spacing: 8) {
                    ForEach(Array(viewModel.waitingTiles.enumerated()), id: \.offset) { _, card in
                        MahjongTileChip(card: card, large: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            SectionCard(title: "听牌结果", systemImage: "questionmark.circle") {
                Text("选满 1、4、7、10 或 13 张后点「计算听牌」")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 底部：操作 + 键盘

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("点选加入")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.horizontal, 4)

                suitPicker

                HStack(spacing: 6) {
                    ForEach(1...9, id: \.self) { r in
                        let card = MahjongCard(suit: keyboardSuit, rank: r)
                        Button {
                            viewModel.addCard(card)
                        } label: {
                            VStack(spacing: 1) {
                                Text("\(r)")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                Text(keyboardSuit.rawValue)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(viewModel.canAddMore ? suitColor(keyboardSuit) : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(uiColor: .tertiarySystemFill))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(suitColor(keyboardSuit).opacity(0.2), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!viewModel.canAddMore)
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
            ForEach(MahjongCard.Suit.displayOrder, id: \.self) { suit in
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

    private func suitColor(_ suit: MahjongCard.Suit) -> Color {
        switch suit {
        case .wan: return Color(red: 0.88, green: 0.28, blue: 0.24)
        case .tong: return Color(red: 0.18, green: 0.48, blue: 0.88)
        case .tiao: return Color(red: 0.15, green: 0.62, blue: 0.36)
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

// MARK: - 相机

private struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    ContentView()
}
