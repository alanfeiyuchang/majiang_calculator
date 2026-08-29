//
//  SpeechAnnouncer.swift
//  majiang calculator
//
//  中文语音播报。分段念，段间留停顿——见 SpokenSummary 里为什么必须分段。
//
//  **播到智能眼镜不需要 Meta 的 SDK**：Ray-Ban Meta 在系统里就是一台标准蓝牙
//  音频设备（A2DP），只要它是当前的音频输出，AVSpeechSynthesizer 的声音自然
//  从眼镜里出来。这里用 .playback + .duckOthers，不抢占已连接的路由。
//

import AVFoundation
import Combine

@MainActor
final class SpeechAnnouncer: NSObject, ObservableObject {

    static let shared = SpeechAnnouncer()

    /// 关掉就完全不出声（设置项用；默认关，出声是要用户主动开的）
    @Published var isEnabled = false

    @Published private(set) var isSpeaking = false

    private let synth = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synth.delegate = self
    }

    /// 播报一组段落。段间停顿由 postUtteranceDelay 控制——
    /// 「四万」和「8块」之间必须断开，否则听起来是「四万八千块」。
    func speak(_ segments: [String]) {
        guard isEnabled, !segments.isEmpty else { return }
        stop()
        configureSession()
        for (i, text) in segments.enumerated() where !text.isEmpty {
            let u = AVSpeechUtterance(string: text)
            u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
            // 牌名后停久一点：金额紧跟在牌名后面最容易被听成一个数
            u.postUtteranceDelay = (i == segments.count - 1) ? 0 : 0.22
            synth.speak(u)
        }
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    /// .playback + .duckOthers：不打断用户在放的东西，只压低。
    /// 不指定输出设备——让系统按当前路由走，接了眼镜就从眼镜出。
    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio,
                                    options: [.duckOthers, .allowBluetoothA2DP])
            try session.setActive(true, options: [])
        } catch {
            // 播不出来不该影响主流程：界面上结果照常显示
            print("SpeechAnnouncer: audio session 配置失败 \(error.localizedDescription)")
        }
    }
}

extension SpeechAnnouncer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = s.isSpeaking
            if !s.isSpeaking {
                try? AVAudioSession.sharedInstance()
                    .setActive(false, options: [.notifyOthersOnDeactivation])
            }
        }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
