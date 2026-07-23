# App Store 提交资料包

这个文件夹收录了把「听牌计算器·四川麻将助手」上架到 App Store 所需的全部素材与文案。

## 文件夹内容

```
app store/
├── README.md                 ← 本文件：总览 + 提交清单 + 上架前必处理项
├── App Store Listing.md      ← 所有要填进 App Store Connect 的文案（可直接复制粘贴，中英双语）
├── Privacy Policy.md         ← 隐私政策正文（托管成网页后填链接，中英双语）
└── screenshots/
    ├── 6.5-inch/             ← 5 张 1242×2688 成品宣传图（直接上传 6.5" 槽位）
    │   ├── 1_tenpai.png      ← 听牌
    │   ├── 2_discard.png     ← 打牌建议
    │   ├── 3_shanten.png     ← 向听 + 进张
    │   ├── 4_input.png       ← 真实牌面 / 输入
    │   └── 5_scoring.png     ← 算番（番型明细 + 点炮/自摸金额）
    ├── raw/                  ← 不带文案的纯界面原图（每张对应 compose_promo.py 里的一条 SCREENS 配方）
    └── compose_promo.py      ← 重新套图脚本：raw/*.png → 6.5-inch/*.png（渐变背景+文案+圆角），见脚本内注释
```

## 上架步骤（概览）

1. 在 [App Store Connect](https://appstoreconnect.apple.com) → My Apps → ➕ 新建 App
   - 平台 iOS，主语言 简体中文，Bundle ID `ACM.majiang-calculator`，SKU 自取。
2. 按 `App Store Listing.md` 的分区，逐项把文案粘贴进去。
3. 上传 `screenshots/6.5-inch/` 的 5 张图到 6.5" 截图槽位。
4. 把 `Privacy Policy.md` 托管成网页，链接填到「隐私政策网址」。
5. 在 Xcode 里 Archive 并上传构建（版本 1.0 / build 1）。
6. 选中构建、填好年龄分级与 App 隐私问卷（答案见 Listing 文档），提交审核。

## ⚠️ 上架前必须处理（重要）

1. **识别模型的授权（可能阻塞上架，务必先确认）**
   App 内置的牌面识别模型 `Models/mahjong_yolov8.onnx` 来源参考自第三方仓库且**没有明确开源许可**。
   未经授权随 App **公开分发**存在侵权 / 合规风险。上架前请二选一：
   - 取得该模型的明确分发授权；或
   - 用自有数据训练 / 替换为有合法许可的模型。
   （应用里的牌面美术来自 FluffyStuff 的 CC0 公共领域素材，这部分没有问题。）

2. **出口合规**：在 `Info.plist` 增加 `ITSAppUsesNonExemptEncryption = NO`（App 不联网、无自有加密），免去每次上传被问加密的弹窗。

3. **部署目标版本不一致**：工程级 `IPHONEOS_DEPLOYMENT_TARGET` 为 26.2，目标级为 17.0。上架前确认最终生效的是一个你想支持的、已正式发布的 iOS 版本（建议 17.0），避免可安装设备范围异常。

4. **App 图标**：`Assets.xcassets/AppIcon.appiconset` 已含 light/dark/tinted 三种 1024 图标，确认渲染正常即可（App Store 会用 1024×1024 那张）。

5. **隐私政策与支持网址**：两者都是必填项，提交前必须是可访问的真实链接（见 Listing 文档第 4 节）。

## 截图尺寸补充

- 已提供 **6.5"（1242×2688）**。当前 App Store Connect 通常只强制要求 6.5"（或 6.7"/6.9"）其中一档；6.5" 这一套即可覆盖提交所需。
- 重新出图（改文案 / UI 变了要换新截图）：先用 Xcode 模拟器 + `SIMCTL_CHILD_DEMO_HAND`/`DEMO_MELDS`/`DEMO_SHEET`/`DEMO_ANALYZE`/`DEMO_NOSCROLL` 等 env hook（见 `MahjongViewModel.swift`/`ContentView.swift` 里的 `#if DEBUG` 块）截出新的 `raw/*.png`，改 `compose_promo.py` 里 `SCREENS` 对应条目的文案/raw 文件名，再 `python3 compose_promo.py` 重新生成 `6.5-inch/*.png`。
- 如果你想额外提供 **6.7"/6.9"（1290×2796）** 专属图，把 `compose_promo.py` 顶部 `CANVAS_W, CANVAS_H` 和 `PHONE_W` 改成对应尺寸重跑即可，版式逻辑不用改。
- iPad：当前 App 仅 iPhone（不需要 iPad 截图）。
