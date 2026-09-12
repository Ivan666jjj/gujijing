import AppKit

// MARK: - 应用委托

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let tabs = NSTabViewController()
        tabs.tabStyle = .segmentedControlOnTop

        let guji = NSTabViewItem(viewController: GujiViewController())
        guji.label = "古籍阅读"
        tabs.addTabViewItem(guji)

        let rhyme = NSTabViewItem(viewController: RhymeViewController())
        rhyme.label = "韵典"
        tabs.addTabViewItem(rhyme)

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered,
                           defer: false)
        win.title = "古籍镜"
        win.contentViewController = tabs
        win.minSize = NSSize(width: 900, height: 600)
        win.center()
        win.makeKeyAndOrderFront(nil)
        mainWindow = win
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于古籍镜",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏古籍镜", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出古籍镜", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(withTitle: "查找", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "f")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }
}

// MARK: - 与字源镜联动

enum Sibling {
    /// 拉起字源镜查这个字的字形演变
    static func openInZiyuanJing(_ ch: String) {
        guard !ch.isEmpty else { return }
        guard let app = appURL else {
            NSSound.beep()
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.arguments = [ch]
        NSWorkspace.shared.openApplication(at: app, configuration: cfg) { _, _ in }
    }

    static var appURL: URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.ziyuanjing.app") {
            return url
        }
        let candidates = [
            "/Applications/字源镜.app",
            NSHomeDirectory() + "/Desktop/字源镜.app",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }
}

// MARK: - 可双击查字的正文视图

final class GlyphTextView: NSTextView {
    /// 双击某个字时回调
    var onPickCharacter: ((String) -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard event.clickCount == 2 else { return }
        let sel = selectedRange()
        guard sel.length > 0, let range = Range(sel, in: string) else { return }
        let picked = String(string[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard picked.count == 1 else { return }
        onPickCharacter?(picked)
    }
}

// MARK: - 通用小工具

func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
               color: NSColor = .labelColor) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = color
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

func makeButton(_ title: String, target: AnyObject, action: Selector) -> NSButton {
    let b = NSButton(title: title, target: target, action: action)
    b.bezelStyle = .rounded
    b.font = .systemFont(ofSize: 12)
    return b
}

/// 把 NSTextView 正确塞进 NSScrollView：纵向滚动、横向跟着容器宽度换行。
/// 少了这几行，文本容器的宽度会一直停在默认的小值，整篇正文被挤成一列几个字，
/// 看起来像竖排。
func configureReading(_ scroll: NSScrollView, _ text: NSTextView) {
    text.minSize = NSSize(width: 0, height: 0)
    text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                          height: CGFloat.greatestFiniteMagnitude)
    text.isVerticallyResizable = true
    text.isHorizontallyResizable = false
    text.autoresizingMask = [.width]
    text.textContainer?.widthTracksTextView = true
    text.textContainer?.containerSize = NSSize(width: 0,
                                               height: CGFloat.greatestFiniteMagnitude)
    scroll.documentView = text
}

// MARK: - 古籍阅读

final class GujiViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    private enum Level {
        case sections([BookSection])
        case books([BookEntry], section: BookSection)
        case chapters([ChapterEntry], section: BookSection, book: BookEntry)
    }

    private var level: Level?
    private var items: [Any] = []

    private let crumbLabel = makeLabel("", size: 12, color: .secondaryLabelColor)
    private let statusLabel = makeLabel("", size: 11, color: .tertiaryLabelColor)
    private let backButton = NSButton()
    private let simplifySwitch = NSButton(checkboxWithTitle: "繁→简", target: nil, action: nil)

    private let tableView = NSTableView()
    private let listScroll = NSScrollView()
    private let textView = GlyphTextView()
    private let textScroll = NSScrollView()
    private let spinner = NSProgressIndicator()

    private let translateButton = NSButton()
    private let translationView = NSTextView()
    private let translationScroll = NSScrollView()

    private var currentChapter: ChapterContent?
    private var simplified = false

    override func loadView() {
        // 别设 translatesAutoresizingMaskIntoConstraints = false ——
        // 这是 contentViewController 的根视图，尺寸由 AppKit 管；关掉 autoresizing
        // 又没有外部约束兜底，宽度会被算错。
        // 最小尺寸这两行也不能少：没有它，窗口能被拖到 500px 上下，
        // 左侧目录占掉一大半，右侧正文只剩几个字宽。
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1120, height: 740))
        root.widthAnchor.constraint(greaterThanOrEqualToConstant: 900).isActive = true
        root.heightAnchor.constraint(greaterThanOrEqualToConstant: 600).isActive = true
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        textView.string = """
        ← 从左边挑一部、再挑一本书，正文会显示在这里。

        小技巧：双击正文里的任意一个字，会用「字源镜」打开它的字形演变。
        """
        Task { await loadSections() }
        // 后台先把本地语料读进内存，免得第一次点「译」时卡一下
        DispatchQueue.global(qos: .utility).async { LocalCorpus.preload() }
    }

    // MARK: UI

    private func buildUI() {
        backButton.title = "← 返回"
        backButton.bezelStyle = .rounded
        backButton.font = .systemFont(ofSize: 12)
        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.isEnabled = false
        backButton.translatesAutoresizingMaskIntoConstraints = false

        simplifySwitch.target = self
        simplifySwitch.action = #selector(toggleSimplify)
        simplifySwitch.font = .systemFont(ofSize: 12)
        simplifySwitch.translatesAutoresizingMaskIntoConstraints = false

        translateButton.title = "译"
        translateButton.bezelStyle = .rounded
        translateButton.font = .systemFont(ofSize: 12)
        translateButton.target = self
        translateButton.action = #selector(translateSelection)
        translateButton.toolTip = "选中正文里的一段：先查本地语料库（离线、免费），没收录才走 DeepSeek"
        translateButton.translatesAutoresizingMaskIntoConstraints = false

        let help = makeLabel("双击正文里的任意一个字 → 用字源镜看它的字形演变", size: 11, color: .tertiaryLabelColor)

        let header = NSStackView(views: [backButton, crumbLabel, NSView(),
                                        translateButton, simplifySwitch, statusLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10
        header.translatesAutoresizingMaskIntoConstraints = false

        // 左侧列表
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.title = "目录"
        column.width = 260
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 26
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(listActivated)

        listScroll.documentView = tableView
        listScroll.hasVerticalScroller = true
        listScroll.borderType = .noBorder
        listScroll.translatesAutoresizingMaskIntoConstraints = false

        // 右侧正文
        textView.isEditable = false
        textView.isRichText = true
        textView.font = .systemFont(ofSize: 17)
        textView.textContainerInset = NSSize(width: 22, height: 20)
        textView.onPickCharacter = { ch in
            Sibling.openInZiyuanJing(ch)
        }
        configureReading(textScroll, textView)
        textScroll.hasVerticalScroller = true
        textScroll.borderType = .noBorder
        textScroll.translatesAutoresizingMaskIntoConstraints = false

        translationView.isEditable = false
        translationView.font = .systemFont(ofSize: 14)
        translationView.textContainerInset = NSSize(width: 16, height: 12)
        translationView.string = "选中正文里的一段，点上面的「译」，白话译文会显示在这里。"
        translationView.textColor = .secondaryLabelColor
        configureReading(translationScroll, translationView)
        translationScroll.hasVerticalScroller = true
        translationScroll.borderType = .noBorder
        translationScroll.translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(translationScroll)
        view.addSubview(header)
        view.addSubview(help)
        view.addSubview(listScroll)
        view.addSubview(textScroll)
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            help.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            help.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            listScroll.topAnchor.constraint(equalTo: help.bottomAnchor, constant: 10),
            listScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            listScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            listScroll.widthAnchor.constraint(equalToConstant: 260),

            textScroll.topAnchor.constraint(equalTo: listScroll.topAnchor),
            textScroll.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor, constant: 14),
            textScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textScroll.bottomAnchor.constraint(equalTo: translationScroll.topAnchor, constant: -10),

            translationScroll.leadingAnchor.constraint(equalTo: textScroll.leadingAnchor),
            translationScroll.trailingAnchor.constraint(equalTo: textScroll.trailingAnchor),
            translationScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            translationScroll.heightAnchor.constraint(equalToConstant: 168),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: 数据加载

    @MainActor
    private func loadSections() async {
        setBusy(true, "正在读取四部…")
        do {
            let html = try await Guji.get("/")
            let sections = Guji.parseSections(html)
            guard !sections.isEmpty else { throw GujiError.decode }
            level = .sections(sections)
            items = sections
            crumbLabel.stringValue = "四部"
            backButton.isEnabled = false
            tableView.reloadData()
            setBusy(false, "共 \(sections.count) 部")
            // 顺手展开第一部、第一本书，免得刚打开时右边一片空白
            if let first = sections.first {
                await openSection(first)
                if case .books(let list, let section) = level, let book = list.first {
                    await openBook(book, in: section)
                }
            }
        } catch {
            setBusy(false, "")
            showText("# 读取失败\n\n\(error.localizedDescription)")
        }
    }

    @MainActor
    private func openSection(_ section: BookSection) async {
        setBusy(true, "正在读取《\(section.name)》书目…")
        do {
            let html = try await Guji.get(section.path)
            let books = Guji.parseBooks(html, section: String(section.path.dropFirst().dropLast()))
            level = .books(books, section: section)
            items = books
            crumbLabel.stringValue = section.name
            backButton.isEnabled = true
            tableView.reloadData()
            setBusy(false, "\(books.count) 种")
        } catch {
            setBusy(false, "")
            showText("# 读取失败\n\n\(error.localizedDescription)")
        }
    }

    @MainActor
    private func openBook(_ book: BookEntry, in section: BookSection) async {
        setBusy(true, "正在读取《\(book.title)》目录…")
        do {
            let html = try await Guji.get(book.path)
            let chapters = Guji.parseChapters(html, bookPath: book.path)
            level = .chapters(chapters, section: section, book: book)
            items = chapters
            crumbLabel.stringValue = "\(section.name) › \(book.title)"
            backButton.isEnabled = true
            tableView.reloadData()
            setBusy(false, "\(chapters.count) 章")
            if let first = chapters.first { await openChapter(first, keepList: true) }
        } catch {
            setBusy(false, "")
            showText("# 读取失败\n\n\(error.localizedDescription)")
        }
    }

    @MainActor
    private func openChapter(_ chapter: ChapterEntry, keepList: Bool = true) async {
        setBusy(true, "正在读取《\(chapter.title)》…")
        do {
            let html = try await Guji.get(chapter.path)
            var content = Guji.parseChapter(html)
            if content.title.isEmpty { content.title = chapter.title }
            currentChapter = content
            if !keepList, case .chapters(let list, _, _) = level {
                items = list
                tableView.reloadData()
            }
            renderChapter()
            setBusy(false, "双击字可查字形 · \(content.blocks.count) 段")
        } catch {
            setBusy(false, "")
            showText("# 读取失败\n\n\(error.localizedDescription)")
        }
    }

    @MainActor
    private func renderChapter() {
        guard let content = currentChapter else { return }
        let body = NSMutableAttributedString()
        let titleFont = NSFont.systemFont(ofSize: 24, weight: .semibold)
        let headFont = NSFont.systemFont(ofSize: 18, weight: .medium)
        let paraFont = NSFont.systemFont(ofSize: 17)
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = 7
        paraStyle.paragraphSpacing = 12
        paraStyle.firstLineHeadIndent = 34

        // 注疏：整段左缩进、行距收紧，跟经文在视觉上分层
        let noteStyle = NSMutableParagraphStyle()
        noteStyle.lineSpacing = 4
        noteStyle.paragraphSpacing = 9
        noteStyle.firstLineHeadIndent = 20
        noteStyle.headIndent = 20

        func fix(_ s: String) -> String { simplified ? toSimplified(s) : s }

        body.append(NSAttributedString(string: fix(content.title) + "\n", attributes: [
            .font: titleFont, .foregroundColor: NSColor.labelColor,
        ]))
        body.append(NSAttributedString(string: fix(content.breadcrumb.joined(separator: " › ")) + "\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        for block in content.blocks {
            switch block {
            case .heading(let t):
                body.append(NSAttributedString(string: fix(t) + "\n", attributes: [
                    .font: headFont, .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paraStyle,
                ]))
            case .paragraph(let t):
                body.append(NSAttributedString(string: fix(t) + "\n", attributes: [
                    .font: paraFont, .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paraStyle,
                ]))
            case .note(let t):
                body.append(NSAttributedString(string: fix(t) + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 13.5),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: noteStyle,
                ]))
            }
        }
        if content.blocks.isEmpty {
            body.append(NSAttributedString(string: "（这一页没有正文内容）\n", attributes: [
                .font: NSFont.systemFont(ofSize: 15),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]))
        }
        if let next = content.nextPath {
            body.append(NSAttributedString(string: "\n", attributes: [:]))
            body.append(NSAttributedString(string: "下一章：\(fix(content.nextTitle.isEmpty ? next : content.nextTitle))",
                                           attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.linkColor,
                .link: next,
            ]))
        }
        textView.textStorage?.setAttributedString(body)
        textView.scrollToBeginningOfDocument(nil)
    }

    private func showText(_ markdownish: String) {
        textView.string = markdownish
    }

    private func setBusy(_ busy: Bool, _ message: String) {
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        if !message.isEmpty { statusLabel.stringValue = message }
    }

    // MARK: 动作

    @objc private func goBack() {
        guard let level else { return }
        switch level {
        case .sections:
            break
        case .books(_, let section):
            Task { await loadSections(); _ = section }
        case .chapters(_, let section, _):
            Task { await openSection(section) }
        }
    }

    @objc private func translateSelection() {
        let range = textView.selectedRange()
        guard range.length > 0, let r = Range(range, in: textView.string) else {
            translationView.string = "先在正文里选中要翻译的段落，再点「译」。"
            translationView.textColor = .systemOrange
            return
        }
        let source = String(textView.string[r])
        let charCount = source.count
        // 当前在读的书名（汉典那边的写法），用来挑对应的本地语料
        let book: String? = {
            if case .chapters(_, _, let b) = level { return b.title }
            return nil
        }()
        translationView.textColor = .secondaryLabelColor
        translationView.string = "正在查本地语料（\(charCount) 字）…"
        translateButton.isEnabled = false

        Task { @MainActor in
            defer { translateButton.isEnabled = true }
            do {
                let zh = try await Translator.translate(source, book: book)
                translationView.string = "【原文】\(source)\n\n【译文】\(zh.text)\n\n—— \(zh.source)"
                translationView.textColor = .labelColor
                translationView.scrollToBeginningOfDocument(nil)
            } catch {
                translationView.string = "翻译失败：\(error.localizedDescription)"
                translationView.textColor = .systemOrange
            }
        }
    }

    @objc private func toggleSimplify() {
        simplified = simplifySwitch.state == .on
        renderChapter()
    }

    @objc private func listActivated() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < items.count, let level else { return }
        switch level {
        case .sections(let list):
            Task { await openSection(list[row]) }
        case .books(let list, let section):
            Task { await openBook(list[row], in: section) }
        case .chapters(let list, _, _):
            Task { await openChapter(list[row]) }
        }
    }

    // MARK: 表格

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
            let c = NSTableCellView()
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.font = .systemFont(ofSize: 14)
            c.addSubview(tf)
            c.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 6),
                tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -6),
                tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            c.identifier = id
            return c
        }()
        let title: String
        switch items[row] {
        case let b as BookEntry:        title = b.title
        case let c as ChapterEntry:     title = c.title
        case let s as BookSection:      title = s.name
        default:                        title = ""
        }
        cell.textField?.stringValue = title
        return cell
    }
}
