# App Store Connect — 提交资料（可直接复制粘贴）

> 本文档把上架 App Store 需要填写的每一项都写好了，按 App Store Connect 页面分区排列。
> 中文为主语言（简体中文），文末附英文版可用于英文本地化 / 美国区。
> 字数限制已在每项标注，所有内容均已控制在限制内。

---

## 0. 关键信息速查

| 项目 | 值 |
|---|---|
| Bundle ID | `ACM.majiang-calculator` |
| 版本号 (Marketing Version) | `1.3` |
| 构建号 (Build) | 由 Xcode Cloud 递增，提交前以实际上传的为准 |
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
四川血战·国标算番·拍照识别
```
> 1.3 起支持国标麻将，旧副标题「拍照识别·算番算钱·向听建议」没体现玩法，已换。
> App 名称保持不动：「四川麻将」是现有搜索权重所在，换名会丢排名，国标放副标题里带。

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
四川血战到底、国标麻将都能算。拍张照，手牌、碰杠吃、风箭花自动认出来——听牌、向听、打哪张、几番多少钱，一次算清。规则照你们牌桌调，标题点一下换玩法。
```
> 75 字符。上一版（只提四川）：
> `手牌一输，答案就出：听不听牌、还差几张、打哪张最优、这把能赢多少钱——App 帮你一次算清。拍照或点选都行，规则还能照你们牌桌调整。四川麻将玩家的算牌神器。`

**App 描述（Description，≤4000 字符）**
```
打牌纠结要多久，「听牌计算器」就能替你省多久。手机镜头一扫，或者手动点几下，向听、听牌、该打哪张、能胡多少钱——瞬间全部算清楚。四川麻将（缺一门 · 血战到底）与国标麻将都支持，新手复盘、老手图省事，都用得上。

• 听牌一眼看穿 —— 手牌输进去，是否听牌、能胡哪些牌，立刻列清楚；空听也会提醒你，别空欢喜一场。

• 算番算钱，不用再心算 —— 每张听牌自动算好番数和输赢金额，点炮、自摸分开算。碰碰胡、清一色、七小对、豪华七对、金钩钓、十八罗汉、杠上开花、天胡地胡……几十种番型全覆盖，点一下还能看懂番型是什么意思。

• 向听 + 进张，心里有数 —— 还没听牌？离听牌差几张、摸哪张最有用、每种还剩几张，全部摆在眼前。

• 打牌建议，替你选最优解 —— 摸到第 14 张纠结打哪张？逐张比较向听数、进张数和番数，直接告诉你打哪张最划算。

• 拍照识别，懒人福音 —— 对着牌桌一拍，不用特意框选，万筒条自动认出来，碰、杠也帮你分好，识别完直接出结果。全程本地识别，不联网、不上传，你的牌只有你自己看得到。

• 规则跟着牌桌走 —— 底分、番数上限、自摸和根怎么算、每种番型开不开，你们的规矩你说了算，改一次全局生效，还有番型一览随时查。

• 牌面做得跟真的一样 —— 万、筒、条都是写实牌面设计，一眼分清花色点数，点起来也顺手。

• 中英双语，一键切换 —— 界面语言自己选，不跟系统语言走。

四川麻将规则从骨子里适配：自动识别「缺一门」，三门花色齐全（花猪）直接提示；血战到底的算法逻辑全部内建。
国标麻将同样是完整实现：81 种番种、起和 8 分、吃碰杠与风箭花齐全，几处各地写法有分歧的规则做成了开关，照你们的打法选。

完全离线运行，不需要注册、不需要登录，不收集任何个人信息。界面简洁，没有广告，没有内购，就是一个纯粹好用的工具。

无论是刚学四川麻将、想练手复盘，还是打惯了图个省事算钱，这款 App 都合适。

注：本 App 是一款牌效计算与学习工具，不含任何真钱或模拟下注玩法。
```

**更新内容（What's New / Release Notes，≤4000 字符）**

> **1.3（当前版本）**
```
这一版加了国标麻将，拍照也认得更全了。

• 新增国标麻将。81 种番种、起和 8 分、可以吃，风牌箭牌花牌都能用。四川血战到底照旧，两套规则各算各的。
• 标题点一下就换玩法。「听牌计算器 · 川麻」和「· 国标」之间随时切，不用再进设置页翻。
• 拍照现在认得出风、箭、花。以前这三类牌一律被丢掉——其实模型一直认得，是 App 没收。
• 拍照也认得出吃了。桌上摆开的顺子会被单独分成一副，不再混进手牌。
• 框选更准。把牌分组的间距阈值重新按实拍数据校准过，副露摆得离手牌近一些也能分开。
• 修好一处国标下的错误：识别到的风牌箭牌在回填时会被整批丢掉。
```

> 1.2
```
这一版重做了拍照识别。

• 拍完自动框出你的牌：手牌和已经碰/杠的牌都在框里，桌上别人的牌、中间的弃牌堆留在框外。框得不准，拖四角或四边随手改。
• 认牌更准。修好了一处影响识别质量的老问题，牌面认得比以前稳不少。
• 桌上的碰/杠不再漏。平摊在桌上的副露以前常被当成别人的牌丢掉，现在能正常认出来。
• 张数不对会明说。识别结果凑不齐 13 或 14 张时会提示你核对，不会闷头算出一副根本不存在的牌。
• 修好了英文界面下几处仍显示中文的文案。
```

> 1.0 是首次发布，可填：
```
首次发布，核心功能一次给齐：
• 拍照识别手牌和桌上的碰/杠——万、筒、条自动认，不用框选，本地识别不联网。
• 一键判断听牌，列出所有能胡的牌，每张听牌自动算好番数和输赢金额。
• 向听数 + 进张一目了然，还给打牌建议，摸到第 14 张不用再纠结。
• 规则设置随你调：底分、封顶、自摸和根怎么算、各番型开关，改一次全局生效。
• 中英双语界面，一键切换。
• 万、筒、条都是写实牌面设计，一眼分清，点选顺手。
• 专为四川麻将「缺一门 · 血战到底」打造。
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

- `screenshots/6.5-inch/` 内的 5 张为 **1242 × 2688**（6.5" 显示屏）成品图，可直接上传到 6.5" 槽位：听牌、打牌建议、向听、真实牌面、算番（番型明细 + 点炮/自摸金额）。
  - 6.5" 槽位同样接受这些图用于覆盖到更大尺寸；如需 6.7"/6.9" 专属图可另出（见 README）。
- `screenshots/raw/` 为不带文案的纯界面原图，`compose_promo.py` 是重新套图的脚本，留作备用 / 二次设计。

App Store 6.5" 截图要求：1242×2688 或 1284×2778，竖屏，PNG/JPG，最多 10 张。本套已满足。

---

# English version (for an English localization / US storefront)

**App Name (≤30)**
```
Tenpai Helper: Mahjong Calc
```

**Subtitle (≤30)**
```
Sichuan + MCR · Scan · Score
```

**Promotional Text (≤170)**
```
Sichuan and Chinese Official (MCR), both covered. Snap a photo — hand, melds, chows, winds and flowers read automatically. Tap the title to switch rulesets.
```

**Description (≤4000)**
```
Tenpai Helper is a hand-efficiency and scoring tool for Sichuan-style mahjong. Whether you're learning or sharpening your game, it shows you exactly how to play your hand — and how much it's worth.

Tap your tiles and melds in, or photograph them and let the app recognize them automatically, then get an instant, clear analysis:

• Waits (tenpai) — Instantly tell whether your hand is ready, and list every tile you can win on.

• Fan scoring & payouts — Every wait comes with its fan count and exact payout (discard-win vs. self-draw), covering all-pongs, flush, seven pairs / grand seven pairs, single-wait pairs, and more. Tap any fan for a one-line explanation.

• Hand + table melds — Enter pongs, exposed kongs, and concealed kongs separately from your concealed hand; they're correctly factored into waits and scoring.

• Rule settings — Base stake, fan cap, how self-draw/kongs are scored, which fan types are in play — all persisted and applied live, so it matches how your table actually plays.

• Shanten + acceptance — Not there yet? See how many steps away you are, every tile that gets you closer, and how many of each remain.

• Discard advice — After drawing your 14th tile, compare every discard by shanten, acceptance, and resulting fan, and see which one's best.

• Photo recognition — Point your camera at the table, no cropping needed. The app reads your tiles, separates your hand from table melds, and shows the result immediately. Runs entirely on your device — no internet, nothing uploaded.

• Realistic tiles — Characters, dots, and bamboo are drawn to look like real mahjong tiles, easy to read and tap.

• Bilingual — Switch between English and Chinese with one tap, independent of your system language.

Built for Sichuan rules: it handles the "missing-one-suit" requirement and flags hands that hold all three suits. Chinese Official (MCR) is fully implemented too — all 81 fan, an 8-point minimum, chows, winds, dragons and flowers, with toggles for the handful of rules that vary between rulebooks.

• Fully offline. No account, no login, no data collected.
• Clean and simple. No ads, no in-app purchases.

Note: this is a calculator and study tool. It contains no real-money or simulated betting.
```

**Keywords (English, ≤100, comma-separated)**
```
mahjong,tenpai,shanten,sichuan mahjong,mcr,chinese official,tile efficiency,waits,discard,fan,score
```

**What's New (1.3, current)**
```
This update adds Chinese Official rules, and photo recognition now reads more of the table.

• Chinese Official (MCR) added. All 81 fan, an 8-point minimum, chow melds, and winds, dragons and flowers. Sichuan Bloody rules are untouched — each ruleset scores on its own terms.
• Tap the title to switch rulesets. Move between "Tenpai Calculator · Sichuan" and "· MCR" without digging into settings.
• Photos now read winds, dragons and flowers. These were being discarded before — the model could always see them, the app just wasn't taking them.
• Photos now read chow melds. A run laid out on the table is grouped as its own meld instead of ending up in your hand.
• Better grouping. The gap threshold that separates melds from your hand was recalibrated against real photos, so melds placed close to your hand still get split off.
• Fixed a bug where recognized winds and dragons were dropped when filling the hand in MCR mode.
```

**What's New (1.2)**
```
This update rebuilds photo recognition.

• Your tiles get framed automatically. The box covers your hand and anything you've ponged or konged, and leaves out other players' tiles and the discard pile. If it's off, drag a corner or an edge.
• Better recognition. Fixed a long-standing problem that was hurting accuracy — tiles read far more reliably now.
• Melds on the table are no longer dropped. Pongs and kongs lying flat used to get mistaken for other players' tiles.
• It tells you when the tile count is wrong. If what it read doesn't add up to 13 or 14, you get a prompt to check, instead of a score for a hand that was never on the table.
• Fixed several labels that stayed in Chinese in the English interface.
```

**What's New (1.0)**
```
First release:
• On-device photo recognition of your hand and melds (characters/dots/bamboo), no cropping needed.
• Instant tenpai detection with all winning tiles, fan count, and payout.
• Shanten and acceptance calculation, plus discard advice.
• Rule settings so scoring matches how your table plays.
• Bilingual interface (English/Chinese), one tap to switch.
• Realistic mahjong tile artwork.
• Built for Sichuan rules.
```

---

## 关键词（中文主语言，Keywords，≤100 字符，逗号分隔无空格）
```
麻将,四川麻将,国标麻将,国标,听牌,向听,进张,牌效,血战到底,缺一门,算番,番种,吃碰杠,麻将计算器,麻将助手
```
> 57 字符，未超 100。1.3 加入「国标麻将 / 国标 / 番种 / 吃碰杠」，
> 挤掉了「打牌 / 规则设置」这两个搜索量低的词。
