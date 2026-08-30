//
//  MCROracleTests.swift
//  国标算番的官方对照回归集。
//
//  期望值来自 **北大 Botzone 国标麻将比赛官方算番器**（PyMahjongGB，
//  逐字 vendor 了 ChineseOfficialMahjongHelper 的 mahjong-algorithm），
//  不是我们自己推的。生成方式见 Tests/data/README.md。
//
//  这 313 条从 12000 副随机合法和牌里按「番种覆盖」挑出来，覆盖 59 个番种。
//  改动算番逻辑后这里挂了，先假定是**我们错了**——除非能拿出规则原文推翻官方算番器。
//

func mcrOracleCases() -> [(hand: String, melds: [Meld], win: String, seat: Int, prev: Int, points: Int, fans: [String])] {
    let path = FileManager.default.currentDirectoryPath + "/Tests/data/mcr_oracle_cases.txt"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    var out: [(String, [Meld], String, Int, Int, Int, [String])] = []
    for line in text.split(separator: "\n") {
        let p = line.split(separator: "|", omittingEmptySubsequences: false)
        guard p.count == 7 else { continue }
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
                    Int(p[5])!, p[6].split(separator: ",").map(String.init)))
    }
    return out
}

print("— 国标官方对照回归集 —")
do {
    let cases = mcrOracleCases()
    mcheck(cases.count >= 300, "ORC0 用例载入", "只读到 \(cases.count) 条")
    var scoreFails: [String] = []
    var fanFails: [String] = []
    for c in cases {
        var ctx = MCRContext(selfDrawn: false, winningTile: mt(c.win).first!.mcrIndex)
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
