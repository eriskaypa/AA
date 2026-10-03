// Fixture data for the W-PDF suites: the 11 §7.12 saved lists, the 11 §7.13 items, and a hand-built XAML DOM
// builder (so the rich-text pipeline can be exercised without the W-RICH parser).
import Foundation
import Testing
@testable import AACore

@MainActor
enum PdfTestData {
    static let xmlns = "http://schemas.microsoft.com/winfx/2006/xaml/presentation"

    static func day(_ y: Int, _ m: Int, _ d: Int) -> NetDateTime { NetDateTime(year: y, month: m, day: d, kind: .unspecified) }

    /// Editor-shaped XAML with one paragraph (`TextRange.Save` root, 05 §4.3).
    static func xaml(_ paragraphs: [String]) -> String {
        "<Section xmlns=\"\(xmlns)\" xml:space=\"preserve\" TextAlignment=\"Left\" LineHeight=\"Auto\" xml:lang=\"en-us\" "
            + "FlowDirection=\"LeftToRight\" FontFamily=\"Consolas\" FontStyle=\"Normal\" FontWeight=\"Normal\" "
            + "FontStretch=\"Normal\" FontSize=\"14\" Foreground=\"#FF1A1A1A\">"
            + paragraphs.map { "<Paragraph><Run>\($0)</Run></Paragraph>" }.joined() + "</Section>"
    }

    struct Golden {
        let made: StoreFactory.Made
        let pumpRoom: Equipment
        let overhaul: TaskItem
        let loto: Procedure
        let aurora: Vessel
        let dangling = UUID(uuidString: "DEADBEEF-0000-0000-0000-000000000001")!
    }

    /// 11 §7.13: Task "Pump overhaul", Procedure "LOTO", Equipment "Pump room", Vessel "MV Aurora".
    static func golden() -> Golden {
        let data = AppData()
        let pumpRoom = Equipment(id: G(1), name: "Pump room")
        pumpRoom.description = "Aft"
        pumpRoom.components = [Component(name: "Impeller", notes: "Check wear")]
        let overhaul = TaskItem(id: G(2), name: "Pump overhaul")
        overhaul.description = "Yearly job"
        overhaul.container.richTextXaml = xaml(["See https://x.io"])
        overhaul.deadline = day(2026, 7, 10)
        overhaul.rangeStart = day(2026, 7, 8)
        overhaul.recurrence = .yearly
        overhaul.isComplete = false
        let drain = TaskItem(id: G(3), name: "Drain")
        drain.deadline = day(2026, 7, 9)
        drain.container.richTextXaml = xaml(["Use tray"])
        drain.subtasks = [TaskItem(id: G(4), name: "Check level")]
        overhaul.subtasks = [drain]
        overhaul.container.files = [FileItem(name: "manual.pdf", path: "files/manual.pdf", kind: .document)]
        let loto = Procedure(id: G(5), name: "LOTO")
        let s1 = ChecklistStep(title: "Isolate")
        s1.done = true
        s1.deadline = day(2026, 7, 1)
        s1.equipmentIds = [pumpRoom.id]
        let golden = Golden(made: StoreFactory.make(data: data), pumpRoom: pumpRoom, overhaul: overhaul, loto: loto,
                            aurora: Vessel(id: G(6), name: "MV Aurora"))
        s1.taskIds = [overhaul.id, golden.dangling]
        loto.steps = [s1, ChecklistStep(title: "Tag")]
        overhaul.relatedIds = [pumpRoom.id, loto.id]
        pumpRoom.procedureIds = [loto.id, golden.dangling]
        data.equipment = [pumpRoom]
        data.tasks = [overhaul]
        data.procedures = [loto]
        data.vessels = [golden.aurora]
        return golden
    }

    /// 11 §7.12: groups G1 "Deck", G2 "engine"; T1 "Mooring" (g2, 2 items, item 1 IsJob), T2 "Ungrp A" (null,
    /// 0 items), T3 "Anchoring" (g1, 1 item), T4 "Bunkering" (g2, 1 item).
    static func savedLists() -> AppData {
        let data = AppData()
        let g1 = ListGroup(id: G(101), name: "Deck"), g2 = ListGroup(id: G(102), name: "engine")
        data.listGroups = [g1, g2]
        let t1 = ChecklistTemplate(id: G(201), name: "Mooring",
                                   items: [ChecklistTemplateItem(title: "item1", isJob: true), ChecklistTemplateItem(title: "item2")],
                                   groupId: g2.id)
        let t2 = ChecklistTemplate(id: G(202), name: "Ungrp A", items: [], groupId: nil)
        let t3 = ChecklistTemplate(id: G(203), name: "Anchoring", items: [ChecklistTemplateItem(title: "Clear the hawse")],
                                   groupId: g1.id)
        let t4 = ChecklistTemplate(id: G(204), name: "Bunkering", items: [ChecklistTemplateItem(title: "Sound tanks")],
                                   groupId: g2.id)
        data.checklistTemplates = [t1, t2, t3, t4]
        return data
    }

    static func lookup(_ g: Golden) -> PdfLookup {
        PdfSnapshotBuilder.lookup(store: g.made.store, isGated: { _ in false })
    }
}

/// Hand-built XAML DOM trees (pre-order arena with parent links), for driving `PdfRichText.blocks(of:)` without
/// the W-RICH parser. Styles resolve through the resolver of this worktree (context values when W-RICH is a stub).
indirect enum PdfX {
    case el(XamlNodeKind, XamlLocalValues, [PdfX])
    case run(String, XamlLocalValues)

    static func section(_ c: [PdfX]) -> PdfX { .el(.section, XamlLocalValues(), c) }
    static func p(_ c: [PdfX], _ l: XamlLocalValues = XamlLocalValues()) -> PdfX { .el(.paragraph, l, c) }
    static func r(_ t: String, _ l: XamlLocalValues = XamlLocalValues()) -> PdfX { .run(t, l) }
    static func list(_ marker: String, _ items: [[PdfX]]) -> PdfX {
        var l = XamlLocalValues(); l.markerStyle = marker
        return .el(.list, l, items.map { .el(.listItem, XamlLocalValues(), $0) })
    }
    static func link(_ uri: String?, _ c: [PdfX]) -> PdfX {
        var l = XamlLocalValues(); l.navigateUri = uri
        return .el(.hyperlink, l, c)
    }
    static var br: PdfX { .el(.lineBreak, XamlLocalValues(), []) }

    static func doc(_ root: PdfX) -> XamlDocument {
        var nodes: [(kind: XamlNodeKind, local: XamlLocalValues, text: String?, parent: Int?, children: [Int])] = []
        func add(_ x: PdfX, parent: Int?) -> Int {
            let id = nodes.count
            switch x {
            case .run(let t, let l):
                nodes.append((.run, l, t, parent, []))
            case .el(let k, let l, let kids):
                nodes.append((k, l, nil, parent, []))
                var ids: [Int] = []
                for c in kids { ids.append(add(c, parent: id)) }
                nodes[id].children = ids
            }
            return id
        }
        _ = add(root, parent: nil)
        let built = nodes.map { n in
            XamlNode(kind: n.kind, qualifiedName: "\(n.kind)", local: n.local, text: n.text,
                     parent: n.parent.map { XamlNodeID(index: Int32($0)) },
                     children: n.children.map { XamlNodeID(index: Int32($0)) })
        }
        return XamlDocument(source: "", nodes: built, root: XamlNodeID(index: 0), rootRole: .wrapper(.section),
                            loadability: .loadable, issues: [])
    }
}

extension XamlLocalValues {
    static func pdfWith(_ f: (inout XamlLocalValues) -> Void) -> XamlLocalValues {
        var l = XamlLocalValues(); f(&l); return l
    }
}
