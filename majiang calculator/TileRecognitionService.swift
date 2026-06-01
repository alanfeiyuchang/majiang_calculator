//
//  TileRecognitionService.swift
//  majiang calculator
//
//  调用 Anthropic Claude 视觉模型，从一张麻将牌照片识别出手牌。
//  返回识别到的 [MahjongCard]（仅 万/筒/条，点数 1–9）。
//

import Foundation
import UIKit

enum TileRecognitionError: LocalizedError {
    case missingAPIKey
    case invalidImage
    case requestFailed(String)
    case decodeFailed
    case noTiles

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "尚未设置 API Key。请点左上角「设置」填写 Anthropic API Key。"
        case .invalidImage:
            return "无法读取所选图片，请换一张试试。"
        case .requestFailed(let m):
            return "识别请求失败：\(m)"
        case .decodeFailed:
            return "无法解析识别结果，请重试或换一张更清晰的照片。"
        case .noTiles:
            return "未能从图片中识别到麻将牌，请确保牌面清晰、正对镜头。"
        }
    }
}

struct TileRecognitionService {
    var apiKey: String
    /// 视觉识别使用的模型，可在设置中修改
    var model: String

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func recognize(imageData: Data) async throws -> [MahjongCard] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw TileRecognitionError.missingAPIKey }
        guard let jpeg = Self.downscaledJPEG(from: imageData) else {
            throw TileRecognitionError.invalidImage
        }
        let b64 = jpeg.base64EncodedString()

        let prompt = """
        识别这张图片中的麻将牌。规则：四川麻将只有三种花色——万(wan)、筒(tong)、条(tiao)，\
        点数 1–9，没有字牌、花牌。请从左到右、从上到下，按顺序列出图中清晰可见的每一张牌\
        （通常是一手 13 或 14 张牌）。
        只输出 JSON，不要任何额外文字、解释或 Markdown 代码块，严格使用以下格式：
        {"tiles":[{"suit":"wan","rank":1},{"suit":"tong","rank":5}]}
        其中 suit 只能是 wan、tong、tiao 之一，rank 为 1 到 9 的整数。
        """

        let body: [String: Any] = [
            "model": model.trimmingCharacters(in: .whitespacesAndNewlines),
            "max_tokens": 1024,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image",
                     "source": ["type": "base64", "media_type": "image/jpeg", "data": b64]],
                    ["type": "text", "text": prompt]
                ]
            ]]
        ]

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 60

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw TileRecognitionError.requestFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TileRecognitionError.requestFailed("无响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TileRecognitionError.requestFailed(Self.apiErrorMessage(data) ?? "HTTP \(http.statusCode)")
        }

        let text = try Self.extractText(data)
        let tiles = try Self.parseTiles(text)
        guard !tiles.isEmpty else { throw TileRecognitionError.noTiles }
        return tiles
    }

    // MARK: - 图片处理

    /// 等比缩放到长边 ≤ maxDimension，并以 JPEG 编码，控制上传体积
    private static func downscaledJPEG(from data: Data, maxDimension: CGFloat = 1280, quality: CGFloat = 0.7) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let size = img.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let scaled = renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: newSize)) }
        return scaled.jpegData(compressionQuality: quality)
    }

    // MARK: - 响应解析

    private static func apiErrorMessage(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let err = obj["error"] as? [String: Any],
              let msg = err["message"] as? String else { return nil }
        return msg
    }

    private static func extractText(_ data: Data) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else {
            throw TileRecognitionError.decodeFailed
        }
        let text = content.compactMap { block -> String? in
            (block["type"] as? String) == "text" ? block["text"] as? String : nil
        }.joined()
        guard !text.isEmpty else { throw TileRecognitionError.decodeFailed }
        return text
    }

    private struct Payload: Decodable {
        let tiles: [Tile]
        struct Tile: Decodable { let suit: String; let rank: Int }
    }

    private static func parseTiles(_ text: String) throws -> [MahjongCard] {
        // 容错：从可能夹带的说明 / 代码块中截取首个 {...} JSON 对象
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            throw TileRecognitionError.decodeFailed
        }
        let json = String(text[start...end])
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8)) else {
            throw TileRecognitionError.decodeFailed
        }
        return payload.tiles.compactMap { t -> MahjongCard? in
            let suit: MahjongCard.Suit?
            switch t.suit.lowercased() {
            case "wan", "万", "m", "characters", "character", "wnn": suit = .wan
            case "tong", "筒", "p", "dots", "dot", "bing", "饼": suit = .tong
            case "tiao", "条", "s", "bamboo", "sticks", "stick", "索": suit = .tiao
            default: suit = nil
            }
            guard let s = suit, (1...9).contains(t.rank) else { return nil }
            return MahjongCard(suit: s, rank: t.rank)
        }
    }
}
