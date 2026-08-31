//
//  ReviewPromptTests.swift
//  什么时候找用户要评分。系统弹窗一年只有 3 次，规则写错了就白白浪费掉，
//  而且线上看不出来——所以这里逐条钉死。
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
    let d = freshDefaults("threshold")
    var asked: [Int] = []
    for i in 1...12 where ReviewPrompt.recordSuccessAndShouldAsk(defaults: d) { asked.append(i) }
    rcheck(asked == [8], "RV1 攒够 8 次成功才问，且只问一次", "在第 \(asked) 次问了")
}
do {
    // 同一个版本问过一次就不再问，哪怕继续用
    let d = freshDefaults("once")
    for _ in 1...8 { _ = ReviewPrompt.recordSuccessAndShouldAsk(defaults: d) }
    var again = false
    for _ in 1...50 where ReviewPrompt.recordSuccessAndShouldAsk(defaults: d) { again = true }
    rcheck(!again, "RV2 同一版本问过就不再问")
}
do {
    // 前 7 次一次都不该问——太早开口会把一年 3 次的额度浪费在还没觉得好用的人身上
    let d = freshDefaults("early")
    var earlyAsk = false
    for _ in 1...7 where ReviewPrompt.recordSuccessAndShouldAsk(defaults: d) { earlyAsk = true }
    rcheck(!earlyAsk, "RV3 前 7 次不开口")
}
do {
    let d = freshDefaults("reset")
    for _ in 1...8 { _ = ReviewPrompt.recordSuccessAndShouldAsk(defaults: d) }
    ReviewPrompt.reset(defaults: d)
    var asked: [Int] = []
    for i in 1...10 where ReviewPrompt.recordSuccessAndShouldAsk(defaults: d) { asked.append(i) }
    rcheck(asked == [8], "RV4 reset 之后从头计数", "在第 \(asked) 次问了")
}
do {
    // 写评价的直达链接得是 App Store 认的那种形式
    let url = ReviewPrompt.writeReviewURL?.absoluteString ?? ""
    rcheck(url == "https://apps.apple.com/app/id6776462266?action=write-review",
           "RV5 写评价链接正确", "got \(url)")
}

print(rFails == 0 ? "评分提示全部通过 ✅" : "❌ 评分提示 \(rFails) 个失败")
