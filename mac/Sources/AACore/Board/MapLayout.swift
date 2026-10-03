// Spec: 07 §3.5 VIEW-170…182 (Relationship Map: inspect list, search, title, 1-hop graph, circle layout, edges, focus
//       persistence), §4.5.1–4.5.4, 02 REPO-031 (map caller of RelatedItems), W-19 (the centre is never its own
//       neighbour), DECISIONS 07 Q-10 (per-kind colours — rendering in the AA target).
import Foundation

public struct MapPoint: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// One row of the Inspect list (VIEW-171).
@MainActor
public struct MapInspectRow: @MainActor Identifiable {
    public let item: HierarchyItem
    public let id: String
    /// `"[{Kind}] {Name}"` with the enum kind name.
    public let text: String
}

/// A drawn graph (VIEW-175…177).
@MainActor
public struct MapGraph {
    public let centre: HierarchyItem
    public let related: [HierarchyItem]
    /// Node positions by item id (centre first).
    public let positions: [UUID: MapPoint]
    /// Dashed neighbour↔neighbour edges as (i, j) indices into `related`, i < j.
    public let dashedEdges: [(Int, Int)]
}

@MainActor
public enum MapLayout {
    public static let canvasWidth = 1400.0
    public static let canvasHeight = 900.0
    public static let centre = MapPoint(x: 700, y: 450)
    /// `min(700, 450) − 140`.
    public static let radius = 310.0
    public static let inspectTitle = "Inspect"
    public static let baseTitle = "Relationship Map"

    /// VIEW-171: every top-level item in `AllItems()` order.
    public static func inspectRows(store: AppStore) -> [MapInspectRow] {
        store.allItems().enumerated().map { i, item in
            MapInspectRow(item: item, id: "\(i)-" + item.id.netString, text: "[\(item.kind.name)] \(item.name)")
        }
    }

    /// VIEW-172: trimmed query, display text contains it (OrdinalIgnoreCase).
    public static func filter(_ rows: [MapInspectRow], query: String) -> [MapInspectRow] {
        let q = NetText.trim(query)
        guard !q.isEmpty else { return rows }
        return rows.filter { NetText.containsIgnoreCase($0.text, q) }
    }

    /// VIEW-174.
    public static func title(_ centre: HierarchyItem?) -> String {
        guard let centre else { return baseTitle }
        return baseTitle + " \u{2014} " + centre.name
    }

    /// VIEW-175: `RelatedItems(centre)` (RelatedIds, then Equipment ProcedureIds / TaskIds; resolved among top-level
    /// items; de-duplicated in first-seen order) without the centre itself (W-19).
    public static func related(of centre: HierarchyItem, store: AppStore) -> [HierarchyItem] {
        var seen = Set<ObjectIdentifier>()
        return store.relatedItems(of: centre).filter { $0.id != centre.id && seen.insert(ObjectIdentifier($0)).inserted }
    }

    /// VIEW-176: node i of n at angle 2π·i/n on the 310 circle (clockwise on screen, i = 0 at 3 o'clock).
    public static func circlePositions(count n: Int) -> [MapPoint] {
        (0..<n).map { i in
            let a = 2 * Double.pi * Double(i) / Double(max(1, n))
            return MapPoint(x: centre.x + radius * cos(a), y: centre.y + radius * sin(a))
        }
    }

    /// VIEW-177: dashed edge i<j when `related[i].RelatedIds` contains `related[j].Id` (one direction checked).
    public static func dashedEdges(_ related: [HierarchyItem]) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for i in related.indices {
            for j in related.indices where j > i && related[i].relatedIds.contains(related[j].id) { out.append((i, j)) }
        }
        return out
    }

    public static func graph(centre: HierarchyItem, store: AppStore) -> MapGraph {
        let rel = related(of: centre, store: store)
        var pos: [UUID: MapPoint] = [centre.id: Self.centre]
        for (item, p) in zip(rel, circlePositions(count: rel.count)) where pos[item.id] == nil { pos[item.id] = p }
        return MapGraph(centre: centre, related: rel, positions: pos, dashedEdges: dashedEdges(rel))
    }

    /// VIEW-180: the persisted focus resolves among top-level items only.
    public static func persistedFocus(store: AppStore) -> HierarchyItem? {
        store.data.ui.mapFocusedItemId.flatMap { store.item(id: $0) }
    }
}
