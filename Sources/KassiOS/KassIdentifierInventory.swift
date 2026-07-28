import XCTest

/// A snapshot of one element's identity, for discovery/scaffolding.
public struct KassIdentifierInfo: Codable, Sendable, Equatable {
    public let identifier: String
    public let type: String          // KassScreen.typeName(...)
    public let label: String
    public let isHittable: Bool
}

public extension KassDevice {

    /// Walks the current screen and returns every element's identity —
    /// `{ identifier, type, label, isHittable }` — for discovery/scaffolding.
    ///
    /// By default only elements that carry a real accessibility identifier (the
    /// inventory you'd build `KassScreen` objects from); pass
    /// `includingUnidentified: true` to also list the rest (raw discovery).
    /// Bounded to `KassTreeWalk.elementCap` elements so a huge tree can't hang
    /// the call.
    func dumpIdentifiers(includingUnidentified: Bool = false) -> [KassIdentifierInfo] {
        config.synchronizer.waitForIdle(timeout: config.timeout)
        return KassTreeWalk.walk(app)
            .filter { includingUnidentified || !$0.identifier.isEmpty }
            .map {
                KassIdentifierInfo(
                    identifier: $0.identifier,
                    type: KassScreen.typeName($0.type),
                    label: $0.label,
                    isHittable: $0.isHittable
                )
            }
    }

    /// Same as ``dumpIdentifiers(includingUnidentified:)``, but also attaches
    /// the inventory as a pretty-printed JSON artifact to the report — hand it
    /// to a coding agent to scaffold `KassScreen` objects.
    @discardableResult
    func attachIdentifierInventory(includingUnidentified: Bool = false) -> [KassIdentifierInfo] {
        let inventory = dumpIdentifiers(includingUnidentified: includingUnidentified)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(inventory)) ?? Data()
        attachText("Identifier inventory", String(data: data, encoding: .utf8) ?? "[]")
        return inventory
    }
}
