//
//  ReviewPromptTests.swift
//  什么时候找用户要评分。系统弹窗一年只有 3 次，规则写错了就白白浪费掉，
//  而且线上看不出来——所以这里逐条钉死。
//
//  两步：分析成功攒次数（够了「上膛」），用户清空 / 开下一局时才真的弹。
//  出结果那一刻不弹——那会儿用户正在读结果。
//

print("\n— 评分提示的触发规则 —")
var rFails = 0
func rcheck(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    if ok { print("  ✓ \(name)") }
    else { rFails += 1; print("  ✗ FAIL \(name)  \(detail())") }
}

func freshDefaults(_ name: String) -> UserDefaults {
    let d = UserDefaults(suiteName: "test.review.\(name)")!
    d.removePersistentDomain(forName: "test.review.\(name)")
    return d
}

do {
    // 攒够 8 次才上膛，而且上膛不等于弹——得等用户开下一手
    let d = freshDefaults("threshold")
    var firedAt: [Int] = []
    for i in 1...12 {
        ReviewPrompt.recordSuccess(defaults: d)
        if ReviewPrompt.consumePendingAsk(defaults: d) { firedAt.append(i) }
    }
    rcheck(firedAt == [8], "RV1 攒够 8 次才弹，且只弹一次", "在第 \(firedAt) 次弹了")
}
do {
    // 光分析、不开下一手，一次都不该弹
    let d = freshDefaults("noconsume")
    for _ in 1...50 { ReviewPrompt.recordSuccess(defaults: d) }
    rcheck(ReviewPrompt.consumePendingAsk(defaults: d), "RV2 攒够后第一次开下一手会弹")
    var again = false
    for _ in 1...20 {
        ReviewPrompt.recordSuccess(defaults: d)
        if ReviewPrompt.consumePendingAsk(defaults: d) { again = true }
    }
    rcheck(!again, "RV3 同一版本弹过就不再弹")
}
do {
    // 前 7 次哪怕一直清空重来也不该弹
    let d = freshDefaults("early")
    var early = false
    for _ in 1...7 {
        ReviewPrompt.recordSuccess(defaults: d)
        if ReviewPrompt.consumePendingAsk(defaults: d) { early = true }
    }
    rcheck(!early, "RV4 前 7 次不开口")
}
do {
    // 没分析过就一通乱点清空，不该弹
    let d = freshDefaults("bare")
    var fired = false
    for _ in 1...30 where ReviewPrompt.consumePendingAsk(defaults: d) { fired = true }
    rcheck(!fired, "RV5 没攒够就清空，不弹")
}
do {
    let d = freshDefaults("reset")
    for _ in 1...8 { ReviewPrompt.recordSuccess(defaults: d) }
    _ = ReviewPrompt.consumePendingAsk(defaults: d)
    ReviewPrompt.reset(defaults: d)
    var firedAt: [Int] = []
    for i in 1...10 {
        ReviewPrompt.recordSuccess(defaults: d)
        if ReviewPrompt.consumePendingAsk(defaults: d) { firedAt.append(i) }
    }
    rcheck(firedAt == [8], "RV6 reset 之后从头计数", "在第 \(firedAt) 次弹了")
}
do {
    let url = ReviewPrompt.writeReviewURL?.absoluteString ?? ""
    rcheck(url == "https://apps.apple.com/app/id6776462266?action=write-review",
           "RV7 写评价链接正确", "got \(url)")
}

print(rFails == 0 ? "评分提示全部通过 ✅" : "❌ 评分提示 \(rFails) 个失败")
