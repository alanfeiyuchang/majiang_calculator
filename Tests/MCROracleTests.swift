//
//  MCROracleTests.swift
//  国标算番的官方对照回归集。
//
//  期望值来自 **北大 Botzone 国标麻将比赛官方算番器**（PyMahjongGB，
//  逐字 vendor 了 ChineseOfficialMahjongHelper 的 mahjong-algorithm），
//  不是我们自己推的。生成方式见 Tests/data/README.md。
//
//  这 431 条同时取自两批语料，覆盖 69 个番种、含 60 条自摸：
//    · 普通牌（含吃/碰/明杠/暗杠、随机门风圈风）
//    · **稀有型加权**（七对/十三幺/九莲宝灯/连七对/全不靠/七星不靠/组合龙/
//      清幺九/混幺九/绿一色/字牌大牌）——纯随机牌几乎生成不出这些，
//      而引擎最容易在这里出错。第一版语料就是漏了它们，把「100% 一致」测成了假象。
//  改动算番逻辑后这里挂了，先假定是**我们错了**——除非能拿出规则原文推翻官方算番器。
//

func mcrOracleCases() -> [(hand: String, melds: [Meld], win: String, seat: Int, prev: Int,
                           selfDrawn: Bool, points: Int, fans: [String])] {
    let path = FileManager.default.currentDirectoryPath + "/Tests/data/mcr_oracle_cases.txt"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    var out: [(String, [Meld], String, Int, Int, Bool, Int, [String])] = []
    for line in text.split(separator: "\n") {
        let p = line.split(separator: "|", omittingEmptySubsequences: false)
        guard p.count == 8 else { continue }
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
        out.append((String(p[0]), melds, String(p[2]), Int(p[3])! - 1, Int(p[4])! - 1,
                    p[5] == "1", Int(p[6])!, p[7].split(separator: ",").map(String.init)))
    }
    return out
}

print("— 国标官方对照回归集 —")
do {
    let cases = mcrOracleCases()
    mcheck(cases.count >= 400, "ORC0 用例载入", "只读到 \(cases.count) 条")
    var scoreFails: [String] = []
    var fanFails: [String] = []
    for c in cases {
        var ctx = MCRContext(selfDrawn: c.selfDrawn, winningTile: mt(c.win).first!.mcrIndex)
        ctx.seatWind = c.seat; ctx.prevalentWind = c.prev
        let s = scoreMCRHand(concealed: mfreq(c.hand), melds: c.melds, context: ctx)
        if s.scoringPoints != c.points {
            scoreFails.append("\(c.hand) 期望\(c.points) 实得\(s.scoringPoints)")
        }
        // 番种集合也要一致（官方的独听・X 对应我们的边张/坎张/单钓将）
        let norm: (String) -> String = {
            $0 == "独听・嵌张" ? "坎张" : $0 == "独听・单钓" ? "单钓将"
                                     : $0 == "独听・边张" ? "边张" : $0
        }
        if Set(c.fans.map(norm)) != Set(s.items.map(\.name)) {
            fanFails.append("\(c.hand) 期望[\(c.fans.map(norm).sorted().joined(separator: ","))] "
                            + "实得[\(s.items.map(\.name).sorted().joined(separator: ","))]")
        }
    }
    mcheck(scoreFails.isEmpty, "ORC1 总分与官方算番器一致（\(cases.count) 条）",
           scoreFails.prefix(3).joined(separator: " ｜ ") + (scoreFails.count > 3 ? " …共\(scoreFails.count)条" : ""))
    mcheck(fanFails.isEmpty, "ORC2 番种集合与官方算番器一致",
           fanFails.prefix(3).joined(separator: " ｜ ") + (fanFails.count > 3 ? " …共\(fanFails.count)条" : ""))
}
