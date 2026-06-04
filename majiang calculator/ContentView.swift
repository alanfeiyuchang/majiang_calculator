//
//  ContentView.swift
//  majiang calculator
//

import SwiftUI
import PhotosUI
import AVFoundation
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
        Image(card.assetName)
            .resizable()
            .interpolation(.high)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
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
            CropView(image: item.image, source: item.source) {
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
                    Text("分析手牌")
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
        } else if viewModel.hasAnalyzed {
            analysisResult
        } else {
            SectionCard(title: "分析结果", systemImage: "questionmark.circle") {
                Text("选牌后点「分析手牌」：13 张算听牌/向听，14 张给打牌建议。")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var analysisResult: some View {
        let sh = viewModel.shantenValue ?? 99
        if sh == -1 {
            // 已和（3n+2 且成牌）
            SectionCard(title: "已和！", systemImage: "checkmark.seal.fill") {
                Text("这副牌已经胡了（满足缺一门）。")
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 0.16, green: 0.65, blue: 0.40))
            }
        } else if !viewModel.discards.isEmpty {
            discardCard
        } else if sh == 0 {
            tenpaiCard
        } else {
            shantenCard
        }
    }

    // 听牌（含空听）
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
                FlowWaitingLayout(spacing: 8) {
                    ForEach(Array(viewModel.waitingTiles.enumerated()), id: \.offset) { _, card in
                        MahjongTileChip(card: card, large: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("无有效进张（受缺一门所限）。")
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

    // 打牌建议（3n+2）
    private var discardCard: some View {
        SectionCard(
            title: "打牌建议",
            systemImage: "hand.point.up.left.fill",
            accessory: Text("\(viewModel.discards.count) 种").monospacedDigit()
        ) {
            VStack(spacing: 10) {
                ForEach(viewModel.discards.prefix(6)) { s in
                    HStack(spacing: 10) {
                        Text("打")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        MahjongTileChip(card: s.discard)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.resultingShanten == 0 ? "听牌" : "向听 \(s.resultingShanten)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(s.resultingShanten == 0
                                                 ? Color(red: 0.16, green: 0.65, blue: 0.40) : .primary)
                            Text("进张 \(s.acceptanceCount) 张 · \(s.acceptance.count) 门")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
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
                            Image(card.assetName)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                                .frame(height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Color.black.opacity(0.28), lineWidth: 1)
                                }
                                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                                .frame(maxWidth: .infinity)
                                .opacity(viewModel.canAddMore ? 1 : 0.35)
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

// MARK: - 相机（AVFoundation 自定义拍摄，拍完直接进裁剪，无「重拍/使用照片」确认步骤）

private final class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "camera.session")
    private var configured = false

    var onCapture: ((UIImage) -> Void)?
    /// 拍摄时根据界面方向设置的旋转角度
    var captureAngle: CGFloat = 90

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
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
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
                    model.captureAngle = Self.currentCaptureAngle()
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
        }
        .onDisappear { model.stop() }
    }

    /// 依据当前界面方向得到拍摄旋转角度（让照片方向正确）
    private static func currentCaptureAngle() -> CGFloat {
        let io = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation ?? .portrait
        switch io {
        case .portrait:            return 90
        case .portraitUpsideDown:  return 270
        case .landscapeLeft:       return 180
        case .landscapeRight:      return 0
        default:                   return 90
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

/// 让用户把裁剪框拖到「只剩自己的手牌」，再交给模型识别，
/// 避免把牌桌上其他人的牌、牌墙、弃牌也识别进来。
private struct CropView: View {
    let image: UIImage
    let source: ImageSource
    var onCancel: () -> Void
    var onRetake: () -> Void
    var onCrop: (UIImage) -> Void

    @State private var working: UIImage? = nil        // 当前（可旋转后）的图片
    @State private var containerSize: CGSize = .zero
    @State private var didSetup = false
    @State private var imageRect: CGRect = .zero    // 图片在视图中的实际显示区域
    @State private var cropRect: CGRect? = nil        // 裁剪框；nil = 未框选，识别整张
    @State private var dragBase: CGRect? = nil        // 移动/缩放手势开始时的快照

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
                .onAppear { setup(in: geo.size) }
                .onChange(of: geo.size) { _, newSize in
                    containerSize = newSize
                    layout()
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) { bottomBar }
            .navigationTitle(cropRect == nil ? "拖动框选 · 可旋转" : "调整选区")
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
        }
    }

    // 底部：清除框选（有框时）+ 大号识别按钮
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if cropRect != nil {
                Button {
                    withAnimation { cropRect = nil }
                } label: {
                    Label("清除框选", systemImage: "xmark.circle")
                        .font(.subheadline.weight(.medium))
                }
                .tint(.secondary)
            }

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
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
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

    /// 首次出现：相机拍的横图（宽 > 高）自动逆时针旋转为竖向，方便竖屏裁剪
    private func setup(in container: CGSize) {
        containerSize = container
        if !didSetup {
            didSetup = true
            if source == .camera, image.size.width > image.size.height {
                working = image.rotated90(clockwise: false)
            }
        }
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
}
