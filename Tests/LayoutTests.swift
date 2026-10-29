import CoreGraphics
import Testing
@testable import Treemap

@Suite("Layout.worst")
struct WorstTests {
    @Test func isOneForAPerfectSquare() {
        // Row area 100, side 10, one item of 100 → 10×10 square.
        #expect(Layout.worst(100, 100, 100, 10) == 1)
    }

    @Test func growsAsTheRowGetsSkinny() {
        let square = Layout.worst(100, 100, 100, 10)
        let skinny = Layout.worst(100, 80, 20, 10)
        #expect(skinny > square)
    }
}

@Suite("Layout.tileAreas")
struct TileAreaTests {
    let rect = CGRect(x: 0, y: 0, width: 200, height: 100)

    @Test func singleChildGetsTheFullArea() {
        let kid = file("only", nil, size: 50)
        #expect(Layout.tileAreas([kid], in: rect) == [20000])
    }

    @Test func proportionalSplitSumsToTheRect() {
        let a = file("a", nil, size: 75)
        let b = file("b", nil, size: 25)
        let areas = Layout.tileAreas([a, b], in: rect)
        #expect(areas.reduce(0, +) == 20000)
        #expect(areas[0] == 15000)
        #expect(areas[1] == 5000)
    }

    @Test func capsTheGiantChildAtMaxShare() {
        let huge = file("huge", nil, size: 99)
        let tiny = file("tiny", nil, size: 1)
        let areas = Layout.tileAreas([huge, tiny], in: rect)
        let cap = 20000 * Layout.maxShare
        #expect(areas[0] == cap)
        #expect(areas[1] == 20000 - cap)
        #expect(areas.reduce(0, +) == 20000)
    }

    @Test func liftsTinyTilesTowardTheClickableFloor() {
        let huge = file("huge", nil, size: 10_000)
        let speck = file("speck", nil, size: 1)
        let areas = Layout.tileAreas([huge, speck], in: CGRect(x: 0, y: 0, width: 400, height: 400))
        let minA = Double(Layout.minSide * Layout.minSide)
        #expect(areas[1] >= minA)
        #expect(areas[0] + areas[1] == 160_000)
        #expect(areas[0] <= 160_000 * Layout.maxShare + 1e-6)
    }

    @Test func equalChildrenStayEqual() {
        let kids = (0..<4).map { file("f\($0)", nil, size: 10) }
        let areas = Layout.tileAreas(kids, in: rect)
        #expect(areas.allSatisfy { abs($0 - 5000) < 1e-9 })
    }
}

@Suite("Layout.place")
struct PlaceTests {
    @Test func fileOccupiesTheWholeRect() {
        let n = file("a.txt", nil, size: 10)
        let rect = CGRect(x: 5, y: 7, width: 40, height: 30)
        let items = Layout.place(n, rect)
        #expect(items.count == 1)
        #expect(items[0].1 === n)
        #expect(items[0].0 == rect)
    }

    @Test func emptyOrZeroSizeDirectoryStaysASingleTile() {
        let empty = dir("empty", nil, [])
        let zero = dir("zero", nil, [file("z", nil, size: 0)])
        zero.size = 0
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(Layout.place(empty, rect).map { $0.1.name } == ["empty"])
        #expect(Layout.place(zero, rect).map { $0.1.name } == ["zero"])
    }

    @Test func skipsSubPixelRects() {
        let n = file("a", nil, size: 1)
        #expect(Layout.place(n, CGRect(x: 0, y: 0, width: 0.4, height: 10)).isEmpty)
        #expect(Layout.place(n, CGRect(x: 0, y: 0, width: 10, height: 0.4)).isEmpty)
    }

    @Test func tinyRectDoesNotDescendIntoChildren() {
        let root = dir("root", nil, [file("a", nil, size: 10), file("b", nil, size: 10)])
        let items = Layout.place(root, CGRect(x: 0, y: 0, width: 2, height: 2))
        #expect(items.count == 1)
        #expect(items[0].1 === root)
    }

    @Test func placesOneLevelAndLeavesFoldersClosed() {
        let root = Node("root", nil)
        let folder = Node("folder", root)
        let inner = file("inner.bin", folder, size: 40)
        folder.children = [inner]
        folder.size = 40
        folder.count = 1
        let outer = file("outer.bin", root, size: 60)
        root.children = [outer, folder]
        root.size = 100
        root.count = 2

        let items = Layout.place(root, CGRect(x: 0, y: 0, width: 200, height: 100))
        let names = Set(items.map { $0.1.name })
        #expect(names == ["outer.bin", "folder"])
        #expect(!names.contains("inner.bin"))
        #expect(!names.contains("root"))
    }

    @Test func childTilesFillTheParentWithoutOverlap() {
        let root = Node("root", nil)
        let kids = [file("a", root, size: 50), file("b", root, size: 30), file("c", root, size: 20)]
        root.children = kids
        root.size = 100
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let items = Layout.place(root, rect)
        #expect(items.count == 3)

        var covered: CGFloat = 0
        for i in items.indices {
            let ri = items[i].0
            covered += ri.width * ri.height
            #expect(rect.contains(ri) || rect.insetBy(dx: -0.01, dy: -0.01).contains(ri))
            for j in items.indices where j > i {
                let overlap = items[i].0.intersection(items[j].0)
                #expect(overlap.width * overlap.height < 1, "tiles overlap: \(items[i].1.name) vs \(items[j].1.name)")
            }
        }
        #expect(abs(covered - rect.width * rect.height) < 1)
    }

    @Test func ignoresZeroSizeChildrenWhenTiling() {
        let root = Node("root", nil)
        let visible = file("visible", root, size: 10)
        let ghost = file("ghost", root, size: 0)
        root.children = [visible, ghost]
        root.size = 10
        let items = Layout.place(root, CGRect(x: 0, y: 0, width: 80, height: 80))
        #expect(items.map { $0.1.name } == ["visible"])
    }
}
