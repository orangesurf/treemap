// treemap — Disk usage map for macOS.
// Copyright (C) 2026  orangesurf (orange.surf)
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// This program is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
// General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
// main.swift — Disk treemap. AppKit only, no dependencies.
// 
// Build: swiftc -O treemap.swift main.swift -o treemap
// Run:   ./treemap [folder]        (no arg → folder picker)
// Hover = path/size · click a folder to zoom in · Esc = zoom out
// Click breadcrumbs = jump to that folder (rescans if above the opened folder) · ⌘-click = reveal in Finder
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

    // Drop this node from its parent and subtract size/count up the ancestor chain.
    func detach() {
        guard let p = parent else { return }
        p.children?.removeAll { $0 === self }
        var a: Node? = p
        while let x = a {
            x.size -= size
            x.count -= count
            x.parent?.children?.sort { $0.size > $1.size }
            a = x.parent
        }
    }
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
            autoreleasepool {                              // drain Foundation temporaries per directory
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
                dir.tag = kids.first(where: { $0.size > 0 })?.tag ?? 0   // color from largest descendant type
                dir.children = kids
            }
        }
        walk(top, root)
        return top
    }
}

enum Layout {
    static let maxShare = 0.75          // largest child cannot eat the whole view
    static let minSide: CGFloat = 28    // clickable / labelable floor

    // Squarified treemap (Bruls et al.). One level of children; folders stay folders.
    static func place(_ node: Node, _ rect: CGRect) -> [(CGRect, Node)] {
        var items: [(CGRect, Node)] = []
        place(node, rect, into: &items)
        return items
    }

    static func place(_ node: Node, _ rect: CGRect, into items: inout [(CGRect, Node)]) {
        if rect.width < 0.5 || rect.height < 0.5 { return }
        guard let raw = node.children, node.size > 0, rect.width >= 3, rect.height >= 3 else { items.append((rect, node)); return }
        let kids = raw.filter { $0.size > 0 }
        guard !kids.isEmpty else { items.append((rect, node)); return }
        let areas = tileAreas(kids, in: rect)
        var rem = rect
        var row: [(Node, Double)] = [], area = 0.0, big = 0.0, small = 0.0, i = 0
        while i < kids.count, rem.width > 0.5, rem.height > 0.5 {
            let a = areas[i]
            if a <= 0 { break }
            let w = Double(min(rem.width, rem.height))
            if row.isEmpty || worst(area + a, max(big, a), min(small, a), w) <= worst(area, big, small, w) {
                big = row.isEmpty ? a : max(big, a)
                small = row.isEmpty ? a : min(small, a)
                row.append((kids[i], a)); area += a; i += 1
            } else {
                flush(row, area, &rem, into: &items)
                row.removeAll(keepingCapacity: true); area = 0
            }
        }
        if !row.isEmpty { flush(row, area, &rem, into: &items) }
    }

    // Pixel areas: cap the giant child and keep a clickable floor for the rest.
    static func tileAreas(_ kids: [Node], in rect: CGRect) -> [Double] {
        let area = Double(rect.width * rect.height)
        let n = kids.count
        let total = Double(kids.reduce(Int64(0)) { $0 + $1.size })
        var areas = kids.map { area * Double($0.size) / total }
        if n > 1, let i = areas.indices.max(by: { areas[$0] < areas[$1] }) {
            let cap = area * maxShare
            if areas[i] > cap {
                let extra = areas[i] - cap
                areas[i] = cap
                let others = areas.indices.filter { $0 != i }
                let otherSum = others.reduce(0.0) { $0 + areas[$1] }
                if otherSum > 0 {
                    for j in others { areas[j] += extra * areas[j] / otherSum }
                } else {
                    let add = extra / Double(others.count)
                    for j in others { areas[j] += add }
                }
            }
        }
        let minA = min(Double(minSide * minSide), area / Double(max(n, 1)) * 0.5)
        var need = 0.0
        for i in areas.indices where areas[i] < minA { need += minA - areas[i]; areas[i] = minA }
        let pool = areas.indices.filter { areas[$0] > minA }
        let avail = pool.reduce(0.0) { $0 + areas[$1] - minA }
        if need > 0, avail > 0 {
            let take = min(need, avail)
            for i in pool { areas[i] -= take * (areas[i] - minA) / avail }
        }
        return areas
    }

    static func worst(_ s: Double, _ mx: Double, _ mn: Double, _ w: Double) -> Double {
        max(w * w * mx / (s * s), s * s / (w * w * mn))
    }

    private static func flush(_ row: [(Node, Double)], _ area: Double, _ rem: inout CGRect, into items: inout [(CGRect, Node)]) {
        if rem.width >= rem.height {
            let w = CGFloat(area / Double(rem.height))
            var y = rem.minY
            for (k, a) in row {
                let h = CGFloat(a) / w
                tile(k, CGRect(x: rem.minX, y: y, width: w, height: h), into: &items)
                y += h
            }
            rem.origin.x += w; rem.size.width -= w
        } else {
            let h = CGFloat(area / Double(rem.width))
            var x = rem.minX
            for (k, a) in row {
                let w = CGFloat(a) / h
                tile(k, CGRect(x: x, y: rem.minY, width: w, height: h), into: &items)
                x += w
            }
            rem.origin.y += h; rem.size.height -= h
        }
    }

    private static func tile(_ node: Node, _ rect: CGRect, into items: inout [(CGRect, Node)]) {
        if rect.width < 0.5 || rect.height < 0.5 { return }
        items.append((rect, node))
    }
}

enum Breadcrumb {
    struct Item {
        let title: String
        let node: Node?
        let url: URL
    }

    static func items(for n: Node, volumeName: String) -> [Item] {
        var byPath: [String: Node] = [:]
        var x: Node? = n
        while let c = x {
            byPath[URL(fileURLWithPath: c.path).standardizedFileURL.path] = c
            x = c.parent
        }
        let url = URL(fileURLWithPath: n.path).standardizedFileURL
        var items = [Item(title: volumeName, node: byPath["/"], url: URL(fileURLWithPath: "/"))]
        var prefix = URL(fileURLWithPath: "/")
        for part in url.pathComponents where part != "/" {
            prefix = prefix.appendingPathComponent(part)
            let p = prefix.standardizedFileURL
            items.append(Item(title: part, node: byPath[p.path], url: p))
        }
        return items
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
    private let bytes = ByteCountFormatter()
    private static let noExt = Scan.fnv("")
    private static let namePara: NSParagraphStyle = {
        let p = NSMutableParagraphStyle(); p.alignment = .center; p.lineBreakMode = .byTruncatingMiddle; return p
    }()
    private static let darkHalo: NSShadow = {
        let s = NSShadow(); s.shadowColor = NSColor.black.withAlphaComponent(0.75); s.shadowBlurRadius = 2.5; s.shadowOffset = .zero; return s
    }()
    private static let lightHalo: NSShadow = {
        let s = NSShadow(); s.shadowColor = NSColor.white.withAlphaComponent(0.8); s.shadowBlurRadius = 2.5; s.shadowOffset = .zero; return s
    }()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        for t in trackingAreas { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    private func relayout() {
        items.removeAll(keepingCapacity: true)
        hovered = nil
        laidOut = bounds.size
        if let r = root { Layout.place(r, bounds, into: &items) }
    }

    override func draw(_ dirty: NSRect) {
        if laidOut != bounds.size { relayout() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fill(dirty)
        ctx.setLineWidth(1)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.5))
        for (r, n) in items where r.intersects(dirty) {
            ctx.setFillColor(color(n.tag))
            ctx.fill(r)
            if r.width > 4, r.height > 4 { ctx.stroke(r.insetBy(dx: 0.5, dy: 0.5)) }
            caption(n, r)
        }
        if let h = hovered, h < items.count {
            ctx.setLineWidth(2)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
            ctx.stroke(items[h].0.insetBy(dx: 1, dy: 1))
        }
    }

    // Name centered, size bottom-right. Skip either (or both) when the tile is too small.
    private func caption(_ n: Node, _ r: CGRect) {
        let pad: CGFloat = 4
        guard r.width >= 28, r.height >= 14, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let light = !isLightFill(n)
        let fg: NSColor = light ? .white : NSColor(white: 0.1, alpha: 1)
        let halo = light ? Self.darkHalo : Self.lightHalo
        let nameFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let sizeFont = NSFont.systemFont(ofSize: 9)
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: nameFont, .foregroundColor: fg, .paragraphStyle: Self.namePara, .shadow: halo
        ]
        let sizeAttrs: [NSAttributedString.Key: Any] = [
            .font: sizeFont, .foregroundColor: fg.withAlphaComponent(0.9), .shadow: halo
        ]
        let nameH = ceil(("Ag" as NSString).size(withAttributes: nameAttrs).height)
        let sizeStr = bytes.string(fromByteCount: n.size) as NSString
        let sizeSz = sizeStr.size(withAttributes: sizeAttrs)
        var showSize = sizeSz.width + pad * 2 <= r.width && sizeSz.height + pad * 2 <= r.height
        var nameArea = CGRect(x: r.minX + pad, y: r.minY + pad, width: r.width - pad * 2, height: r.height - pad * 2)
        let fullNameW = (n.name as NSString).size(withAttributes: nameAttrs).width
        // Truncate only when enough width remains to keep a useful fragment; short names can use a smaller tile.
        func nameFits(_ area: CGRect) -> Bool {
            area.height >= nameH && (fullNameW <= area.width || area.width >= 64)
        }
        if showSize {
            let reserved = sizeSz.height + pad
            var shrunk = nameArea
            shrunk.size.height -= reserved
            if nameFits(shrunk) { nameArea = shrunk } else if nameFits(nameArea) { showSize = false }
        }
        ctx.saveGState()
        ctx.clip(to: r.insetBy(dx: 1, dy: 1))
        if nameFits(nameArea) {
            (n.name as NSString).draw(in: CGRect(x: nameArea.minX, y: nameArea.midY - nameH / 2, width: nameArea.width, height: nameH), withAttributes: nameAttrs)
        }
        if showSize {
            sizeStr.draw(at: CGPoint(x: r.maxX - pad - sizeSz.width, y: r.maxY - pad - sizeSz.height), withAttributes: sizeAttrs)
        }
        ctx.restoreGState()
    }

    private func isLightFill(_ n: Node) -> Bool {
        guard let c = color(n.tag).converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)?.components, c.count >= 3 else { return true }
        return (0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]) > 0.55
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
        if n !== r, n.isDir { zoom(n) }
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
        guard let n = menuNode, n.parent != nil else { return }
        do { try FileManager.default.trashItem(at: n.url, resultingItemURL: nil) }
        catch { NSAlert(error: error).runModal(); return }
        n.detach()
        menuNode = nil
        relayout()
        needsDisplay = true
        if let r = root { onZoom?(r) }
    }

    @objc private func zoomOut() { if let p = root?.parent { zoom(p) } }

    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 { zoomOut() } else { super.keyDown(with: e) }
    }
    func zoomTo(_ n: Node) { zoom(n) }
    private func zoom(_ n: Node) { root = n; onZoom?(n) }
}

// Finder-style path bar. Click a parent to zoom back, or to rescan if it's above the opened folder.
final class CrumbsView: NSView {
    var onPick: ((Node?, URL) -> Void)?
    private let stack = NSStackView()
    private var items: [Breadcrumb.Item] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = CGColor(gray: 0.13, alpha: 1)
        appearance = NSAppearance(named: .darkAqua)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { false }

    func show(_ n: Node?) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        items.removeAll()
        guard let n else { return }
        let url = URL(fileURLWithPath: n.path).standardizedFileURL
        let vol = (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "Macintosh HD"
        items = Breadcrumb.items(for: n, volumeName: vol)
        for (i, item) in items.enumerated() {
            if i > 0 {
                let chev = NSTextField(labelWithString: "›")
                chev.font = .systemFont(ofSize: 11, weight: .semibold)
                chev.textColor = NSColor.white.withAlphaComponent(0.35)
                chev.isSelectable = false
                chev.setContentHuggingPriority(.required, for: .horizontal)
                stack.addArrangedSubview(chev)
            }
            let last = i == items.count - 1
            let btn = NSButton(title: item.title, target: self, action: #selector(pick(_:)))
            btn.tag = i
            btn.bezelStyle = .recessed
            btn.setButtonType(.momentaryLight)
            btn.controlSize = .small
            btn.focusRingType = .none
            btn.font = .systemFont(ofSize: 12, weight: last ? .semibold : .medium)
            btn.toolTip = item.url.path
            btn.setContentHuggingPriority(last ? .defaultHigh : .defaultLow, for: .horizontal)
            btn.setContentCompressionResistancePriority(last ? .required : .defaultLow, for: .horizontal)
            stack.addArrangedSubview(btn)
        }
    }

    @objc private func pick(_ sender: NSButton) {
        let i = sender.tag
        guard i >= 0, i < items.count else { return }
        let item = items[i]
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        } else {
            onPick?(item.node, item.url)
            return
        }
        if let w = window {
            for v in w.contentView?.subviews ?? [] where v is TreemapView { _ = w.makeFirstResponder(v); break }
        }
    }
}

final class App: NSObject, NSApplicationDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 750),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    let view = TreemapView()
    let crumbs = CrumbsView()
    let status = NSTextField(labelWithString: " ")
    let bytes = ByteCountFormatter()
    var tree: Node?
    var scanURL: URL?
    var gen = 0

    func applicationDidFinishLaunching(_ note: Notification) {
        menus()
        let content = NSView()
        for v in [view, status, crumbs] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }
        status.lineBreakMode = .byTruncatingMiddle
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            crumbs.topAnchor.constraint(equalTo: content.topAnchor),
            crumbs.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            crumbs.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            crumbs.heightAnchor.constraint(equalToConstant: 32),
            view.topAnchor.constraint(equalTo: crumbs.bottomAnchor),
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
        crumbs.onPick = { [unowned self] n, url in
            if let n {
                self.view.zoomTo(n)
            } else if let s = self.scanURL, s.standardizedFileURL.path == url.standardizedFileURL.path, let t = self.tree {
                self.view.zoomTo(t)
            } else {
                self.scan(url)
            }
            _ = self.window.makeFirstResponder(self.view)
        }
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
        crumbs.show(nil)
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

    func title(_ n: Node) {
        window.title = "\(n.path) — \(bytes.string(fromByteCount: n.size)) — \(num(n.count)) files"
        crumbs.show(n)
    }
    func num(_ n: Int) -> String { NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal) }
}
