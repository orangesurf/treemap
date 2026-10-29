import Foundation
import Testing
@testable import Treemap

@Suite("Node")
struct NodeTests {
    @Test func fileIsNotADirectory() {
        let n = Node("a.txt", nil)
        #expect(!n.isDir)
        #expect(n.children == nil)
    }

    @Test func emptyChildrenMakesADirectory() {
        let n = Node("docs", nil)
        n.children = []
        #expect(n.isDir)
    }

    @Test func pathIsTheNameWhenThereIsNoParent() {
        let n = Node("/Users/me/Downloads", nil)
        #expect(n.path == "/Users/me/Downloads")
        #expect(n.url.path == "/Users/me/Downloads")
    }

    @Test func pathJoinsParentAndName() {
        let root = Node("/Users/me", nil)
        let child = Node("Downloads", root)
        #expect(child.path == "/Users/me/Downloads")
    }

    @Test func pathUnderVolumeRootDoesNotDoubleSlash() {
        let root = Node("/", nil)
        let users = Node("Users", root)
        let me = Node("me", users)
        #expect(users.path == "/Users")
        #expect(me.path == "/Users/me")
        #expect(me.url.path == "/Users/me")
    }

    @Test func nestedPathUsesSingleSlashSeparators() {
        let a = Node("/tmp", nil)
        let b = Node("x", a)
        let c = Node("y.txt", b)
        #expect(c.path == "/tmp/x/y.txt")
    }

    @Test func detachRemovesChildAndRollsSizeAndCountUp() {
        let root = Node("/tmp", nil)
        let docs = Node("docs", root)
        let keep = file("keep.bin", docs, size: 30)
        let gone = file("gone.bin", docs, size: 70)
        docs.children = [gone, keep]
        docs.size = 100
        docs.count = 2
        root.children = [docs]
        root.size = 100
        root.count = 2

        gone.detach()

        #expect(docs.children?.count == 1)
        #expect(docs.children?.first === keep)
        #expect(docs.size == 30)
        #expect(docs.count == 1)
        #expect(root.size == 30)
        #expect(root.count == 1)
        #expect(root.children?.first === docs)
    }

    @Test func detachReSortsAncestorSiblingsBySize() {
        let root = Node("/tmp", nil)
        let a = Node("a", root)
        let b = Node("b", root)
        let big = file("big.bin", a, size: 80)
        let small = file("small.bin", a, size: 10)
        a.children = [big, small]
        a.size = 90
        a.count = 2
        let other = file("other.bin", b, size: 50)
        b.children = [other]
        b.size = 50
        b.count = 1
        root.children = [a, b]
        root.size = 140
        root.count = 3

        big.detach()

        #expect(a.size == 10)
        #expect(root.children?.map(\.name) == ["b", "a"])
        #expect(root.size == 60)
        #expect(root.count == 2)
    }

    @Test func detachOnRootIsANoOp() {
        let root = Node("/tmp", nil)
        root.children = []
        root.size = 12
        root.count = 3
        root.detach()
        #expect(root.size == 12)
        #expect(root.count == 3)
        #expect(root.children?.isEmpty == true)
    }
}
