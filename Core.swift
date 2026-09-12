import Foundation

// MARK: - 通用

let kUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

/// 去掉 HTML 标签和常见实体，留下纯文本
func plainText(_ raw: String) -> String {
    var t = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    let entities = [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                    ("&quot;", "\""), ("&#39;", "'"), ("&mdash;", "—"), ("&middot;", "·")]
    for (k, v) in entities { t = t.replacingOccurrences(of: k, with: v) }
    return t.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 繁 → 简
func toSimplified(_ text: String) -> String {
    let s = NSMutableString(string: text)
    CFStringTransform(s, nil, "Traditional-Simplified" as CFString, false)
    return s as String
}

func matches(_ pattern: String, in text: String) -> [[String]] {
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
    let ns = text as NSString
    return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
        (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }
}

// MARK: - 古籍模型

struct BookSection: Hashable {
    let path: String     // "/jingbu/"
    let name: String     // "經部"
}

struct BookEntry: Hashable {
    let path: String     // "/jingbu/46/"
    let title: String    // "周易"
}

struct ChapterEntry: Hashable {
    let path: String     // "/jingbu/46/833.html"
    let title: String    // "彖"
}

enum TextBlock {
    case heading(String)
    case paragraph(String)
    case note(String)       // 注疏：小字、灰色、左缩进
}

struct ChapterContent {
    var title = ""
    var breadcrumb: [String] = []
    var blocks: [TextBlock] = []
    var nextPath: String?
    var nextTitle = ""
}

enum GujiError: LocalizedError {
    case badURL
    case http(Int)
    case decode

    var errorDescription: String? {
        switch self {
        case .badURL:      return "地址构造失败"
        case .http(let c): return "站点返回 HTTP \(c)"
        case .decode:      return "页面解码失败"
        }
    }
}

// MARK: - 汉典古籍

enum Guji {

    static let base = "https://gj.zdic.net"
    /// 四部的顺序按经史子集，不要按字母排
    static let sectionOrder: [(key: String, fallback: String)] = [
        ("jingbu", "經部"), ("shibu", "史部"), ("zibu", "子部"), ("jibu", "集部"),
    ]

    static func get(_ path: String) async throws -> String {
        guard let url = URL(string: path.hasPrefix("http") ? path : base + path) else {
            throw GujiError.badURL
        }
        var req = URLRequest(url: url)
        req.setValue(kUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(base + "/", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 30
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw GujiError.http(http.statusCode)
        }
        guard let html = String(data: data, encoding: .utf8) else { throw GujiError.decode }
        return html
    }

    /// 首页 → 四部（名字从页面读，读不到就用兜底名）
    static func parseSections(_ html: String) -> [BookSection] {
        sectionOrder.map { key, fallback in
            let found = matches("<a href=\"/\(key)/\"[^>]*title=\"([^\"]*)\"", in: html)
            return BookSection(path: "/\(key)/",
                               name: found.first.map { plainText($0[1]) }.flatMap { $0.isEmpty ? nil : $0 } ?? fallback)
        }
    }

    /// 部 → 书目
    static func parseBooks(_ html: String, section: String) -> [BookEntry] {
        var seen = Set<String>()
        var out: [BookEntry] = []
        for m in matches("<a href=\"(/\(section)/[0-9]+/)\"[^>]*title=\"([^\"]*)\"", in: html) {
            let path = m[1], title = plainText(m[2])
            guard !path.isEmpty, !title.isEmpty, !seen.contains(path) else { continue }
            seen.insert(path)
            out.append(BookEntry(path: path, title: title))
        }
        return out
    }

    /// 书 → 章节
    static func parseChapters(_ html: String, bookPath: String) -> [ChapterEntry] {
        var seen = Set<String>()
        var out: [ChapterEntry] = []
        for m in matches("<a href=\"(\(bookPath)[0-9]+\\.html)\"[^>]*title=\"([^\"]*)\"", in: html) {
            let path = m[1], title = plainText(m[2])
            guard !path.isEmpty, !title.isEmpty, !seen.contains(path) else { continue }
            seen.insert(path)
            out.append(ChapterEntry(path: path, title: title))
        }
        return out
    }

    /// 判断一段属于经文、小节标题还是注疏。
    /// 注疏类书（十三经注疏）把经文和疏文混在纯文本里，疏文以这些标记开头。
    static func classify(_ raw: String) -> TextBlock {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 注疏先判 —— 疏文里也有以 ○ 开头的（○正义曰）
        let noteMarks = ["[疏]", "［疏］", "【疏】", "[注]", "［注］", "【注】",
                         "[正义曰]", "○正义曰", "[释]", "[音义]", "[笺]", "[校]"]
        for mark in noteMarks where t.hasPrefix(mark) { return .note(t) }
        if t.hasPrefix("○") || t.hasPrefix("〔") || t.hasPrefix("【") { return .heading(t) }
        return .paragraph(t)
    }

    /// 正文页 → 标题 / 面包屑 / 正文块 / 下一章
    static func parseChapter(_ html: String) -> ChapterContent {
        var content = ChapterContent()

        // class 里可能还有别的类名或尾随空格（页面上 `class="article-page "` 这种写法到处都是）
        if let m = matches("<h1 class=\"title-article[^\"]*\">([^<]*)</h1>", in: html).first {
            content.title = plainText(m[1])
        }
        if let m = matches("<div class=\"article-section[^\"]*\">(.*?)</div>", in: html).first {
            content.breadcrumb = matches("title=\"([^\"]*)\"", in: m[1]).map { plainText($0[1]) }
        }

        // 正文：从 div.article-body 开始，按顺序读 <h3>/<p>，遇到别的元素就停。
        // ⚠️ 这里必须认 `class="article-body`，不能用裸的 "article-body" ——
        // 页面的 <style> 里也有 .article-body 的样式定义，遇上样式表排在正文前面的
        // 页面（如《旧唐书》）会先撞上它，结果一段正文都读不出来。
        // ⚠️ 全程用 NSString/NSRange。NSRange 是 UTF-16 偏移，而 String.distance 数的是
        // 字符（grapheme）个数 —— 页面里只要出现一个扩展区汉字（代理对），两者就会错开，
        // 后面的正则在错误的位置上找 <p>，结果一段正文都读不出来（《旧唐书》就栽在这）。
        let ns = html as NSString
        let bodyAnchor = ns.range(of: "class=\"article-body")
        let anchor = bodyAnchor.location == NSNotFound ? ns.range(of: "article-body") : bodyAnchor
        if anchor.location != NSNotFound {
            let afterAnchor = NSRange(location: anchor.location + anchor.length,
                                      length: ns.length - anchor.location - anchor.length)
            let gt = ns.range(of: ">", options: [], range: afterAnchor)
            if gt.location != NSNotFound {
                let bodyStart = gt.location + gt.length
                // ⚠️ 标题层级各篇不统一：周易用 <h3>、旧唐书·代宗用 <p> 起头、
                // 德宗上却用 <h2>。只写 h3 的话碰上 h2 就断档，整篇正文都读不出来。
                let blockRe = try? NSRegularExpression(pattern: "<(h[1-6]|p)[^>]*>(.*?)</\\1>",
                                                       options: [.dotMatchesLineSeparators])
                var cursor = bodyStart
                while let re = blockRe, cursor < ns.length {
                    let remaining = NSRange(location: cursor, length: ns.length - cursor)
                    guard let m = re.firstMatch(in: html, range: remaining) else { break }
                    // 中间只允许空白，否则说明正文已经结束
                    let gap = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                    if !gap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
                    let tag = ns.substring(with: m.range(at: 1))
                    let text = plainText(ns.substring(with: m.range(at: 2)))
                    if !text.isEmpty {
                        content.blocks.append(tag == "p" ? classify(text) : .heading(text))
                    }
                    cursor = m.range.location + m.range.length
                }

                // 有些篇目（如《廿二史劄记·小引》）的正文是裸文本，一个块标签都没有，
                // 只靠 <br><br> 分段。这时退化成按 <br> 切段，总比给用户一片空白强。
                if content.blocks.isEmpty {
                    let close = ns.range(of: "</div>", options: [],
                                         range: NSRange(location: bodyStart,
                                                        length: ns.length - bodyStart))
                    let end = close.location == NSNotFound ? ns.length : close.location
                    let raw = ns.substring(with: NSRange(location: bodyStart, length: end - bodyStart))
                        .replacingOccurrences(of: "<br/>", with: "<br>")
                        .replacingOccurrences(of: "<br />", with: "<br>")
                    for chunk in raw.components(separatedBy: "<br>") {
                        let text = plainText(chunk)
                        if !text.isEmpty { content.blocks.append(classify(text)) }
                    }
                }
            }
        }

        // 下一章
        if let m = matches("<a href=\"([^\"]+\\.html)\"[^>]*>下一章</a>", in: html).first {
            content.nextPath = m[1]
        } else if let m = matches("<a href=\"([^\"]+\\.html)\"[^>]*title=\"([^\"]*)\"[^>]*>下一章", in: html).first {
            content.nextPath = m[1]
        }
        if let m = matches("<a href=\"([^\"]+\\.html)\"[^>]*title=\"([^\"]*)\"[^>]*>\\s*下一章", in: html).first {
            content.nextPath = m[1]
            content.nextTitle = plainText(m[2])
        }
        // 标题里带着章节名时补一下下一章名
        if content.nextPath == nil,
           let m = matches("href=\"([^\"]+\\.html)\"[^>]*title=\"下一章\"", in: html).first {
            content.nextPath = m[1]
        }

        return content
    }
}

// MARK: - 韵典（离线韵书）

struct RhymeGroup {
    let book: String        // 平水韵
    let name: String        // 上平一东
    let tone: String        // 平 / 仄
    let chars: String       // 该韵部所有字
}

struct RhymeHit {
    let book: String
    let name: String
    let tone: String
}

final class RhymeLibrary {
    static let shared = RhymeLibrary()

    private(set) var groups: [RhymeGroup] = []
    private(set) var loadError = ""
    private var index: [Character: [Int]] = [:]

    /// 平水韵 106 韵的韵目名，顺序必须与数据一致
    private static let pingNames: [String] = [
        "上平一东", "上平二冬", "上平三江", "上平四支", "上平五微",
        "上平六鱼", "上平七虞", "上平八齐", "上平九佳", "上平十灰",
        "上平十一真", "上平十二文", "上平十三元", "上平十四寒", "上平十五删",
        "下平一先", "下平二萧", "下平三肴", "下平四豪", "下平五歌",
        "下平六麻", "下平七阳", "下平八庚", "下平九青", "下平十蒸",
        "下平十一尤", "下平十二侵", "下平十三覃", "下平十四盐", "下平十五咸",
    ]
    private static let zeNames: [String] = [
        "上声一董", "上声二肿", "上声三讲", "上声四纸", "上声五尾",
        "上声六语", "上声七麌", "上声八荠", "上声九蟹", "上声十贿",
        "上声十一轸", "上声十二吻", "上声十三阮", "上声十四旱", "上声十五潸",
        "上声十六铣", "上声十七篠", "上声十八巧", "上声十九皓", "上声二十哿",
        "上声廿一马", "上声廿二养", "上声廿三梗", "上声廿四迥", "上声廿五有",
        "上声廿六寝", "上声廿七感", "上声廿八俭", "上声廿九豏",
        "去声一送", "去声二宋", "去声三绛", "去声四寘", "去声五未",
        "去声六御", "去声七遇", "去声八霁", "去声九泰", "去声十卦",
        "去声十一队", "去声十二震", "去声十三问", "去声十四愿", "去声十五翰",
        "去声十六谏", "去声十七霰", "去声十八啸", "去声十九效", "去声二十号",
        "去声廿一箇", "去声廿二禡", "去声廿三漾", "去声廿四敬", "去声廿五径",
        "去声廿六宥", "去声廿七沁", "去声廿八勘", "去声廿九艳", "去声三十陷",
        "入声一屋", "入声二沃", "入声三觉", "入声四质", "入声五物",
        "入声六月", "入声七曷", "入声八黠", "入声九屑", "入声十药",
        "入声十一陌", "入声十二锡", "入声十三职", "入声十四缉", "入声十五合",
        "入声十六叶", "入声十七洽",
    ]
    /// 中华新韵 14 韵部（平、仄两半的序号一一对应）
    private static let xinYunNames: [String] = [
        "一麻", "二波", "三皆", "四开", "五微", "六豪", "七尤",
        "八寒", "九文", "十唐", "十一庚", "十二齐", "十三支", "十四姑",
    ]

    private init() { load() }

    private func load() {
        guard let url = Bundle.main.url(forResource: "rhymebooks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            loadError = "韵书数据没找到（rhymebooks.json 应在 App 的 Resources 里）"
            return
        }
        build(book: "平水韵", halves: root["平水韵"] as? [[String]], names: (Self.pingNames, Self.zeNames))
        build(book: "中华新韵", halves: root["中华新韵"] as? [[String]],
              names: (Self.xinYunNames, Self.xinYunNames))
        for (i, g) in groups.enumerated() {
            for ch in Set(g.chars) { index[ch, default: []].append(i) }
        }
    }

    private func build(book: String, halves: [[String]]?, names: ([String]?, [String]?)?) {
        guard let halves, halves.count >= 2 else { return }
        let sides: [(String, [String], [String]?)] = [("平", halves[0], names?.0), ("仄", halves[1], names?.1)]
        for (tone, list, nameList) in sides {
            for (i, chars) in list.enumerated() {
                let label: String
                if let nameList, i < nameList.count {
                    label = nameList[i]
                } else {
                    label = "\(tone)声第 \(i + 1) 部"
                }
                groups.append(RhymeGroup(book: book, name: label, tone: tone, chars: chars))
            }
        }
    }

    /// 查一个字落在哪些韵部。
    /// 韵书数据是简体，所以繁体字要先转一下 —— 古籍正文全是繁体，
    /// 不转的话「馬」「國」这类常用字一律查不到。
    func lookup(_ ch: Character) -> [RhymeHit] {
        var hitIndexes = index[ch] ?? []
        if hitIndexes.isEmpty, let simplified = toSimplified(String(ch)).first, simplified != ch {
            hitIndexes = index[simplified] ?? []
        }
        return hitIndexes.map { RhymeHit(book: groups[$0].book, name: groups[$0].name, tone: groups[$0].tone) }
    }

    /// 按韵部名反查（支持模糊），返回韵部列表
    func groupsMatching(_ keyword: String) -> [RhymeGroup] {
        let k = keyword.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return [] }
        return groups.filter { $0.name.contains(k) || $0.chars.contains(k) }
    }
}
