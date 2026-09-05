import Foundation
import Testing
@testable import Treemap

@Suite("Breadcrumb")
struct BreadcrumbTests {
    @Test func volumeRootIsASingleCrumb() {
        let root = Node("/", nil)
        let items = Breadcrumb.items(for: root, volumeName: "Macintosh HD")
        #expect(items.count == 1)
        #expect(items[0].title == "Macintosh HD")
        #expect(items[0].url.path == "/")
        #expect(items[0].node === root)
    }

    @Test func splitsAFullPathAndBindsEachAncestor() {
        let root = Node("/", nil)
        let users = Node("Users", root)
        let me = Node("me", users)
        let items = Breadcrumb.items(for: me, volumeName: "Macintosh HD")
        #expect(items.map(\.title) == ["Macintosh HD", "Users", "me"])
        #expect(items.map(\.url.path) == ["/", "/Users", "/Users/me"])
        #expect(items[0].node === root)
        #expect(items[1].node === users)
        #expect(items[2].node === me)
    }

    @Test func scanRootThatIsNotSlashLeavesHigherCrumbsUnbound() {
        let top = Node("/Users/me/Downloads", nil)
        let folder = Node("Projects", top)
        let items = Breadcrumb.items(for: folder, volumeName: "Data")
        #expect(items.map(\.title) == ["Data", "Users", "me", "Downloads", "Projects"])
        #expect(items[0].node == nil)
        #expect(items[1].node == nil)
        #expect(items[2].node == nil)
        #expect(items[3].node === top)
        #expect(items[4].node === folder)
        #expect(items.map(\.url.path) == ["/", "/Users", "/Users/me", "/Users/me/Downloads", "/Users/me/Downloads/Projects"])
    }

    @Test func usesTheSuppliedVolumeName() {
        let n = Node("/tmp", nil)
        let items = Breadcrumb.items(for: n, volumeName: "External")
        #expect(items.first?.title == "External")
    }
}
