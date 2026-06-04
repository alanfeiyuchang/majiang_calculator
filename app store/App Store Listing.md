# App Store Connect — 提交资料（可直接复制粘贴）

> 本文档把上架 App Store 需要填写的每一项都写好了，按 App Store Connect 页面分区排列。
> 中文为主语言（简体中文），文末附英文版可用于英文本地化 / 美国区。
> 字数限制已在每项标注，所有内容均已控制在限制内。

---

## 0. 关键信息速查

| 项目 | 值 |
|---|---|
| Bundle ID | `ACM.majiang-calculator` |
| 版本号 (Marketing Version) | `1.0` |
| 构建号 (Build) | `1` |
| 最低系统 | iOS 17.0 |
| 设备 | 仅 iPhone（TARGETED_DEVICE_FAMILY = 1） |
| 开发团队 ID | `5V3HM8L9GT` |
| 主语言 | 简体中文 |
| 价格 | 免费（建议） |
| 内购 | 无 |
| 账号登录 | 无（无需注册/登录） |
| 联网 | 无（牌面识别完全在本机离线运行） |

> ⚠️ **上架前务必先看本文末「提交前必须处理」清单**，其中有一项关于识别模型授权的法律风险，可能阻塞上架。

---

## 1. App 信息（App Information）

**App 名称（App Name，≤30 字符）**
```
听牌计算器·四川麻将助手
```

**副标题（Subtitle，≤30 字符）**
```
拍照识别·向听进张·打牌建议
```

**类别（Category）**
- 主要类别：工具（Utilities）
- 次要类别：效率（Productivity）（可留空）

**版权（Copyright）**
```
© 2026 Feiyu Chang
```

> 把 `Feiyu Chang` 换成你要署名的个人名 / 公司名。

---

## 2. 价格与销售范围（Pricing and Availability）
- 价格：**免费（Free）**
- 销售范围：所有国家/地区，或按需选择（中国大陆为主要市场）

---

## 3. 本次版本信息（Version Information）

**推广文本（Promotional Text，≤170 字符，可随时改、无需审核）**
```
摸到一手牌不知道听什么？拍张照或点几下，立刻算出向听数、列出所有进张和能胡的牌，并告诉你打哪张最划算。专为四川麻将（缺一门·血战到底）打造。
```

**App 描述（Description，≤4000 字符）**
```
「听牌计算器」是一款为四川麻将打造的牌效分析工具。无论你是刚学牌还是想提升牌技，它都能帮你看清这手牌该怎么打。

把手里的牌点选进去，或者直接拍照让 App 自动识别，立刻得到清晰的分析结果：

• 听牌判断 —— 13 张牌一键判断是否听牌，并列出所有能胡的牌，缺一门规则下空听也会提醒。

• 向听数 + 进张 —— 还没听牌？告诉你离听牌还差几步（向听数），并列出所有能让你更近一步的进张牌，以及每种牌还剩几张。

• 打牌建议 —— 摸进第 14 张后，逐一比较每一种打法，按向听数和进张数排序，直接告诉你打哪张最优。

• 拍照识别 —— 对着牌桌上自己的手牌拍一张，App 自动识别万、筒、条。识别在手机本地完成，不联网、不上传，速度快也更放心。

• 真实牌面 —— 万、筒、条采用还原真实麻将的牌面设计，一眼就能分清，点选顺手。

专为四川麻将规则设计：
• 自动处理「缺一门」—— 三门花色齐全（花猪）会直接提示。
• 适配「血战到底」的牌型分析思路。

特点：
• 完全离线，不需要注册、不需要登录、不收集任何个人信息。
• 界面简洁，上手即用。
• 纯工具，无广告、无内购。

适合：想快速判断听牌、计算牌效、复盘练习的麻将爱好者。

注：本 App 是一款牌效计算与学习工具，不含任何真钱或模拟下注玩法。
```

**更新内容（What's New / Release Notes，≤4000 字符）**

> 1.0 是首次发布，可填：
```
首次发布：
• 拍照识别手牌（万 / 筒 / 条），本地离线识别。
• 一键判断听牌，列出所有能胡的牌。
• 计算向听数与进张，给出打牌建议。
• 还原真实麻将牌面设计，点选顺手。
• 适配四川麻将「缺一门 / 血战到底」规则。
```

---

## 4. 网址与联系信息（URLs）

> App Store 要求**必须填**「支持网址」和「隐私政策网址」。下面给了可直接使用的模板，
> 你需要把它们托管到任意可访问的网页（GitHub Pages / 个人站点 / Notion 公开页均可），再把链接填进去。

**支持网址（Support URL，必填）**
```
https://github.com/<你的用户名>/majiang-calculator
```
> 用一个 README 或简单页面即可，需有联系方式（邮箱）。

**营销网址（Marketing URL，可选）**
```
（可留空）
```

**隐私政策网址（Privacy Policy URL，必填）**
```
https://<你的隐私政策页面>
```
> 隐私政策正文见本文件夹的 `Privacy Policy.md`，照搬托管即可。

---

## 5. App 隐私（App Privacy）—— 问卷答案

在 App Store Connect 的「App 隐私」里如实回答：

**是否收集数据？** 选 **「不收集数据」（Data Not Collected）**。

理由（用于自己核对，也可写进审核备注）：
- 牌面识别在设备本地完成（ONNX YOLOv8 模型），**不联网、不上传照片**。
- 拍摄/选取的照片仅在本机用于识别，**不离开设备、不被收集**。
- 无账号、无分析 SDK、无广告 SDK、无第三方追踪。

> 因为没有任何数据离开设备，App 隐私可全部勾「不收集」。但**隐私政策网址仍然必填**（Apple 强制要求）。

---

## 6. 年龄分级（Age Rating）—— 问卷答案

逐项选择，结果应为 **4+**：
- 卡通或幻想暴力 / 现实暴力 / 色情 / 亵渎 / 恐怖 等：**全部「无」**
- **模拟赌博（Simulated Gambling）：无 / None** ✅（本 App 是计算器，不含任何对局或下注玩法）
- 真钱赌博与彩票：**否**
- 不受限网页访问：**否**
- 用户生成内容：**否**

> 说明：麻将本身常与博彩联想，但本 App 仅做牌效计算、不含任何游戏对局或下注，故「模拟赌博」应选「无」。在审核备注里也强调这一点（见第 8 节），可降低被退回风险。

---

## 7. App 审核信息（App Review Information）

**登录信息**：无需登录（勾选「Sign-in not required」）。

**联系人**：填你的姓名、电话、邮箱。

**备注（Notes，给审核员看，可直接粘贴）**
```
本 App 是四川麻将的牌效计算 / 学习工具，不含任何对局玩法、真钱或模拟下注。

主要功能：
1. 手动点选或拍照识别手牌（万/筒/条）。
2. 计算是否听牌、向听数、进张，并给出打牌建议。

关于权限与隐私：
- 相机权限仅用于拍摄牌桌上的麻将牌以识别手牌。
- 牌面识别使用打包在 App 内的本地模型完成，全程离线，不联网、不上传照片、不收集任何数据。
- 无需注册或登录。

如何测试：
- 直接用底部键盘点选牌（万/筒/条 各 1–9），凑够 13 张点「分析手牌」即可看到听牌/向听结果；
  凑 14 张可看到打牌建议。无需相机也能完整体验核心功能。
```

---

## 8. 构建与导出合规（Build & Export Compliance）

- 上传构建：用 Xcode → Product → Archive，或 `xcodebuild` 归档后通过 Organizer / Transporter 上传。
- **出口合规（Encryption）**：App 不含任何自有加密、且不联网。建议在 `Info.plist` 加：
  ```
  ITSAppUsesNonExemptEncryption = NO
  ```
  这样每次上传不会再被问「是否使用加密」。

---

## 9. 截图（Screenshots）

- `screenshots/6.5-inch/` 内的 4 张为 **1242 × 2688**（6.5" 显示屏）成品图，可直接上传到 6.5" 槽位。
  - 6.5" 槽位同样接受这些图用于覆盖到更大尺寸；如需 6.7"/6.9" 专属图可另出（见 README）。
- `screenshots/raw/` 为不带文案的纯界面原图，留作备用 / 二次设计。

App Store 6.5" 截图要求：1242×2688 或 1284×2778，竖屏，PNG/JPG，最多 10 张。本套已满足。

---

# English version (for an English localization / US storefront)

**App Name (≤30)**
```
Tenpai Helper: Mahjong Calc
```

**Subtitle (≤30)**
```
Scan tiles · waits · discards
```

**Promotional Text (≤170)**
```
Not sure what your hand is waiting on? Snap a photo or tap your tiles to instantly get shanten, every useful draw, the tiles you can win on, and the best discard.
```

**Description (≤4000)**
```
Tenpai Helper is a hand-efficiency tool for Sichuan-style mahjong. Whether you're learning or sharpening your game, it shows you exactly how to play your hand.

Tap your tiles in, or photograph them and let the app recognize them automatically, then get an instant, clear analysis:

• Waits (tenpai) — Instantly tell whether 13 tiles are ready, and list every tile you can win on.

• Shanten + acceptance — Not there yet? See how many steps away you are, every tile that gets you closer, and how many of each remain.

• Discard advice — After drawing your 14th tile, compare every discard and see which one keeps you most efficient.

• Photo recognition — Point your camera at your hand and the app reads the tiles. Recognition runs entirely on your device — no internet, nothing uploaded.

• Realistic tiles — Characters, dots, and bamboo are drawn to look like real mahjong tiles, easy to read and tap.

Built for Sichuan rules: it handles the "missing-one-suit" requirement and flags hands that hold all three suits.

• Fully offline. No account, no login, no data collected.
• Clean and simple. No ads, no in-app purchases.

Note: this is a calculator and study tool. It contains no real-money or simulated betting.
```

**Keywords (English, ≤100, comma-separated)**
```
mahjong,tenpai,shanten,sichuan mahjong,tile efficiency,waits,discard,calculator,riichi,ukeire
```

**What's New (1.0)**
```
First release:
• On-device photo recognition of your hand (characters/dots/bamboo).
• Instant tenpai detection with all winning tiles listed.
• Shanten and acceptance calculation, plus discard advice.
• Realistic mahjong tile artwork.
• Built for Sichuan rules.
```

---

## 关键词（中文主语言，Keywords，≤100 字符，逗号分隔无空格）
```
麻将,四川麻将,听牌,向听,进张,打牌,牌效,血战到底,缺一门,麻将计算器,算牌,胡牌,麻将助手
```
> 上面这串约 60 个中文字符，未超 100。名称/副标题里已出现的词可不必再放进关键词，把额度留给其它词。
