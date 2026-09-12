import Foundation

// MARK: - 本地语料库（离线 · 免费）

/// NiuTrans/Classical-Modern（MIT 协议）的句级《古文 ↔ 现代文》对照语料：
/// 97 本书、97 万句对。按书拆成 corpus/<书名>.json 随 App 一起打包，
/// 读到哪本书就只把哪本读进内存（最大的《资治通鉴》也只有 23 MB），
/// 另外用 _common.json（一批小型经典合并）兜底 —— 汉典书名和语料书名
/// 对不上时，常见的句子照样查得到。
///
/// 全程离线、零成本：dmg 发给别人，对方没有 API key 也能直接用。
enum LocalCorpus {

    struct Lookup {
        var text: String?   // 查到的译文（可能是部分命中）；nil 表示一句都没查到
        var matched: Int    // 命中的句数
        var total: Int      // 一共切出几句
        var approx: Bool    // 有没有句子是靠「包含匹配」猜出来的，界面要提示核对
    }

    private static let queue = DispatchQueue(label: "com.gujijing.localcorpus")

    private static var bookKeys: [String: Int] = [:]
    private static var bookTexts: [String] = []
    private static var loadedBook: String?
    private static var commonKeys: [String: Int] = [:]
    private static var commonTexts: [String] = []
    private static var commonLoaded = false

    /// 当前已经装进内存的条目数（状态栏用）
    static var entryCount: Int { queue.sync { bookTexts.count + commonTexts.count } }
    static var currentBook: String? { queue.sync { loadedBook } }

    /// 一批老异体字 → 通行字。繁简转换管不到这些（「愼」是「慎」的异体，
    /// 不是繁体字），汉典正文里却常见，不归并的话整句就对不上。
    private static let variants: [UInt32: UInt32] = [
        0x613C: 0x614E,   // 愼 → 慎
        0x55A9: 0x55BB,   // 喩 → 喻
        0x6537: 0x8003,   // 攷 → 考
        0x654E: 0x6559,   // 敎 → 教
        0x7955: 0x79D8,   // 祕 → 秘
        0x6C4E: 0x6CDB,   // 汎 → 泛
        0x7240: 0x5E8A,   // 牀 → 床
        0x76C3: 0x676F,   // 盃 → 杯
        0x6B4E: 0x53F9,   // 歎 → 叹
        0x95C7: 0x6697,   // 闇 → 暗
        0x7FA3: 0x7FA4,   // 羣 → 群
        0x7571: 0x7559,   // 畱 → 留
        0x5DFB: 0x5377,   // 巻 → 卷
        0x51A9: 0x5199,   // 冩 → 写
        0x65E3: 0x65E2,   // 旣 → 既
        0x96A3: 0x90BB,   // 隣 → 邻
        0x69E9: 0x6982,   // 槩 → 概
        0x69EA: 0x6982,   // 槪 → 概
        0x7567: 0x7565,   // 畧 → 略
        0x5FA7: 0x904D,   // 徧 → 遍
        0x6159: 0x60ED,   // 慙 → 惭
        0x617E: 0x6B32,   // 慾 → 欲
        0x64E7: 0x4E3E,   // 擧 → 举
        0x6A11: 0x6881,   // 樑 → 梁
        0x7156: 0x6696,   // 煖 → 暖
        0x7255: 0x7A97,   // 牕 → 窗
        0x7609: 0x6108,   // 瘉 → 愈
        0x7690: 0x768B,   // 皐 → 皋
        0x7760: 0x7737,   // 睠 → 眷
        0x7881: 0x68CB,   // 碁 → 棋
        0x7ADD: 0x5E76,   // 竝 → 并
        0x7B87: 0x4E2A,   // 箇 → 个
        0x7DB5: 0x5F69,   // 綵 → 彩
        0x7FEB: 0x73A9,   // 翫 → 玩
        0x8278: 0x8349,   // 艸 → 草
        0x8345: 0x7B54,   // 荅 → 答
        0x83F4: 0x5EB5,   // 菴 → 庵
        0x8675: 0x86C7,   // 虵 → 蛇
        0x8768: 0x8671,   // 蝨 → 虱
        0x885E: 0x536B,   // 衞 → 卫
        0x8988: 0x6838,   // 覈 → 核
        0x8A60: 0x548F,   // 詠 → 咏
        0x8B90: 0x96E0,   // 讐 → 雠
        0x8CDB: 0x8D5E,   // 賛 → 赞
        0x8CB2: 0x8D44,   // 貲 → 资
        0x8D82: 0x8D81,   // 趂 → 趁
        0x8EB0: 0x4F53,   // 躰 → 体
        0x8FA4: 0x8F9E,   // 辤 → 辞
        0x8FFA: 0x4E43,   // 迺 → 乃
        0x90A8: 0x6751,   // 邨 → 村
        0x9245: 0x5DE8,   // 鉅 → 巨
        0x965E: 0x5347,   // 陞 → 升
        0x9B2C: 0x6597,   // 鬬 → 斗
        0x9927: 0x5582,   // 餧 → 喂
    ]

    /// 只留汉字/字母/数字，抹掉空白和标点，并把老异体字归并成通行字。
    /// 汉典正文与语料的标点和用字习惯不一样，不这样归一化就对不上。
    static func norm(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for u in s.unicodeScalars {
            let v = variants[u.value] ?? u.value
            switch v {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F,
                 0x30...0x39, 0x41...0x5A, 0x61...0x7A:
                if let scalar = UnicodeScalar(v) { out.unicodeScalars.append(scalar) }
            default:
                break
            }
        }
        return out
    }

    /// 把一段古文按句末标点切开（保留标点）。
    /// 切完剩下的「」『』这类只剩标点的碎片必须丢掉 —— 汉典正文常写成
    /// 「子曰：「學而時習之…」」，收尾的「」会被切出一段空壳，留着就会
    /// 让「命中 N/N+1 句」永远差一句，整段白白回退到联网。
    static func sentences(of text: String) -> [String] {
        var out: [String] = []
        var cur = ""

        func push() {
            let s = cur.trimmingCharacters(in: .whitespacesAndNewlines)
            cur = ""
            guard !s.isEmpty, !norm(s).isEmpty else { return }
            out.append(s)
        }

        for ch in text {
            cur.append(ch)
            if "。！？".contains(ch) { push() }
        }
        push()
        return out
    }

    // MARK: 载入

    private static func corpusDir() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("corpus", isDirectory: true)
    }

    private static func loadFile(_ name: String) -> ([String: Int], [String])? {
        guard let dir = corpusDir() else { return nil }
        let url = dir.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let keys = obj["i"] as? [String: Int],
              let texts = obj["t"] as? [String] else { return nil }
        return (keys, texts)
    }

    private static func loadCommon() {
        guard !commonLoaded else { return }
        commonLoaded = true
        if let (k, t) = loadFile("_common.json") {
            commonKeys = k
            commonTexts = t
        }
    }

    /// 汉典的书名可能是繁体、也可能带「注疏」「集解」这类后缀，
    /// 逐个候选去碰语料文件名。
    private static func fileCandidates(for book: String?) -> [String] {
        guard let book, !book.isEmpty else { return [] }
        let cleaned = toSimplified(book).filter { $0.isLetter || $0.isNumber }
        guard !cleaned.isEmpty else { return [] }
        var out = [cleaned]
        for suffix in ["注疏", "集解", "正义", "章句", "集注", "新注", "校注", "译注", "全译"] {
            if cleaned.hasSuffix(suffix), cleaned.count > suffix.count {
                out.append(String(cleaned.dropLast(suffix.count)))
            }
        }
        return out
    }

    private static func prepare(_ book: String?) {
        for file in fileCandidates(for: book) where file != loadedBook {
            if let (k, t) = loadFile(file + ".json") {
                bookKeys = k
                bookTexts = t
                loadedBook = file
                return
            }
        }
    }

    /// 让调用方能在后台线程先把兜底语料读进内存，免得第一次点「译」时卡一下
    static func preload() { queue.sync { loadCommon() } }

    /// 切到正在读的这本书（没有对应语料就什么都不做，后面还有 _common 兜底）
    static func prepare(book: String?) { queue.sync { prepare(book) } }

    // MARK: 查询

    /// 汉典会在正文里夹校勘注，如「一作『也已矣』」「一無『已』字」
    /// 「一說該章的句讀應作『…』」。这些不是正文，留着既会把译文带偏，
    /// 也会让整句对不上语料。
    private static let notePattern = try? NSRegularExpression(
        pattern: "一[作無无說说][^「『]{0,30}[「『][^」』]{0,120}[」』]字?")

    private static func stripNotes(_ s: String) -> String {
        guard let re = notePattern else { return s }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
    }

    static func lookup(_ text: String) -> Lookup {
        queue.sync {
            // 汉典正文可能是繁体（语料是简体），还夹着校勘注文
            let base = stripNotes(toSimplified(text))
            let parts = sentences(of: base)
            guard !parts.isEmpty else {
                return Lookup(text: nil, matched: 0, total: 0, approx: false)
            }

            // 先在当前这本书里查
            var best = Lookup(text: nil, matched: 0, total: parts.count, approx: false)
            if !bookKeys.isEmpty {
                best = search(parts, keys: bookKeys, texts: bookTexts)
                if best.matched == best.total, best.text != nil { return best }
            }

            // 没查全的话，再用小书兜底库比一比，谁命中多就用谁
            loadCommon()
            let fallback = search(parts, keys: commonKeys, texts: commonTexts)
            if fallback.matched > best.matched { return fallback }
            return best
        }
    }

    private static func search(_ parts: [String], keys: [String: Int], texts: [String]) -> Lookup {
        guard !keys.isEmpty else {
            return Lookup(text: nil, matched: 0, total: parts.count, approx: false)
        }
        var picked: [String] = []
        var matched = 0
        var approx = false

        for s in parts {
            let k = norm(s)
            guard k.count >= 2 else { continue }
            var hit: Int?
            if let i = keys[k], i < texts.count {
                hit = i                              // 整句精确命中
            } else if let i = fuzzy(k, keys: keys), i < texts.count {
                hit = i                              // 靠包含关系猜的，得让用户核对
                approx = true
            }
            guard let i = hit else { continue }
            matched += 1
            let t = texts[i]
            // 同一段里的多句共用一条译文时别重复贴
            if picked.last != t { picked.append(t) }
        }

        // 哪怕只命中一部分也先用本地译文顶着（界面会标明几句没查到），
        // 总比整段什么都没有强。
        if matched > 0, !picked.isEmpty {
            return Lookup(text: picked.joined(separator: " "),
                          matched: matched, total: parts.count, approx: approx)
        }
        return Lookup(text: nil, matched: 0, total: parts.count, approx: approx)
    }

    /// 子串兜底：语料里的句子常带「子曰：」这类引语前缀，整句对不上时
    /// 退一步找包含关系里长度最接近的一条。只有唯一候选才采用，避免误配。
    /// 命中的结果只是「近似」，调用方要在界面上提示核对。
    private static func fuzzy(_ key: String, keys: [String: Int]) -> Int? {
        guard key.count >= 4 else { return nil }
        var bestDiff = Int.max
        var bestIdx: Int?
        var ties = 0
        for (k, i) in keys where k.count >= 4 {
            guard k.contains(key) || key.contains(k) else { continue }
            let diff = abs(k.count - key.count)
            if diff < bestDiff {
                bestDiff = diff
                bestIdx = i
                ties = 1
            } else if diff == bestDiff {
                ties += 1
            }
        }
        return ties == 1 ? bestIdx : nil
    }
}

// MARK: - 白话翻译（本地优先，DeepSeek 兜底）

/// 两级翻译：
/// 一级 —— 本地语料库，离线、免费、毫秒级，dmg 发给别人也一样能用；
/// 二级 —— 本地没收录才走 DeepSeek（没 key 就明说「未收录」）。
enum Translator {

    struct Result {
        let text: String
        let source: String      // 译文来源，显示在界面底部
    }

    private static let endpoint = "https://api.deepseek.com/chat/completions"
    private static let model = "deepseek-chat"

    private static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("古籍镜", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var cacheURL: URL { cacheDir.appendingPathComponent("translations.plist") }

    private static var cache: [String: String] = {
        guard let data = try? Data(contentsOf: cacheURL),
              let dict = try? PropertyListDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }()

    private static func saveCache() {
        guard let data = try? PropertyListEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL)
    }

    /// 从 ~/.reasonix/.env 读 DEEPSEEK_API_KEY
    static var apiKey: String? {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".reasonix/.env")
        guard let content = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
            return nil
        }
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            guard key == "DEEPSEEK_API_KEY" else { continue }
            var value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    static var keyStatus: String {
        apiKey == nil ? "没读到底 ~/.reasonix/.env 里的 DEEPSEEK_API_KEY" : "就绪"
    }

    /// 本地语料库的状态（状态栏用）
    static var corpusStatus: String {
        if let book = LocalCorpus.currentBook { return "本地语料《\(book)》" }
        return LocalCorpus.entryCount > 0 ? "本地语料（兜底库）" : "本地语料未加载"
    }

    enum TranslateError: LocalizedError {
        case noKey
        case empty
        case notInCorpus(Int, Int)
        case http(Int, String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .noKey:
                return "没找到 DEEPSEEK_API_KEY（应在 ~/.reasonix/.env 里）"
            case .empty:
                return "先选中要翻译的段落"
            case .notInCorpus(let matched, let total):
                if matched > 0 {
                    return "本地语料库这 \(total) 句里只有 \(matched) 句收录了，其余没收录；"
                        + "也没读到 DEEPSEEK_API_KEY，没法联网补译。"
                }
                return "本地语料库未收录这段（共 \(total) 句）；"
                    + "也没读到 DEEPSEEK_API_KEY，没法联网翻译。"
            case .http(let c, let m):
                return "接口返回 HTTP \(c)：\(m.prefix(120))"
            case .badResponse:
                return "接口返回的内容读不出来"
            }
        }
    }

    /// book 传当前正在读的书名（汉典那边的写法），用来挑对应的本地语料
    static func translate(_ text: String, book: String? = nil) async throws -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslateError.empty }

        // 一级：本地语料库（离线、免费）。放后台查，免得读大语料时卡住界面。
        let hit = await withCheckedContinuation { (cont: CheckedContinuation<LocalCorpus.Lookup, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                LocalCorpus.prepare(book: book)
                cont.resume(returning: LocalCorpus.lookup(trimmed))
            }
        }
        if let local = hit.text, !local.isEmpty {
            var label = "本地语料库 · 离线"
            if hit.total > 1 {
                label += hit.matched == hit.total
                    ? "（\(hit.matched) 句）"
                    : "（只收录了 \(hit.total) 句中的 \(hit.matched) 句）"
            }
            if hit.approx { label += " · 近似匹配，请核对" }
            return Result(text: local, source: label)
        }

        // 二级：本机缓存过的 DeepSeek 结果
        if let cached = cache[trimmed] { return Result(text: cached, source: "本机缓存 · DeepSeek") }

        // 三级：DeepSeek（没 key 就明说未收录）
        guard let key = apiKey else {
            throw TranslateError.notInCorpus(hit.matched, hit.total)
        }

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system",
                 "content": "你是古籍翻译助手。把用户给的古文译成通顺的现代汉语。"
                    + "只输出译文本身，不要解释、不要加引号、不要复述原文。"
                    + "遇到生僻的官名、地名、器物名，可在译文里用括号简要说明。"],
                ["role": "user", "content": trimmed],
            ],
        ]

        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 90
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw TranslateError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslateError.badResponse
        }
        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        cache[trimmed] = result
        saveCache()
        return Result(text: result, source: "DeepSeek 在线翻译")
    }

    /// 缓存里已有多少条
    static var cachedCount: Int { cache.count }
}
