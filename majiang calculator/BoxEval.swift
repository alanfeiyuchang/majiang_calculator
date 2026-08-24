//
//  BoxEval.swift
//  majiang calculator
//
//  自动框选的离线评测（仅 DEBUG，不进 Release 包）。
//
//  跑法见 data/README.md：把 data/preview/*.jpg 拷进模拟器 App 容器的 Documents/eval/，
//  用环境变量 MJ_EVAL=1 启动，控制台会逐张打出 suggestHandRegion() 算出来的框，
//  再和 data/boxes.json 里的 ground truth 比 IoU。
//
//  走的是和线上完全一样的代码路径（同一个 LocalTileRecognizer），
//  不是另写一份推理，避免「照着重写的版本调出来的参数，装回 App 里不灵」。
//

#if DEBUG
import Foundation
import UIKit

enum BoxEval {
    /// 环境变量 MJ_EVAL=1 时才跑
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["MJ_EVAL"] == "1"
    }

    static func run() async {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = docs.appendingPathComponent("eval")
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            print("EVAL_ERR 找不到 \(dir.path)")
            return
        }

        let recognizer = LocalTileRecognizer()
        print("EVAL_BEGIN")
        for url in files.filter({ $0.pathExtension.lowercased() == "jpg" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: url) else {
                print("EVAL \(name) read_failed")
                continue
            }
            do {
                // 原始检测框导出，供离线调算法用
                let dets = try await recognizer.debugDetections(imageData: data)
                let compact = dets.map { d in
                    "[" + d.enumerated().map { i, v in
                        i < 4 ? String(format: "%.5f", v) : String(format: "%.3f", v)
                    }.joined(separator: ",") + "]"
                }.joined(separator: ",")
                print("DET \(name) [\(compact)]")

                if let r = try await recognizer.suggestHandRegion(imageData: data) {
                    print(String(format: "EVAL %@ %.4f %.4f %.4f %.4f",
                                 name, r.minX, r.minY, r.width, r.height))
                    // 再走一遍用户的实际路径：按自动框裁剪 → 识别 → 打出分组结果
                    await recognizeCropped(name: name, data: data, unit: r, recognizer: recognizer)
                } else {
                    print("EVAL \(name) nil")     // 没把握框 → 裁剪页退回手动
                    await recognizeCropped(name: name, data: data, unit: nil, recognizer: recognizer)
                }
            } catch {
                print("EVAL \(name) error \(error.localizedDescription)")
            }
        }
        print("EVAL_END")
    }

    /// 按自动框裁剪后识别，输出格式：REC <编号> hand=<牌…> melds=<种类:牌…>
    private static func recognizeCropped(name: String, data: Data, unit: CGRect?,
                                         recognizer: LocalTileRecognizer) async {
        var payload = data
        if let unit, let img = UIImage(data: data)?.normalizedUp(), let cg = img.cgImage {
            let px = CGRect(x: unit.minX * CGFloat(cg.width),
                            y: unit.minY * CGFloat(cg.height),
                            width: unit.width * CGFloat(cg.width),
                            height: unit.height * CGFloat(cg.height)).integral
            if let cropped = cg.cropping(to: px),
               let d = UIImage(cgImage: cropped).jpegData(compressionQuality: 0.95) {
                payload = d
            }
        }
        do {
            let r = try await recognizer.recognize(imageData: payload)
            let hand = r.hand.map(code).joined(separator: " ")
            let melds = r.melds.map { "\($0.kind.rawValue):\(code($0.card))" }.joined(separator: " ")
            print("REC \(name) hand=[\(hand)] melds=[\(melds)]")
        } catch {
            print("REC \(name) error \(error.localizedDescription)")
        }
    }

    /// 2m / 5p / 8s 这种紧凑写法，和 data/labels.md 一致
    private static func code(_ c: MahjongCard) -> String {
        let suit: String
        switch c.suit {
        case .wan:  suit = "m"
        case .tong: suit = "p"
        case .tiao: suit = "s"
        }
        return "\(c.rank)\(suit)"
    }
}
#endif
