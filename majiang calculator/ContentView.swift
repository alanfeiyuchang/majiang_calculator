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
    /// 选中/拍摄后待裁剪的图片（裁剪到只剩自己的手牌再识别）
    @State private var pendingCrop: PendingImage?

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
                if let data, let image = UIImage(data: data) {
                    pendingCrop = PendingImage(image: image)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                pendingCrop = PendingImage(image: image)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $pendingCrop) { item in
            CropView(image: item.image) {
                pendingCrop = nil
            } onCrop: { cropped in
                pendingCrop = nil
                if let data = cropped.jpegData(compressionQuality: 0.9) {
                    Task { await viewModel.recognizeAndCalculate(imageData: data) }
                }
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

// MARK: - 裁剪到手牌

struct PendingImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// 让用户把裁剪框拖到「只剩自己的手牌」，再交给模型识别，
/// 避免把牌桌上其他人的牌、牌墙、弃牌也识别进来。
private struct CropView: View {
    let image: UIImage
    var onCancel: () -> Void
    var onCrop: (UIImage) -> Void

    @State private var imageRect: CGRect = .zero    // 图片在视图中的实际显示区域
    @State private var cropRect: CGRect? = nil        // 裁剪框；nil = 未框选，识别整张
    @State private var dragBase: CGRect? = nil        // 移动/缩放手势开始时的快照

    private let handleSize: CGFloat = 28
    private let minCrop: CGFloat = 44

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()
                    Image(uiImage: image)
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
                .onAppear { layout(in: geo.size) }
                .onChange(of: geo.size) { _, newSize in layout(in: newSize) }
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) { bottomBar }
            .navigationTitle(cropRect == nil ? "在手牌上拖动框选（可选）" : "调整选区")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                if cropRect != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("重选") { withAnimation { cropRect = nil } }
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // 底部大号识别按钮
    private var bottomBar: some View {
        VStack(spacing: 0) {
            Button {
                performCrop()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text(cropRect == nil ? "识别整张照片" : "识别选中区域")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    // 框外压暗
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
            .ignoresSafeArea()
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

            ForEach(Corner.allCases, id: \.self) { corner in
                handle
                    .position(point(for: corner, in: rect))
                    .gesture(resizeGesture(corner))
            }
        }
    }

    private var handle: some View {
        Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .shadow(radius: 2)
    }

    private enum Corner: CaseIterable { case tl, tr, bl, br }

    private func point(for c: Corner, in rect: CGRect) -> CGPoint {
        switch c {
        case .tl: return CGPoint(x: rect.minX, y: rect.minY)
        case .tr: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bl: return CGPoint(x: rect.minX, y: rect.maxY)
        case .br: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
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

    private func resizeGesture(_ corner: Corner) -> some Gesture {
        DragGesture()
            .onChanged { v in
                guard let cur = cropRect else { return }
                let base = dragBase ?? cur
                if dragBase == nil { dragBase = base }
                var minX = base.minX, minY = base.minY, maxX = base.maxX, maxY = base.maxY
                let tx = v.translation.width, ty = v.translation.height
                switch corner {
                case .tl: minX += tx; minY += ty
                case .tr: maxX += tx; minY += ty
                case .bl: minX += tx; maxY += ty
                case .br: maxX += tx; maxY += ty
                }
                // 限制在图片范围内
                minX = max(minX, imageRect.minX); minY = max(minY, imageRect.minY)
                maxX = min(maxX, imageRect.maxX); maxY = min(maxY, imageRect.maxY)
                // 最小尺寸（防止翻转/过小）
                if maxX - minX < minCrop {
                    if corner == .tl || corner == .bl { minX = maxX - minCrop } else { maxX = minX + minCrop }
                }
                if maxY - minY < minCrop {
                    if corner == .tl || corner == .tr { minY = maxY - minCrop } else { maxY = minY + minCrop }
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

    private func layout(in container: CGSize) {
        let iw = image.size.width, ih = image.size.height
        guard iw > 0, ih > 0, container.width > 0, container.height > 0 else { return }
        let scale = min(container.width / iw, container.height / ih)
        let w = iw * scale, h = ih * scale
        imageRect = CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    private func performCrop() {
        let up = image.normalizedUp()
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
}
