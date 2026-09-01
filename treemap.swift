// main.swift — Disk treemap. AppKit only, no dependencies.
// Build: swiftc -O main.swift -o treemap
// Run:   ./treemap [folder]        (no arg → folder picker)
// Hover = path/size · click = zoom into that subfolder · Esc = zoom out
// Right-click = menu (Reveal in Finder / Move to Trash / Zoom Out) · ⌘O open · ⌘R rescan · ⌘Q quit
import AppKit

final class Node {
    let name: String
    unowned var parent: Node?
    var size: Int64 = 0
    var count = 0
    var children: [Node]?   // nil = file
    var tag: UInt32 = 0     // extension hash → color
    init(_ name: String, _ parent: Node?) { self.name = name; self.parent = parent }
    var isDir: Bool { children != nil }
    var path: String { parent.map { ($0.path == "/" ? "/" : $0.path + "/") + name } ?? name }
    var url: URL { URL(fileURLWithPath: path) }
}

enum Scan {
    static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileSizeKey, .volumeIdentifierKey]
    static let keyList = Array(keys)

    static func fnv(_ s: String) -> UInt32 {
        var h: UInt32 = 2166136261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return h
    }

    // Allocated (on-disk) sizes. Symlinks not followed. Stays on the root's volume (like du -x).
    static func run(_ root: URL, progress: @escaping (Int) -> Void) -> Node {
        let top = Node(root.path, nil)
        top.children = []
        let vol = (try? root.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier
        var seen = 0
        func walk(_ dir: Node, _ url: URL) {
            guard let entries = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keyList, options: []) else { return }
            var kids: [Node] = []
            kids.reserveCapacity(entries.count)
            for u in entries {
                guard let v = try? u.resourceValues(forKeys: keys) else { continue }
                let n = Node(u.lastPathComponent, dir)
                if v.isSymbolicLink != true, v.isDirectory == true {
                    if let a = vol, let b = v.volumeIdentifier, !a.isEqual(b) { continue }
                    n.children = []
                    walk(n, u)
                } else {
                    n.size = Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
                    n.count = 1
                    n.tag = fnv(u.pathExtension.lowercased())
                    seen += 1
                    if seen & 4095 == 0 { progress(seen) }
                }
                dir.size += n.size
                dir.count += n.count
                kids.append(n)
            }
            kids.sort { $0.size > $1.size }
            dir.children = kids
        }
        walk(top, root)
        return top
    }
}

final class TreemapView: NSView {
    var root: Node? { didSet { relayout(); needsDisplay = true } }
    var onHover: ((Node?) -> Void)?
    var onZoom: ((Node) -> Void)?

    private var items: [(CGRect, Node)] = []
    private var laidOut = CGSize.zero
    private var hovered: Int?
    private var menuNode: Node?
    private var colors: [UInt32: CGColor] = [:]
    private static let noExt = Scan.fnv("")
    private static let dirColor = CGColor(gray: 0.35, alpha: 1)

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        for t in trackingAreas { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    // Squarified treemap (Bruls et al.). Only leaves are recorded; tiny dirs become gray leaves.
    private func relayout() {
        items.removeAll(keepingCapacity: true)
        hovered = nil
        laidOut = bounds.size
        if let r = root { place(r, bounds) }
    }

    private func place(_ node: Node, _ rect: CGRect) {
        if rect.width < 0.5 || rect.height < 0.5 { return }
        guard let kids = node.children, node.size > 0, rect.width >= 3, rect.height >= 3 else { items.append((rect, node)); return }
        let scale = Double(rect.width * rect.height) / Double(node.size)   // px² per byte
        var rem = rect
        var row: [Node] = [], area = 0.0, big = 0.0, small = 0.0, i = 0
        while i < kids.count, rem.width > 0.5, rem.height > 0.5 {
            let a = Double(kids[i].size) * scale
            if a <= 0 { break }
            let w = Double(min(rem.width, rem.height))
            if row.isEmpty || worst(area + a, max(big, a), min(small, a), w) <= worst(area, big, small, w) {
                big = row.isEmpty ? a : max(big, a)
                small = row.isEmpty ? a : min(small, a)
                row.append(kids[i]); area += a; i += 1
            } else {
                flush(row, area, scale, &rem)
                row.removeAll(keepingCapacity: true); area = 0
            }
        }
        if !row.isEmpty { flush(row, area, scale, &rem) }
    }

    private func worst(_ s: Double, _ mx: Double, _ mn: Double, _ w: Double) -> Double {
        max(w * w * mx / (s * s), s * s / (w * w * mn))
    }

    private func flush(_ row: [Node], _ area: Double, _ scale: Double, _ rem: inout CGRect) {
        if rem.width >= rem.height {
            let w = CGFloat(area / Double(rem.height))
            var y = rem.minY
            for k in row {
                let h = CGFloat(Double(k.size) * scale) / w
                place(k, CGRect(x: rem.minX, y: y, width: w, height: h))
                y += h
            }
            rem.origin.x += w; rem.size.width -= w
        } else {
            let h = CGFloat(area / Double(rem.width))
            var x = rem.minX
            for k in row {
                let w = CGFloat(Double(k.size) * scale) / h
                place(k, CGRect(x: x, y: rem.minY, width: w, height: h))
                x += w
            }
            rem.origin.y += h; rem.size.height -= h
        }
    }

    override func draw(_ dirty: NSRect) {
        if laidOut != bounds.size { relayout() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fill(dirty)
        ctx.setLineWidth(1)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.5))
        for (r, n) in items where r.intersects(dirty) {
            ctx.setFillColor(n.isDir ? Self.dirColor : color(n.tag))
            ctx.fill(r)
            if r.width > 4, r.height > 4 { ctx.stroke(r.insetBy(dx: 0.5, dy: 0.5)) }
        }
        if let h = hovered, h < items.count {
            ctx.setLineWidth(2)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
            ctx.stroke(items[h].0.insetBy(dx: 1, dy: 1))
        }
    }

    private func color(_ tag: UInt32) -> CGColor {
        if let c = colors[tag] { return c }
        let c = NSColor(hue: CGFloat(tag % 360) / 360, saturation: tag == Self.noExt ? 0.1 : 0.6, brightness: 0.85, alpha: 1).cgColor
        colors[tag] = c
        return c
    }

    private func hit(_ e: NSEvent) -> Int? {
        let p = convert(e.locationInWindow, from: nil)
        return items.firstIndex { $0.0.contains(p) }
    }

    override func mouseMoved(with e: NSEvent) { hover(hit(e)) }
    override func mouseExited(with e: NSEvent) { hover(nil) }

    private func hover(_ i: Int?) {
        guard i != hovered else { return }
        for j in [hovered, i] { if let j = j, j < items.count { setNeedsDisplay(items[j].0.insetBy(dx: -2, dy: -2)) } }
        hovered = i
        onHover?(i.map { items[$0].1 })
    }

    override func mouseDown(with e: NSEvent) {
        guard let i = hit(e), let r = root else { return }
        let n = items[i].1
        if e.modifierFlags.contains(.command) { NSWorkspace.shared.activateFileViewerSelecting([n.url]); return }
        var t = n
        while let p = t.parent, p !== r { t = p }   // child of current root containing the click
        if t !== r, t.isDir { zoom(t) }
    }
    override func menu(for e: NSEvent) -> NSMenu? {
        let i = hit(e)
        menuNode = i.map { items[$0].1 }
        hover(i)
        let m = NSMenu()
        m.autoenablesItems = false
        func add(_ title: String, _ sel: Selector, _ enabled: Bool) {
            let it = m.addItem(withTitle: title, action: sel, keyEquivalent: "")
            it.target = self
            it.isEnabled = enabled
        }
        add("Reveal in Finder", #selector(revealClicked), menuNode != nil)
        add("Move to Trash", #selector(trashClicked), menuNode?.parent != nil)
        m.addItem(.separator())
        add("Zoom Out", #selector(zoomOut), root?.parent != nil)
        return m
    }

    @objc private func revealClicked() {
        if let n = menuNode { NSWorkspace.shared.activateFileViewerSelecting([n.url]) }
    }

    @objc private func trashClicked() {
        guard let n = menuNode, let p = n.parent else { return }
        do { try FileManager.default.trashItem(at: n.url, resultingItemURL: nil) }
        catch { NSAlert(error: error).runModal(); return }
        p.children?.removeAll { $0 === n }
        var a: Node? = p                                    // fix sizes/counts up the chain, keep siblings sorted
        while let x = a { x.size -= n.size; x.count -= n.count; x.parent?.children?.sort { $0.size > $1.size }; a = x.parent }
        menuNode = nil
        relayout()
        needsDisplay = true
        if let r = root { onZoom?(r) }
    }

    @objc private func zoomOut() { if let p = root?.parent { zoom(p) } }

    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 { zoomOut() } else { super.keyDown(with: e) }
    }
    private func zoom(_ n: Node) { root = n; onZoom?(n) }
}

final class App: NSObject, NSApplicationDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 750),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    let view = TreemapView()
    let status = NSTextField(labelWithString: " ")
    let bytes = ByteCountFormatter()
    var tree: Node?
    var scanURL: URL?
    var gen = 0

    func applicationDidFinishLaunching(_ note: Notification) {
        menus()
        let content = NSView()
        for v in [view, status] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }
        status.lineBreakMode = .byTruncatingMiddle
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: content.topAnchor),
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -4),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -4),
        ])
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.title = "Treemap"
        window.center()
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(view)
        view.onHover = { [unowned self] n in
            self.status.stringValue = n.map { "\($0.path) — \(self.bytes.string(fromByteCount: $0.size))" + ($0.isDir ? " — \(self.num($0.count)) files" : "") } ?? " "
        }
        view.onZoom = { [unowned self] in self.title($0) }
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.count > 1 { scan(URL(fileURLWithPath: CommandLine.arguments[1])) } else { openFolder(nil) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    func menus() {
        let bar = NSMenu(), appMenu = NSMenu(), fileMenu = NSMenu(title: "File")
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        fileMenu.addItem(withTitle: "Open…", action: #selector(openFolder(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Rescan", action: #selector(rescan(_:)), keyEquivalent: "r")
        for m in [appMenu, fileMenu] { let i = NSMenuItem(); i.submenu = m; bar.addItem(i) }
        NSApp.mainMenu = bar
    }

    @objc func openFolder(_ sender: Any?) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.prompt = "Scan"
        if p.runModal() == .OK, let u = p.url { scan(u) } else if scanURL == nil { NSApp.terminate(nil) }
    }

    @objc func rescan(_ sender: Any?) { if let u = scanURL { scan(u) } }

    func scan(_ url: URL) {
        gen += 1
        let g = gen
        scanURL = url
        view.root = nil
        tree = nil
        window.title = url.path
        status.stringValue = "Scanning…"
        DispatchQueue.global(qos: .userInitiated).async {
            let t = Scan.run(url) { n in
                DispatchQueue.main.async { if self.gen == g { self.status.stringValue = "Scanning… \(self.num(n)) files" } }
            }
            DispatchQueue.main.async {
                guard self.gen == g else { return }
                self.tree = t
                self.view.root = t
                self.title(t)
                self.status.stringValue = " "
            }
        }
    }

    func title(_ n: Node) { window.title = "\(n.path) — \(bytes.string(fromByteCount: n.size)) — \(num(n.count)) files" }
    func num(_ n: Int) -> String { NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal) }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
