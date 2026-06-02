# 听牌计算器 · Sichuan Mahjong Tenpai Calculator

An iOS app for **Sichuan mahjong (四川麻将 / 血战到底)** that tells you what you're
waiting on (听牌), and can read your hand straight from a **photo** using an
on-device AI model — no network, no API key.

<p align="center">
  <img src="majiang%20calculator/Assets.xcassets/AppIcon.appiconset/icon-light.png" width="120" alt="App icon">
</p>

## Features

- **Correct Sichuan rules.** Win/wait detection enforces the rules that actually
  matter in Sichuan play:
  - **缺一门 (missing-one-suit):** a winning hand may contain at most two of the
    three suits (万/筒/条). Three suits = 花猪 (flower pig) and cannot win.
  - **七对 (seven pairs)**, including **龙七对** (a kong counts as two pairs).
  - Standard form (1 pair + 4 melds) of course.
- **Partial hands.** Enter 1 / 4 / 7 / 10 / 13 tiles and it computes the waits,
  treating the not-yet-drawn tiles as completable melds — e.g. `1234万` → waits `1万 4万`.
- **📷 Photo recognition (on-device).** Take or pick a photo, **drag the crop box
  over just your own hand** (so tiles laying around the table — discards, the wall,
  other players' melds — are excluded), and a bundled YOLOv8 model recognizes the
  tiles, fills in the hand, and computes the result. Runs fully offline.
- **Clean tile keypad** for manual entry, with auto-sort and undo.

## Tiles

Sichuan mahjong uses only the three numbered suits, 1–9 each:

| Suit | 中文 | Model class suffix |
|------|------|--------------------|
| Characters | 万 (wan)  | `C` |
| Dots       | 筒 (tong) | `D` |
| Bamboo     | 条 (tiao) | `B` |

No winds, dragons, flowers, or seasons.

## How the recognition works

0. You crop the photo to just your hand (the model detects *every* tile in frame,
   so cropping is what disambiguates your tiles from the rest of the table).
1. The cropped image is letterbox-resized to 640×640 (gray padding), normalized to RGB/255, CHW.
2. A YOLOv8 model (`Models/mahjong_yolov8.onnx`) runs via **ONNX Runtime**, output
   shape `[1, 46, 8400]` (4 box coords + 42 tile classes).
3. Confidence threshold + NMS, then boxes are sorted in reading order.
4. Classes `1C…9C / 1D…9D / 1B…9B` map to 万/筒/条; all other classes
   (flowers, seasons, winds, dragons) are ignored, since Sichuan doesn't use them.

The recognizer lives in [`LocalTileRecognizer.swift`](majiang%20calculator/LocalTileRecognizer.swift);
the rules engine lives in [`MahjongCalculator.swift`](majiang%20calculator/MahjongCalculator.swift).

## Build & run

- **Xcode** with a recent iOS SDK. Deployment target is **iOS 17.6+**.
- Open `majiang calculator.xcodeproj` and build. On first open, Xcode resolves the
  **ONNX Runtime** Swift package (downloads the native binary once — needs network).
- Photo from the library works in the simulator; the **camera** requires a real device.

If Xcode reports *"Missing package product 'onnxruntime'"*, quit Xcode, then
**File ▸ Packages ▸ Reset Package Caches** and **Resolve Package Versions**.

## Tech

- SwiftUI, iOS 17.6+.
- [ONNX Runtime — Swift Package](https://github.com/microsoft/onnxruntime-swift-package-manager) (`onnxruntime`, product module `OnnxRuntimeBindings`).
- YOLOv8 object detection model in ONNX format.

## 🙏 Acknowledgements

The on-device tile-recognition model (`Models/mahjong_yolov8.onnx`) and the
detection pipeline it's based on come from the excellent
**[AR-Mahjong-Assistant-preview](https://github.com/LYiHub/AR-Mahjong-Assistant-preview)**
project by [**@LYiHub**](https://github.com/LYiHub) — an AR-glasses mahjong assistant
built around a shanten/efficiency engine and a local YOLOv8 recognizer. Huge thanks
for making the trained model and inference code available; this app would not have
an offline recognizer without it. Please go check out their work. 🀄️

> **Note on the model:** the reference repository does not currently carry an explicit
> open-source license, so the bundled model weights are included here for **personal
> use** only. If you intend to distribute this app, please obtain permission from the
> original author or train/substitute your own model.

## License

The app's own source code in this repository is provided as-is for personal use.
The bundled model weights are subject to the note above.
