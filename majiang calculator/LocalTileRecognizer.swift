//
//  LocalTileRecognizer.swift
//  majiang calculator
//
//  On-device 麻将牌识别：用 ONNX Runtime 跑 YOLOv8 模型（mahjong_yolov8.onnx）。
//  纯本地推理，不联网、不需要 API Key。
//
//  模型来源参考：github.com/LYiHub/AR-Mahjong-Assistant-preview （YOLOv8 / ONNX）。
//  类别命名：后缀 C=Characters(万)、D=Dots(筒)、B=Bamboo(条)，点数 1–9；
//  其余（花/季/风/箭）四川麻将用不到，识别时忽略。
//

import Foundation
import UIKit
import OnnxRuntimeBindings

enum LocalRecognitionError: LocalizedError {
    case modelMissing
    case invalidImage
    case inferenceFailed(String)
    case noTiles

    var errorDescription: String? {
        switch self {
        case .modelMissing:    return "未找到本地识别模型文件。"
        case .invalidImage:    return "无法读取所选图片，请换一张试试。"
        case .inferenceFailed(let m): return "本地识别失败：\(m)"
        case .noTiles:         return "未能从图片中识别到麻将牌，请确保牌面清晰、正对镜头、光线充足。"
        }
    }
}

actor LocalTileRecognizer {

    // YOLOv8 模型参数
    private let inputSize = 640
    private let confidenceThreshold: Float = 0.5
    private let iouThreshold: Float = 0.45

    /// class_names.txt 的 42 个类别（顺序与模型输出通道一致）
    private let classNames = [
        "1B","1C","1D","1F","1S","2B","2C","2D","2F","2S",
        "3B","3C","3D","3F","3S","4B","4C","4D","4F","4S",
        "5B","5C","5D","6B","6C","6D","7B","7C","7D","8B",
        "8C","8D","9B","9C","9D","EW","GD","NW","RD","SW","WD","WW"
    ]

    private var env: ORTEnv?
    private var session: ORTSession?

    private func loadSessionIfNeeded() throws {
        guard session == nil else { return }
        guard let url = Bundle.main.url(forResource: "mahjong_yolov8", withExtension: "onnx") else {
            throw LocalRecognitionError.modelMissing
        }
        do {
            let env = try ORTEnv(loggingLevel: .warning)
            let options = try ORTSessionOptions()
            self.session = try ORTSession(env: env, modelPath: url.path, sessionOptions: options)
            self.env = env
        } catch {
            throw LocalRecognitionError.inferenceFailed(error.localizedDescription)
        }
    }

    func recognize(imageData: Data) throws -> [MahjongCard] {
        try loadSessionIfNeeded()
        guard let session else { throw LocalRecognitionError.modelMissing }
        guard let image = UIImage(data: imageData)?.normalizedUp() else {
            throw LocalRecognitionError.invalidImage
        }
        guard let pre = preprocess(image) else { throw LocalRecognitionError.invalidImage }

        // 构造输入张量 [1,3,640,640]
        let inputData = NSMutableData(bytes: pre.tensor, length: pre.tensor.count * MemoryLayout<Float>.stride)
        let shape: [NSNumber] = [1, 3, NSNumber(value: inputSize), NSNumber(value: inputSize)]

        let detections: [Detection]
        do {
            let input = try ORTValue(tensorData: inputData, elementType: .float, shape: shape)
            let outputs = try session.run(withInputs: ["images": input],
                                          outputNames: ["output0"],
                                          runOptions: nil)
            guard let output = outputs["output0"] else {
                throw LocalRecognitionError.inferenceFailed("缺少输出")
            }
            let info = try output.tensorTypeAndShapeInfo()
            let outShape = info.shape.map { $0.intValue }   // [1, 4+numClasses, anchors]
            let data = try output.tensorData() as Data
            let floats: [Float] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            detections = decode(floats, shape: outShape)
        } catch let e as LocalRecognitionError {
            throw e
        } catch {
            throw LocalRecognitionError.inferenceFailed(error.localizedDescription)
        }

        let kept = nms(detections)
        let cards = readingOrder(kept).compactMap { card(for: $0.classId) }
        guard !cards.isEmpty else { throw LocalRecognitionError.noTiles }
        return cards
    }

    // MARK: - 预处理（letterbox → RGB/255 → CHW）

    private func preprocess(_ image: UIImage) -> (tensor: [Float], scale: CGFloat, dw: CGFloat, dh: CGFloat)? {
        guard let cg = image.cgImage else { return nil }
        let imgW = CGFloat(cg.width), imgH = CGFloat(cg.height)
        guard imgW > 0, imgH > 0 else { return nil }

        let s = CGFloat(inputSize)
        let scale = min(s / imgW, s / imgH)
        let newW = (imgW * scale).rounded()
        let newH = (imgH * scale).rounded()
        let dw = (s - newW) / 2
        let dh = (s - newH) / 2

        let size = inputSize
        let bytesPerRow = size * 4
        var pixels = [UInt8](repeating: 114, count: size * size * 4)   // 灰色填充 (114,114,114)
        guard let ctx = CGContext(data: &pixels, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // 翻转坐标系，使绘制结果为「左上原点」的栅格，牌面朝上
        ctx.translateBy(x: 0, y: s)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: dw, y: dh, width: newW, height: newH))

        let plane = size * size
        var tensor = [Float](repeating: 0, count: 3 * plane)
        for i in 0..<plane {
            let p = i * 4
            tensor[i]             = Float(pixels[p])     / 255.0   // R
            tensor[plane + i]     = Float(pixels[p + 1]) / 255.0   // G
            tensor[2 * plane + i] = Float(pixels[p + 2]) / 255.0   // B
        }
        return (tensor, scale, dw, dh)
    }

    // MARK: - 解码 YOLOv8 输出

    private struct Detection {
        var x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat
        var score: Float
        var classId: Int
        var cx: CGFloat { (x1 + x2) / 2 }
        var cy: CGFloat { (y1 + y2) / 2 }
        var h: CGFloat { y2 - y1 }
    }

    /// floats 布局为 [1, channels, anchors]，元素 (c,a) 索引 = c*anchors + a
    private func decode(_ floats: [Float], shape: [Int]) -> [Detection] {
        guard shape.count == 3 else { return [] }
        let channels = shape[1]
        let anchors = shape[2]
        let numClasses = channels - 4
        guard numClasses > 0, floats.count >= channels * anchors else { return [] }

        var dets: [Detection] = []
        for a in 0..<anchors {
            var bestId = 0
            var bestScore: Float = 0
            for c in 0..<numClasses {
                let v = floats[(4 + c) * anchors + a]
                if v > bestScore { bestScore = v; bestId = c }
            }
            guard bestScore >= confidenceThreshold else { continue }

            let cx = CGFloat(floats[a])
            let cy = CGFloat(floats[anchors + a])
            let w  = CGFloat(floats[2 * anchors + a])
            let hh = CGFloat(floats[3 * anchors + a])
            dets.append(Detection(x1: cx - w / 2, y1: cy - hh / 2,
                                  x2: cx + w / 2, y2: cy + hh / 2,
                                  score: bestScore, classId: bestId))
        }
        return dets
    }

    // MARK: - NMS

    private func nms(_ input: [Detection]) -> [Detection] {
        let sorted = input.sorted { $0.score > $1.score }
        var kept: [Detection] = []
        for d in sorted {
            if kept.allSatisfy({ iou($0, d) <= iouThreshold }) {
                kept.append(d)
            }
        }
        return kept
    }

    private func iou(_ a: Detection, _ b: Detection) -> Float {
        let x1 = max(a.x1, b.x1), y1 = max(a.y1, b.y1)
        let x2 = min(a.x2, b.x2), y2 = min(a.y2, b.y2)
        let iw = max(0, x2 - x1), ih = max(0, y2 - y1)
        let inter = iw * ih
        let areaA = max(0, a.x2 - a.x1) * max(0, a.y2 - a.y1)
        let areaB = max(0, b.x2 - b.x1) * max(0, b.y2 - b.y1)
        let union = areaA + areaB - inter
        return union <= 0 ? 0 : Float(inter / union)
    }

    // MARK: - 阅读顺序（按行从上到下、行内从左到右）

    private func readingOrder(_ dets: [Detection]) -> [Detection] {
        guard !dets.isEmpty else { return [] }
        let avgH = dets.map { $0.h }.reduce(0, +) / CGFloat(dets.count)
        let rowGap = max(avgH * 0.6, 1)
        var rows: [[Detection]] = []
        for d in dets.sorted(by: { $0.cy < $1.cy }) {
            if let i = rows.indices.last, let first = rows[i].first, abs(d.cy - first.cy) <= rowGap {
                rows[i].append(d)
            } else {
                rows.append([d])
            }
        }
        return rows.flatMap { $0.sorted { $0.cx < $1.cx } }
    }

    // MARK: - 类别 → MahjongCard（仅 万/筒/条）

    private func card(for classId: Int) -> MahjongCard? {
        guard classId >= 0, classId < classNames.count else { return nil }
        let name = classNames[classId]          // 如 "5C"
        guard name.count == 2,
              let rank = Int(String(name.first!)), (1...9).contains(rank) else { return nil }
        switch name.last! {
        case "C": return MahjongCard(suit: .wan, rank: rank)   // Characters 万
        case "D": return MahjongCard(suit: .tong, rank: rank)  // Dots 筒
        case "B": return MahjongCard(suit: .tiao, rank: rank)  // Bamboo 条
        default:  return nil                                    // F/S/风/箭：忽略
        }
    }
}

// MARK: - 方向归一化

extension UIImage {
    /// 将带 EXIF 方向的图片重绘为 .up，避免输入张量被旋转/镜像
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
