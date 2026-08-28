# 听牌计算器 · Mahjong Tenpai Calculator

An iOS app that tells you what you're waiting on (听牌), what each wait is worth,
and can read your hand — plus your melds — straight from a **photo** using an
on-device AI model. No network, no API key.

Two rule sets, switchable in settings:

- **四川麻将 / 血战到底 (Sichuan)** — 缺一门, no chow, fan doubling and money.
- **国标麻将 / MCR (Chinese Official Rules)** — full tile set, chow, the 81 fan
  types and the 8-point minimum.

<p align="center">
  <img src="majiang%20calculator/Assets.xcassets/AppIcon.appiconset/icon-light.png" width="120" alt="App icon">
</p>

## Features

- **玩法选择 (game mode).** The setting at the top of the rules screen switches the
  whole app between Sichuan and MCR: tile keypad, meld types, win detection,
  scoring and the fan reference all follow. The choice is persisted; Sichuan is
  the default and is byte-for-byte the same experience as before.
- **Correct Sichuan rules.** Win/wait detection enforces the rules that actually
  matter in Sichuan play:
  - **缺一门 (missing-one-suit):** a winning hand may contain at most two of the
    three suits (万/筒/条). Three suits = 花猪 (flower pig) and cannot win.
  - **七对 (seven pairs)**, including **豪华七对 / 龙七对** (a kong counts as two pairs).
  - Standard form (1 pair + 4 melds) of course.
- **手牌 + 桌上的牌 (hand + table melds).** Pong / exposed kong / concealed kong are
  entered separately from your concealed hand and participate fully in win/wait
  detection and scoring — e.g. two pongs correctly leave you with a 7-tile hand
  to wait on, not 13.
- **番数 + 金额 (fan scoring & payouts).** Every wait shows its fan count and the
  money it settles for (discard-win vs. self-draw), computed by a full 川麻 scoring
  engine: 碰碰胡, 清一色, 七小对/豪华七小对, 金钩钓, 十八罗汉, 将对/将七对, 门清,
  断幺九, 根, 杠上开花/杠上炮/抢杠胡/海底捞月/天胡/地胡, and more. Tap any fan for
  a one-line explanation of what it means.
- **规则设置 (rule settings), because every table's rules differ.** Base stake, fan
  cap, how 自摸/根 are scored (add fan / add base / off, and whether only kongs
  count as 根), which fan types are even in play, 金钩钓's fan value, 将对/将七对
  on or off — all persisted and reflected live in every calculation. A built-in
  番型一览 reference lists every fan and its current value.
- **Partial hands.** Enter 1 / 4 / 7 / 10 / 13 tiles and it computes the waits,
  treating the not-yet-drawn tiles as completable melds — e.g. `1234万` → waits `1万 4万`.
- **向听数 + 进张 + 打牌建议 (shanten / acceptance / discard advice).**
  - 13-tile (or 3n+1) hands not yet ready show the **向听数** and every **进张**
    (improving tile) with how many of each remain. Tenpai shows the waits (with
    fan/money); a 空听 (all winners already in hand) is flagged.
  - 14-tile (or 3n+2) hands get **打牌建议**: each discard ranked by resulting
    向听, then 进张 count, then the fan of the resulting wait — so you know what
    to throw. Respects 缺一门 and 七对.
- **📷 Photo recognition (on-device), no cropping required.** Take or pick a photo
  of the whole table area; a bundled YOLOv8 model detects every tile, then a
  two-pass pipeline (wide detection pass to locate the tiles, then a cropped,
  zoomed-in re-detection) reads them sharply even when tiles are small in frame.
  Tiles are automatically grouped by position into your **concealed hand** and
  **table melds** (pong / exposed kong / a concealed kong's one visible tile),
  even when several melds sit right next to each other — and the analysis runs
  immediately, no confirmation step. Runs fully offline. Manual cropping is still
  available for messy table photos.
- **Bilingual, defaults to Chinese.** A one-tap globe button switches the whole
  UI between 中文 and English, independent of the system language.
- **Clean tile keypad** for manual entry (hand or melds), with auto-sort and undo.

## 国标麻将 (MCR)

Selecting 国标麻将 switches the engine to the *Chinese Official Rules*:

- **Tiles.** The three numbered suits plus **winds (东南西北)**, **dragons (中发白)**
  and **flowers (春夏秋冬梅兰竹菊)**. Flowers never take part in the hand — they are
  held separately and score 1 point each. Honours and flowers have no artwork in
  the asset catalogue, so they are drawn as text tile faces.
- **Melds.** 吃 (chow) joins 碰 / 明杠 / 暗杠. Tap the lowest tile and the run is
  filled in for you. A chow may legally only be claimed from the player to your
  left; as an analysis tool this app does **not** enforce that, and says so in the
  meld section.
- **Winning shapes.** Standard (4 sets + a pair, honours can only form pungs),
  七对 / 连七对, 十三幺, 全不靠 / 七星不靠, and 组合龙 (the knitted straight, whose
  fourth set may be melded). Sichuan's 缺一门 / 花猪 restriction is fully disabled.
- **Scoring.** All **81 fan types**, 8-point minimum to win, flowers scored but
  excluded from that minimum. The **non-repeat principles** are implemented rather
  than approximated — see [`MCRScoring.swift`](majiang%20calculator/MCRScoring.swift):
  - *不可拆分 / 套算一次 / 就高不就低* — set-structure fan (一般高, 喜相逢, 清龙,
    一色三同顺, 双同刻 …) are found by taking the **highest-scoring set partition**
    of the four melds, so a meld can never be reused in two different fan.
  - *不可重复* — an explicit exclusion table (`mcrFanExcludes`) removes lower fan
    already implied by a higher one (大三元 removes 箭刻/双箭刻, 清一色 removes
    无字/缺一门, 四暗刻 removes 碰碰和/三暗刻/双暗刻, …).
  - The whole hand is evaluated over every winning shape × every decomposition ×
    every reading of the winning tile, and the best total wins.
  - A pung completed by someone else's discard counts as **melded**, so the same
    tiles score 四暗刻 on a self-draw but only 三暗刻 on a discard.
- **圈风 / 门风** are set in the rules screen and feed 圈风刻 / 门风刻.
- **Photo recognition is limited here.** The bundled YOLO model only knows the 27
  numbered classes, so winds, dragons and flowers are **never** recognised. In MCR
  mode every recognition result carries a notice saying so; add the missing honours
  and flowers with the keypad.

## Tiles

Sichuan mahjong uses only the three numbered suits, 1–9 each:

| Suit | 中文 | Model class suffix |
|------|------|--------------------|
| Characters | 万 (wan)  | `C` |
| Dots       | 筒 (tong) | `D` |
| Bamboo     | 条 (tiao) | `B` |

No winds, dragons, flowers, or seasons — those exist only in the MCR rule set, and
only as manual input.

## How the recognition works

1. (Optional) crop to just the area you care about — cropping is how you exclude
   other players' tiles, the wall, or discards from a busy table photo. A full,
   uncropped photo works too.
2. The image is letterbox-resized to 640×640 (gray padding), normalized to RGB/255, CHW,
   and run through a YOLOv8 model (`Models/mahjong_yolov8.onnx`) via **ONNX Runtime**,
   output shape `[1, 46, 8400]` (4 box coords + 42 tile classes).
3. A first pass at a low confidence threshold locates *where* the tiles are in the
   frame. If they occupy only a small region (common in a whole-table shot), that
   region is cropped out of the original image, upscaled, and re-run through the
   model at the normal threshold — so small, distant tiles still get read sharply.
4. Confidence threshold + NMS on the final pass; classes `1C…9C / 1D…9D / 1B…9B`
   map to 万/筒/条 (all other classes — flowers, seasons, winds, dragons — are
   ignored, since Sichuan doesn't use them).
5. Detected tiles are grouped by on-screen position: rows by vertical center,
   then columns by horizontal gap. The largest cluster is your concealed hand;
   separated clusters are read as melds — a run of 3 identical tiles is a pong,
   4 is an exposed kong, and a lone tile is treated as the one visible tile of a
   concealed kong (flagged as a guess, since the other three tiles are face-down
   and physically invisible to the camera). Several melds sitting flush against
   each other are still split correctly by looking for repeated-tile runs.
6. The result fills in **手里的牌** and **桌上的牌** and the analysis runs
   immediately — no confirmation step. If a concealed kong was guessed or tiles
   had to be dropped to fit, a small non-blocking notice says so underneath the
   result.

The recognizer lives in [`LocalTileRecognizer.swift`](majiang%20calculator/LocalTileRecognizer.swift),
the grouping logic in [`TileGrouping.swift`](majiang%20calculator/TileGrouping.swift), the win/wait
rules engine in [`MahjongCalculator.swift`](majiang%20calculator/MahjongCalculator.swift), and the
fan-scoring engine in [`MahjongScoring.swift`](majiang%20calculator/MahjongScoring.swift).

## Build & run

- **Xcode** with a recent iOS SDK. Deployment target is **iOS 17.0+**.
- Open `majiang calculator.xcodeproj` and build. On first open, Xcode resolves the
  **ONNX Runtime** Swift package (downloads the native binary once — needs network).
- Photo from the library works in the simulator; the **camera** requires a real device.

If Xcode reports *"Missing package product 'onnxruntime'"*, quit Xcode, then
**File ▸ Packages ▸ Reset Package Caches** and **Resolve Package Versions**.

## Tests

```bash
./Tests/run.sh
```

Assembles the pure-logic sources (`MahjongCard`/`Meld`/`GameMode`/`MahjongCalculator`/
`MCRCalculator`/`MahjongScoring`/`MCRScoring`/`TileGrouping`, with the `@MainActor` UI-facing
bits stripped) plus everything in `Tests/` into one file and runs it with `swift` directly —
no Xcode project, no simulator. **Exits non-zero if any assertion fails.** Covers Sichuan
scoring (every fan type, rule-setting permutation, capped/uncapped payouts), photo-recognition
grouping (hand/meld separation, adjacent-meld splitting, the two-pass zoom region), discard
evaluation, and the MCR engine (winning shapes, shanten/waits with honours, every one of the
81 fan types, the non-repeat principles, and the 8-point minimum). A companion Android test
suite (`majiang-calculator-android`) mirrors the Sichuan assertions case-for-case — the two
apps should never disagree. **MCR is iOS-only for now**; the Android port has not been updated.

## Tech

- SwiftUI, iOS 17.0+.
- [ONNX Runtime — Swift Package](https://github.com/microsoft/onnxruntime-swift-package-manager) (`onnxruntime`, product module `OnnxRuntimeBindings`).
- YOLOv8 object detection model in ONNX format.

## Android

A Kotlin + Jetpack Compose port of the **Sichuan** side with feature parity — same
scoring engine, same rule settings, same recognition pipeline, same bilingual strings
— lives at
[**majiang_calculator_android**](https://github.com/alanfeiyuchang/majiang_calculator_android).

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
