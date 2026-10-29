import Foundation
import Testing
@testable import Treemap

@Suite("FolderList")
struct FolderListTests {
    @Test func includesFilesAndFoldersInChildOrder() {
        let root = Node("root", nil)
        let big = dir("big", root, [file("x.bin", nil, size: 80)])
        let pic = file("photo.jpg", root, size: 50)
        let small = dir("small", root, [file("y.bin", nil, size: 20)])
        let empty = dir("empty", root, [])
        root.children = [big, pic, small, empty]
        root.size = 150
        #expect(FolderList.entries(under: root).map(\.name) == ["big", "photo.jpg", "small", "empty"])
    }

    @Test func emptyWhenNilOrFile() {
        #expect(FolderList.entries(under: nil).isEmpty)
        #expect(FolderList.entries(under: file("a.bin", nil, size: 10)).isEmpty)
    }

    @Test func emptyDirectoryHasNoEntries() {
        let root = dir("root", nil, [])
        #expect(FolderList.entries(under: root).isEmpty)
    }

    @Test func filesOnlyDirectoryListsTheFiles() {
        let root = Node("root", nil)
        root.children = [file("a.bin", root, size: 10), file("b.bin", root, size: 5)]
        root.size = 15
        #expect(FolderList.entries(under: root).map(\.name) == ["a.bin", "b.bin"])
    }
}
