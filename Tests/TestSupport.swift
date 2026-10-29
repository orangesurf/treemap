import Foundation
@testable import Treemap

func file(_ name: String, _ parent: Node?, size: Int64, tag: UInt32 = 0) -> Node {
    let n = Node(name, parent)
    n.size = size
    n.count = 1
    n.tag = tag
    return n
}

func dir(_ name: String, _ parent: Node?, _ children: [Node]) -> Node {
    let n = Node(name, parent)
    n.children = children
    n.size = children.reduce(0) { $0 + $1.size }
    n.count = children.reduce(0) { $0 + $1.count }
    n.tag = children.first(where: { $0.size > 0 })?.tag ?? 0
    return n
}

func withTempDir(_ body: (URL) throws -> Void) throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("treemap-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url) }
    try body(url)
}

func writeFile(_ url: URL, bytes: Int) throws {
    try Data(repeating: 0x61, count: bytes).write(to: url)
}

func allocatedSize(of url: URL) throws -> Int64 {
    let v = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
    return Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
}

func child(_ node: Node, _ name: String) -> Node? {
    node.children?.first { $0.name == name }
}
