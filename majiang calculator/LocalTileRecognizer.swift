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
        let b = appLanguageBundle()
        switch self {
        case .modelMissing:    return String(localized: "未找到本地识别模型文件。", bundle: b)
        case .invalidImage:    return String(localized: "无法读取所选图片，请换一张试试。", bundle: b)
        case .inferenceFailed(let m): return String(localized: "本地识别失败：\(m)", bundle: b)
        case .noTiles:         return String(localized: "未能从图片中识别到麻将牌，请确保牌面清晰、正对镜头、光线充足。", bundle: b)
        }
    }
}

actor LocalTileRecognizer {

    // YOLOv8 模型参数
    private let inputSize = 640
    private let confidenceThreshold: Float = 0.5
    /// 第一遍估计「牌所在区域」用的低阈值（多找些框，只用于定位，不进结果）
    private let regionThreshold: Float = 0.35
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

    func recognize(imageData: Data) throws -> RecognitionResult {
        try loadSessionIfNeeded()
        guard let image = UIImage(data: imageData)?.normalizedUp() else {
            throw LocalRecognitionError.invalidImage
        }

        // 第一遍：整图识别。低阈值的框只用来估计「牌所在区域」，达标（≥ 正式阈值）的作候选结果
        let first = try detect(image, threshold: regionThreshold)
        var finalDets = first.dets.filter { $0.score >= confidenceThreshold }

        // 第二遍：牌只占画面一小部分时（整图缩到 640 后每张牌太小），
        // 把牌区裁出来放大重新识别，用更清晰的结果替换
        let boxesInImage = first.dets.map { d in
            CGRect(x: (d.x1 - first.dw) / first.scale,
                   y: (d.y1 - first.dh) / first.scale,
                   width: (d.x2 - d.x1) / first.scale,
                   height: (d.y2 - d.y1) / first.scale)
        }
        if let region = zoomRegion(boxes: boxesInImage, imageSize: image.size),
           let cropped = image.cgImage?.cropping(to: region) {
            let second = try detect(UIImage(cgImage: cropped), threshold: confidenceThreshold)
            if second.dets.count >= finalDets.count {   // 保底：第二遍反而更差就保留第一遍
                finalDets = second.dets
            }
        }

        // 只保留 万/筒/条（忽略风/箭等），转成牌盒后做空间聚类分组
        let boxes: [TileBox] = finalDets.compactMap { d in
            guard let c = card(for: d.classId) else { return nil }
            return TileBox(minX: d.x1, maxX: d.x2, cy: d.cy, height: d.h, card: c)
        }
        guard !boxes.isEmpty else { throw LocalRecognitionError.noTiles }
        let result = groupTiles(boxes)
        guard !result.hand.isEmpty || !result.melds.isEmpty else {
            throw LocalRecognitionError.noTiles
        }
        return result
    }

    /// 一次完整推理：letterbox → ONNX → 解码 → NMS。
    /// 检测框在 640 空间；scale/dw/dh 用于映射回原图像素。
    private struct DetectPass {
        let dets: [Detection]
        let scale: CGFloat
        let dw: CGFloat
        let dh: CGFloat
    }

    private func detect(_ image: UIImage, threshold: Float) throws -> DetectPass {
        guard let session else { throw LocalRecognitionError.modelMissing }
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
                throw LocalRecognitionError.inferenceFailed(String(localized: "缺少输出", bundle: appLanguageBundle()))
            }
            let info = try output.tensorTypeAndShapeInfo()
            let outShape = info.shape.map { $0.intValue }   // [1, 4+numClasses, anchors]
            let data = try output.tensorData() as Data
            let floats: [Float] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            detections = decode(floats, shape: outShape, threshold: threshold)
        } catch let e as LocalRecognitionError {
            throw e
        } catch {
            throw LocalRecognitionError.inferenceFailed(error.localizedDescription)
        }
        return DetectPass(dets: nms(detections), scale: pre.scale, dw: pre.dw, dh: pre.dh)
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
    private func decode(_ floats: [Float], shape: [Int], threshold: Float) -> [Detection] {
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
            guard bestScore >= threshold else { continue }

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

    /// 旋转 90°（像素级烘焙，宽高互换）。clockwise = true 顺时针，false 逆时针。
    func rotated90(clockwise: Bool) -> UIImage {
        let newSize = CGSize(width: size.height, height: size.width)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            cg.rotate(by: clockwise ? .pi / 2 : -.pi / 2)
            cg.translateBy(x: -size.width / 2, y: -size.height / 2)
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
