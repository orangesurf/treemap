import Foundation
import Testing
@testable import Treemap

@Suite("Scan.fnv")
struct FnvTests {
    @Test(arguments: [
        ("", UInt32(0x811c9dc5)),
        ("a", UInt32(0xe40c292c)),
        ("foobar", UInt32(0xbf9cf968)),
        ("swift", UInt32(0xb13260d8)),
    ])
    func matchesFNV1a32(_ string: String, _ expected: UInt32) {
        #expect(Scan.fnv(string) == expected)
    }

    @Test func isCaseSensitive() {
        #expect(Scan.fnv("Swift") != Scan.fnv("swift"))
    }
}

@Suite("Scan.run")
struct ScanTests {
    @Test func emptyDirectoryIsADirWithZeroSize() throws {
        try withTempDir { dir in
            let tree = Scan.run(dir) { _ in }
            #expect(tree.isDir)
            #expect(tree.name == dir.path)
            #expect(tree.path == dir.path)
            #expect(tree.size == 0)
            #expect(tree.count == 0)
            #expect(tree.children?.isEmpty == true)
            #expect(tree.tag == 0)
        }
    }

    @Test func recordsAllocatedSizeCountAndExtensionTag() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("note.TXT")
            try writeFile(url, bytes: 4096)
            let tree = Scan.run(dir) { _ in }
            let n = try #require(child(tree, "note.TXT"))
            #expect(!n.isDir)
            #expect(n.count == 1)
            #expect(n.size == (try allocatedSize(of: url)))
            #expect(n.tag == Scan.fnv("txt"))
            #expect(tree.size == n.size)
            #expect(tree.count == 1)
            #expect(tree.tag == n.tag)
        }
    }

    @Test func fileWithNoExtensionUsesEmptyTag() throws {
        try withTempDir { dir in
            try writeFile(dir.appendingPathComponent("LICENSE"), bytes: 16)
            let tree = Scan.run(dir) { _ in }
            let n = try #require(child(tree, "LICENSE"))
            #expect(n.tag == Scan.fnv(""))
        }
    }

    @Test func rollsUpNestedDirectoriesAndSortsBySizeDescending() throws {
        try withTempDir { dir in
            let nested = dir.appendingPathComponent("nested", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            let small = dir.appendingPathComponent("small.bin")
            let large = dir.appendingPathComponent("large.bin")
            let inner = nested.appendingPathComponent("inner.bin")
            try writeFile(small, bytes: 1)
            try writeFile(large, bytes: 200_000)
            try writeFile(inner, bytes: 50_000)

            let tree = Scan.run(dir) { _ in }
            let nestedSize = try allocatedSize(of: inner)
            let expected = [
                ("large.bin", try allocatedSize(of: large)),
                ("nested", nestedSize),
                ("small.bin", try allocatedSize(of: small)),
            ].sorted { $0.1 > $1.1 }.map(\.0)
            #expect(tree.children?.map(\.name) == expected)

            let nestedNode = try #require(child(tree, "nested"))
            #expect(nestedNode.isDir)
            #expect(nestedNode.count == 1)
            #expect(nestedNode.size == nestedSize)
            #expect(tree.count == 3)
            #expect(tree.size == (tree.children ?? []).reduce(Int64(0)) { $0 + $1.size })
        }
    }

    @Test func directoryTagComesFromLargestDescendantType() throws {
        try withTempDir { dir in
            try writeFile(dir.appendingPathComponent("tiny.swift"), bytes: 50)
            try writeFile(dir.appendingPathComponent("huge.png"), bytes: 9000)
            let tree = Scan.run(dir) { _ in }
            #expect(tree.tag == Scan.fnv("png"))
        }
    }

    @Test func treatsSymlinkAsAFileAndDoesNotFollowIt() throws {
        try withTempDir { dir in
            let target = dir.appendingPathComponent("real", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try writeFile(target.appendingPathComponent("secret.bin"), bytes: 5000)
            let link = dir.appendingPathComponent("alias")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

            let tree = Scan.run(dir) { _ in }
            let alias = try #require(child(tree, "alias"))
            #expect(!alias.isDir)
            #expect(alias.count == 1)
            #expect(alias.size == (try allocatedSize(of: link)))
            #expect(alias.size < 5000)
            #expect(child(tree, "real")?.isDir == true)
            #expect(tree.count == 2)
        }
    }

    @Test func countsHardLinksSeparately() throws {
        try withTempDir { dir in
            let a = dir.appendingPathComponent("a.bin")
            let b = dir.appendingPathComponent("b.bin")
            try writeFile(a, bytes: 2048)
            try FileManager.default.linkItem(at: a, to: b)

            let tree = Scan.run(dir) { _ in }
            #expect(tree.count == 2)
            let aNode = try #require(child(tree, "a.bin"))
            let bNode = try #require(child(tree, "b.bin"))
            #expect(aNode.size == bNode.size)
            #expect(tree.size == aNode.size + bNode.size)
        }
    }

    @Test func usesAllocatedSizeNotLogicalSizeForSparseFiles() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("sparse.bin")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 1_000_000)
            try handle.close()

            let vals = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            let allocated = Int64(vals.totalFileAllocatedSize ?? 0)
            let logical = Int64(vals.fileSize ?? 0)
            try #require(logical == 1_000_000)
            try #require(allocated < logical)

            let tree = Scan.run(dir) { _ in }
            let n = try #require(child(tree, "sparse.bin"))
            #expect(n.size == allocated)
            #expect(n.size != logical)
        }
    }

    @Test func unreadableDirectoryStaysEmpty() throws {
        try withTempDir { dir in
            let locked = dir.appendingPathComponent("secret", isDirectory: true)
            try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
            try writeFile(locked.appendingPathComponent("hidden.bin"), bytes: 100)
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

            let tree = Scan.run(dir) { _ in }
            let n = try #require(child(tree, "secret"))
            #expect(n.isDir)
            #expect(n.children?.isEmpty == true)
            #expect(n.size == 0)
            #expect(n.count == 0)
        }
    }

    @Test func progressFiresEvery4096Files() throws {
        try withTempDir { dir in
            for i in 0..<4096 {
                FileManager.default.createFile(atPath: dir.appendingPathComponent("f\(i)").path, contents: Data())
            }
            var ticks: [Int] = []
            let tree = Scan.run(dir) { ticks.append($0) }
            #expect(tree.count == 4096)
            #expect(ticks == [4096])
        }
    }

    @Test func progressDoesNotFireBefore4096Files() throws {
        try withTempDir { dir in
            for i in 0..<4095 {
                FileManager.default.createFile(atPath: dir.appendingPathComponent("f\(i)").path, contents: Data())
            }
            var ticks: [Int] = []
            _ = Scan.run(dir) { ticks.append($0) }
            #expect(ticks.isEmpty)
        }
    }
}
