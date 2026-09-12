import AppKit

// MARK: - 韵典

final class RhymeViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    private let searchField = NSSearchField()
    private let noteLabel = makeLabel("", size: 11, color: .tertiaryLabelColor)
    private let hintLabel = makeLabel("输入一个字查它属于哪些韵部；或输入韵部名（如「一东」「入声」）反查同韵字",
                                      size: 11, color: .tertiaryLabelColor)

    private let tableView = NSTableView()
    private let listScroll = NSScrollView()
    private let charsView = GlyphTextView()
    private let charsScroll = NSScrollView()

    private var groups: [RhymeGroup] = []

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

        let lib = RhymeLibrary.shared
        if !lib.loadError.isEmpty {
            noteLabel.stringValue = lib.loadError
            noteLabel.textColor = .systemOrange
        } else {
            noteLabel.stringValue = "已载入 \(lib.groups.count) 个韵部"
        }
    }

    private func buildUI() {
        searchField.placeholderString = "一个字，或韵部名"
        searchField.font = .systemFont(ofSize: 14)
        searchField.target = self
        searchField.action = #selector(doSearch)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(equalToConstant: 220).isActive = true

        let button = makeButton("查询", target: self, action: #selector(doSearch))
        button.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView(views: [searchField, button, noteLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10
        header.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rhyme"))
        column.title = "韵部"
        column.width = 260
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 24
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false

        listScroll.documentView = tableView
        listScroll.hasVerticalScroller = true
        listScroll.borderType = .noBorder
        listScroll.translatesAutoresizingMaskIntoConstraints = false

        charsView.isEditable = false
        charsView.font = .systemFont(ofSize: 16)
        charsView.textContainerInset = NSSize(width: 18, height: 16)
        charsView.onPickCharacter = { ch in
            Sibling.openInZiyuanJing(ch)
        }
        configureReading(charsScroll, charsView)
        charsScroll.hasVerticalScroller = true
        charsScroll.borderType = .noBorder
        charsScroll.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(header)
        view.addSubview(hintLabel)
        view.addSubview(listScroll)
        view.addSubview(charsScroll)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),

            hintLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            listScroll.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 10),
            listScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            listScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            listScroll.widthAnchor.constraint(equalToConstant: 260),

            charsScroll.topAnchor.constraint(equalTo: listScroll.topAnchor),
            charsScroll.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor, constant: 14),
            charsScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            charsScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
        ])
    }

    // MARK: 查询

    @objc private func doSearch() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let lib = RhymeLibrary.shared
        guard lib.loadError.isEmpty else { return }

        if query.count == 1, let ch = query.first {
            let hits = lib.lookup(ch)
            groups = hits.compactMap { hit in
                lib.groups.first { $0.book == hit.book && $0.name == hit.name }
            }
            if hits.isEmpty {
                noteLabel.stringValue = "「\(query)」在收录的韵书里没有找到"
            } else {
                let tones = Set(hits.map { $0.tone }).sorted().joined(separator: "/")
                noteLabel.stringValue = "「\(query)」落在 \(hits.count) 个韵部（\(tones)声）"
            }
        } else {
            groups = lib.groupsMatching(query)
            noteLabel.stringValue = "匹配到 \(groups.count) 个韵部"
        }

        tableView.reloadData()
        if groups.isEmpty {
            charsView.string = ""
        } else {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            showChars(groups[0])
        }
    }

    private func showChars(_ group: RhymeGroup?) {
        guard let group else { charsView.string = ""; return }
        let unique = Set(group.chars).count
        charsView.string = """
        【\(group.book) · \(group.name)】（\(group.tone)声，共 \(unique) 字）

        \(group.chars)
        """
    }

    // MARK: 表格

    func numberOfRows(in tableView: NSTableView) -> Int { groups.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("rhymeCell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
            let c = NSTableCellView()
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.font = .systemFont(ofSize: 13)
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
        let g = groups[row]
        cell.textField?.stringValue = "\(g.book) · \(g.name)"
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < groups.count else { return }
        showChars(groups[row])
    }
}
