//
//  MCROracleTests.swift
//  国标算番的官方对照回归集。
//
//  期望值来自 **北大 Botzone 国标麻将比赛官方算番器**（PyMahjongGB，
//  逐字 vendor 了 ChineseOfficialMahjongHelper 的 mahjong-algorithm），
//  不是我们自己推的。生成方式见 Tests/data/README.md。
//
//  语料覆盖全部 82 个番种，并且**每个场景标志都带上**（自摸、和绝张勾选、
//  杠上开花/抢杠和、妙手回春/海底捞月、花牌），来源：
//    · 普通牌（含吃/碰/明杠/暗杠、随机门风圈风）
//    · **稀有型加权**（七对/十三幺/九莲宝灯/连七对/全不靠/七星不靠/组合龙/
//      清幺九/混幺九/绿一色/字牌大牌）——纯随机牌几乎生成不出这些
//    · 手工构造（一色双龙会/一色四同顺/一色四步高/三色双龙会/全大/全带五/
//      全求人/四杠 等随机牌打不出来的番种）
//  前两版语料都栽在覆盖率上：第一版 0 条自摸 0 条特殊型，第二版 13 个番种零覆盖、
//  场景标志一个没开，于是「100% 一致」两次都是假象。改语料前先看覆盖率。
//  改动算番逻辑后这里挂了，先假定是**我们错了**——除非能拿出规则原文推翻官方算番器。
//

struct MCROracleCase {
    var hand: String, melds: [Meld], win: String, seat: Int, prev: Int
    var selfDrawn: Bool, points: Int, fans: [String]
    // 场景标志：官方把杠上开花 / 抢杠和合成同一个标志，自摸时读作前者
    var lastTileOfKind = false, kongFlag = false, wallLast = false, flowers = 0
}

func mcrOracleCases() -> [MCROracleCase] {
    let path = FileManager.default.currentDirectoryPath + "/Tests/data/mcr_oracle_cases.txt"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    var out: [MCROracleCase] = []
    for line in text.split(separator: "\n") {
        let p = line.split(separator: "|", omittingEmptySubsequences: false)
        guard p.count == 13 else { continue }
        var melds: [Meld] = []
        if p[1] != "-" {
            for part in p[1].split(separator: ";") {
                let kv = part.split(separator: ",")
                guard kv.count == 2, let card = mt(String(kv[1])).first else { continue }
                let kind: Meld.Kind = kv[0] == "chow" ? .chow : kv[0] == "pung" ? .pong
                                     : kv[0] == "ekong" ? .exposedKong : .concealedKong
                melds.append(Meld(kind: kind, card: card))
            }
        }
        out.append(MCROracleCase(
            hand: String(p[0]), melds: melds, win: String(p[2]),
            seat: Int(p[3])! - 1, prev: Int(p[4])! - 1, selfDrawn: p[5] == "1",
            points: Int(p[6])!, fans: p[7].split(separator: ",").map(String.init),
            lastTileOfKind: p[8] == "1", kongFlag: p[9] == "1",
            wallLast: p[10] == "1", flowers: Int(p[12]) ?? 0))
    }
    return out
}

print("— 国标官方对照回归集 —")
do {
    let cases = mcrOracleCases()
    mcheck(cases.count >= 1700, "ORC0 用例载入", "只读到 \(cases.count) 条")
    var scoreFails: [String] = []
    var fanFails: [String] = []
    for c in cases {
        var ctx = MCRContext(selfDrawn: c.selfDrawn, winningTile: mt(c.win).first!.mcrIndex)
        ctx.seatWind = c.seat; ctx.prevalentWind = c.prev
        ctx.lastTileOfKind = c.lastTileOfKind
        ctx.flowers = c.flowers
        if c.selfDrawn { ctx.kongBloom = c.kongFlag; ctx.lastTileDraw = c.wallLast }
        else { ctx.robbingKong = c.kongFlag; ctx.lastDiscard = c.wallLast }
        let s = scoreMCRHand(concealed: mfreq(c.hand), melds: c.melds, context: ctx)
        // 官方给的是**含花总分**，对应我们的 totalPoints（scoringPoints 不含花，
        // 那是用来判起和线的）
        if s.totalPoints != c.points {
            scoreFails.append("\(c.hand) 期望\(c.points) 实得\(s.totalPoints)")
        }
        // 番种要连**个数**一起对上（官方的独听・X 对应我们的边张/坎张/单钓将，
        // 「幺九刻*2」这种写法表示同一番种计了 2 次）
        let norm: (String) -> String = {
            $0 == "独听・嵌张" ? "坎张" : $0 == "独听・单钓" ? "单钓将"
                                     : $0 == "独听・边张" ? "边张" : $0
        }
        var want: [String: Int] = [:]
        for f in c.fans {
            let parts = f.split(separator: "*")
            want[norm(String(parts[0]))] = parts.count > 1 ? Int(parts[1])! : 1
        }
        var got: [String: Int] = [:]
        for i in s.items { got[i.name] = i.count }
        if want != got {
            func show(_ d: [String: Int]) -> String {
                d.keys.sorted().map { d[$0]! > 1 ? "\($0)*\(d[$0]!)" : $0 }.joined(separator: ",")
            }
            fanFails.append("\(c.hand) 期望[\(show(want))] 实得[\(show(got))]")
        }
    }
    mcheck(scoreFails.isEmpty, "ORC1 总分与官方算番器一致（\(cases.count) 条）",
           scoreFails.prefix(3).joined(separator: " ｜ ") + (scoreFails.count > 3 ? " …共\(scoreFails.count)条" : ""))
    mcheck(fanFails.isEmpty, "ORC2 番种集合与官方算番器一致",
           fanFails.prefix(3).joined(separator: " ｜ ") + (fanFails.count > 3 ? " …共\(fanFails.count)条" : ""))
}
