import XCTest
@testable import KassiOS

final class KassTreeWalkTests: XCTestCase {

    /// A stand-in for `XCUIElementSnapshot`: just a name and children.
    private struct Node {
        let id: String
        var children: [Node] = []
    }

    private func ids(_ root: Node, cap: Int) -> [String] {
        KassTreeWalk.flatten(root, cap: cap, children: \.children) {
            KassTreeWalk.Visited(identifier: $0.id, label: "", type: .other, isHittable: true)
        }.map(\.identifier)
    }

    private let tree = Node(id: "app", children: [
        Node(id: "a", children: [Node(id: "a1"), Node(id: "a2", children: [Node(id: "a2x")])]),
        Node(id: "b"),
        Node(id: "c", children: [Node(id: "c1")])
    ])

    func test_flatten_isPreOrder_excludingRoot() {
        // Same order as `descendants(matching: .any)`.
        XCTAssertEqual(ids(tree, cap: 100), ["a", "a1", "a2", "a2x", "b", "c", "c1"])
    }

    func test_flatten_stopsAtCap() {
        XCTAssertEqual(ids(tree, cap: 3), ["a", "a1", "a2"])
        XCTAssertEqual(ids(tree, cap: 0), [])
    }

    func test_flatten_leafRoot_isEmpty() {
        XCTAssertEqual(ids(Node(id: "app"), cap: 10), [])
    }

    func test_flatten_deepTree_doesNotRecurse() {
        var node = Node(id: "leaf")
        for depth in 0..<20_000 { node = Node(id: "n\(depth)", children: [node]) }
        XCTAssertEqual(ids(node, cap: KassTreeWalk.elementCap).count, KassTreeWalk.elementCap)
    }

    func test_isOnScreen() {
        let app = CGRect(x: 0, y: 0, width: 400, height: 800)
        XCTAssertTrue(KassTreeWalk.isOnScreen(CGRect(x: 10, y: 10, width: 50, height: 20), within: app))
        XCTAssertTrue(KassTreeWalk.isOnScreen(CGRect(x: 380, y: 790, width: 50, height: 20), within: app))
        XCTAssertFalse(KassTreeWalk.isOnScreen(CGRect(x: 0, y: 900, width: 50, height: 20), within: app))
        XCTAssertFalse(KassTreeWalk.isOnScreen(CGRect(x: 10, y: 10, width: 0, height: 20), within: app))
        XCTAssertFalse(KassTreeWalk.isOnScreen(.zero, within: app))
    }
}
