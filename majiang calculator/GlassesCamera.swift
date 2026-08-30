//
//  GlassesCamera.swift
//  majiang calculator
//
//  用 Meta 智能眼镜（Ray-Ban Meta / Oakley Meta）代替手机相机拍牌桌。
//  戴着眼镜时视角天然对准牌，不用举起手机；结果再用语音播报，全程不看屏幕。
//
//  三件事必须知道：
//
//  1) **拍照必须先起一路视频流**。SDK 没有「冷拍一张」的接口，
//     capturePhoto 只能在 stream.start() 之后调。所以按下到出片有几秒启动开销，
//     这里在开始识别前就预热，不是按下才建会话。
//
//  2) **App 退到后台会话就断**（SDK 0.9.0 起）。所以这条路只在前台可用，
//     不能做成锁屏/后台待命。
//
//  3) **需要用户在 Meta AI App 里授权**：先 startRegistration() 跳过去批准，
//     再回调回来。没授权时 isAvailable 为 false，界面自动退回手机相机。
//

import Foundation
import UIKit
import Combine
import MWDATCore
import MWDATCamera

@MainActor
final class GlassesCamera: ObservableObject {

    static let shared = GlassesCamera()

    /// 眼镜可用（已注册 + 有设备在线）。界面据此决定拍照走眼镜还是手机相机。
    @Published private(set) var isAvailable = false
    /// 正在预热会话/取流
    @Published private(set) var isPreparing = false
    /// 最近一次失败原因，供界面提示；失败一律退回手机相机，不阻断主流程
    @Published private(set) var lastError: String?

    private var session: DeviceSession?
    private var camera: Camera?
    private var photoToken: Any?
    /// capturePhoto 是异步出片的，用它把 publisher 回调接回 async 调用
    private var pendingShot: CheckedContinuation<Data, Error>?

    private init() {}

    // MARK: - 生命周期

    /// App 启动时调一次。SDK 没配好（缺 MetaAppID 等）时不崩，只是眼镜功能不可用。
    static func configureAtLaunch() {
        do {
            try Wearables.configure()
        } catch {
            print("GlassesCamera: SDK 未配置，眼镜功能不可用 —— \(error.localizedDescription)")
        }
    }

    /// Meta AI 授权后会通过 URL scheme 回调
    func handleCallback(_ url: URL) async {
        _ = try? await Wearables.shared.handleUrl(url)
    }

    /// 监听注册状态与设备在线，任一变化都重算 isAvailable
    func startMonitoring() {
        Task { [weak self] in
            for await state in Wearables.shared.registrationStateStream() {
                await self?.setRegistered(state == .registered)
            }
        }
        Task { [weak self] in
            for await devices in Wearables.shared.devicesStream() {
                await self?.setHasDevice(!devices.isEmpty)
            }
        }
    }

    private var isRegistered = false { didSet { recomputeAvailability() } }
    private var hasDevice = false { didSet { recomputeAvailability() } }

    private func setRegistered(_ v: Bool) { isRegistered = v }
    private func setHasDevice(_ v: Bool) { hasDevice = v }
    private func recomputeAvailability() { isAvailable = isRegistered && hasDevice }

    /// 引导用户去 Meta AI 授权
    func requestAuthorization() async {
        do { try await Wearables.shared.startRegistration() }
        catch { lastError = error.localizedDescription }
    }

    // MARK: - 拍照

    /// 拍一张。内部负责建会话、起流、等出片。
    /// 失败就抛错——调用方应当退回手机相机，而不是让用户干等。
    func capture() async throws -> Data {
        try await prepareIfNeeded()
        guard let stream = camera?.stream else {
            throw GlassesError.notReady
        }
        return try await withCheckedThrowingContinuation { cont in
            self.pendingShot = cont
            if !stream.capturePhoto(format: .jpeg) {
                self.pendingShot = nil
                cont.resume(throwing: GlassesError.captureRejected)
            }
        }
    }

    /// 预热：建会话 → 等 started → 加相机 → 起流 → 挂出片监听。
    /// 已经就绪时直接返回，重复调用无副作用。
    func prepareIfNeeded() async throws {
        if camera != nil { return }
        guard isAvailable else { throw GlassesError.unavailable }
        isPreparing = true
        defer { isPreparing = false }

        let wearables = Wearables.shared
        let session = try wearables.createSession(deviceSelector: AutoDeviceSelector(wearables: wearables))
        try session.start()
        self.session = session

        // 等会话真正 started 再加相机；期间设备可能直接 stopped（比如镜腿合上）
        for await state in session.stateStream() {
            if state == .started { break }
            if state == .stopped { throw GlassesError.sessionStopped }
        }

        // 只为拍照，取最低画质的流——出片走的是独立的照片通道，不受这个分辨率限制，
        // 流本身只是 capturePhoto 的前置条件，画质开高纯属浪费带宽和电。
        let config = StreamConfiguration(videoCodec: .raw, resolution: .low, frameRate: 24)
        guard let camera = try session.addCamera(config: config) else {
            throw GlassesError.noCamera
        }
        self.camera = camera

        photoToken = camera.stream.photoDataPublisher.listen { [weak self] photo in
            Task { @MainActor in self?.deliver(photo.data) }
        }
        camera.stream.start()
    }

    private func deliver(_ data: Data) {
        pendingShot?.resume(returning: data)
        pendingShot = nil
    }

    /// 用完就放掉：流一直开着很费电，而且会一直亮着眼镜的隐私指示灯
    func teardown() {
        camera?.stream.stop()
        photoToken = nil
        camera = nil
        session?.stop()
        session = nil
        pendingShot?.resume(throwing: GlassesError.sessionStopped)
        pendingShot = nil
    }

    enum GlassesError: LocalizedError {
        case unavailable, notReady, noCamera, sessionStopped, captureRejected

        var errorDescription: String? {
            let b = appLanguageBundle()
            switch self {
            case .unavailable:     return String(localized: "眼镜没连上，或还没在 Meta AI 里授权。", bundle: b)
            case .notReady:        return String(localized: "眼镜相机还没准备好。", bundle: b)
            case .noCamera:        return String(localized: "这副眼镜没有可用的相机。", bundle: b)
            case .sessionStopped:  return String(localized: "眼镜连接中断了（镜腿合上或走出蓝牙范围）。", bundle: b)
            case .captureRejected: return String(localized: "眼镜拒绝了拍照请求，请重试。", bundle: b)
            }
        }
    }
}
