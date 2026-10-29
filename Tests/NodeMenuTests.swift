import AppKit
import Testing
@testable import Treemap

@Suite("NodeMenu")
struct NodeMenuTests {
    final class Target: NSObject {
        @objc func reveal() {}
        @objc func trash() {}
        @objc func zoomOut() {}
    }

    let target = Target()

    func menu(node: Node?, canZoomOut: Bool) -> NSMenu {
        NodeMenu.make(node: node, canZoomOut: canZoomOut, target: target,
                      reveal: #selector(Target.reveal), trash: #selector(Target.trash), zoomOut: #selector(Target.zoomOut))
    }

    func item(_ m: NSMenu, _ title: String) -> NSMenuItem? {
        m.items.first { $0.title == title }
    }

    @Test func orderIsRevealTrashSeparatorZoomOut() {
        let m = menu(node: nil, canZoomOut: false)
        #expect(m.items.map(\.title) == ["Reveal in Finder", "Move to Trash", "", "Zoom Out"])
        #expect(m.items[2].isSeparatorItem)
    }

    @Test func childEnablesRevealAndTrash() {
        let root = Node("root", nil)
        let child = file("a.bin", root, size: 1)
        let m = menu(node: child, canZoomOut: true)
        #expect(item(m, "Reveal in Finder")?.isEnabled == true)
        #expect(item(m, "Move to Trash")?.isEnabled == true)
        #expect(item(m, "Zoom Out")?.isEnabled == true)
    }

    @Test func missingNodeDisablesRevealAndTrash() {
        let m = menu(node: nil, canZoomOut: true)
        #expect(item(m, "Reveal in Finder")?.isEnabled == false)
        #expect(item(m, "Move to Trash")?.isEnabled == false)
        #expect(item(m, "Zoom Out")?.isEnabled == true)
    }

    @Test func rootNodeCannotBeTrashed() {
        let root = dir("root", nil, [])
        let m = menu(node: root, canZoomOut: false)
        #expect(item(m, "Reveal in Finder")?.isEnabled == true)
        #expect(item(m, "Move to Trash")?.isEnabled == false)
        #expect(item(m, "Zoom Out")?.isEnabled == false)
    }
}
