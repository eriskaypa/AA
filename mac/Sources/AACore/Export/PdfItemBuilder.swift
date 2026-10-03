// Spec: 11 §2.4 PDF-030…045 (item PDF content), §3.4.1 (BuildDocument, WriteSpecifics, WriteEquipmentSpecifics,
//       TaskWhen, WriteTaskSpecifics, WriteSubtaskDetailed, WriteProcedureSpecifics, WriteTaskSummary,
//       WriteRelationships, WriteFileBank, KindLabel, AddKV, Shorten), PDF-102, PDF-103, PDF-105, §7.4–§7.6,
//       §7.13; DECISIONS 11 Q6 (gated related/linked items: name only), Q7 (fixed yyyy-MM-dd HH:mm).
import Foundation

/// Shared scaffolding of the PdfExporter documents (items and saved lists).
public enum PdfScaffold {
    /// The running header (PDF-031 / PDF-050): 9 pt grey, right tab stop at 16 cm, `{left}` TAB `{stamp}`.
    public static func header(_ left: String, stamp: String) -> PdfParagraph {
        var f = PdfParagraphFormat(font: PdfCharFormat(size: 9, color: .muted))
        f.tabStops = [PdfTabStop(positionCm: 16, alignment: .right)]
        return PdfParagraph(style: .header, format: f, inlines: PdfText.inlines(left) + [.tab] + PdfText.inlines(stamp))
    }

    /// The footer (PDF-032 / PDF-080): right-aligned 9 pt grey `Page {n} / {N}`.
    public static func footer() -> PdfParagraph {
        let f = PdfParagraphFormat(alignment: .right, font: PdfCharFormat(size: 9, color: .muted))
        return PdfParagraph(style: .footer, format: f, inlines: [
            .text("Page ", PdfCharFormat()), .pageField(PdfCharFormat()), .text(" / ", PdfCharFormat()),
            .numPagesField(PdfCharFormat()),
        ])
    }

    /// `yyyy-MM-dd HH:mm` of a local timestamp (PDF-103: en_US_POSIX digits, Gregorian, `:` separator).
    public static func stamp(_ now: NetDateTime) -> String { now.format(.isoMinute) }
}

public enum PdfItemBuilder {
    /// `KindLabel` (11 §3.4.1): Equipment → `Equipment/Area`, else the enum name.
    public static func kindLabel(_ k: ItemKind) -> String { k == .equipment ? "Equipment/Area" : k.name }

    /// PDF-102 `Shorten(s, max)`: CR/LF → space, .NET Trim, then the first `max − 1` UTF-16 units + `…`, backing
    /// off to a grapheme boundary (never splitting a surrogate pair or cluster).
    public static func shorten(_ s: String, _ max: Int) -> String {
        let t = NetText.trim(s.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " "))
        if t.utf16.count <= max { return t }
        var out = ""
        var units = 0
        for ch in t {
            let n = String(ch).utf16.count
            if units + n > max - 1 { break }
            out.append(ch); units += n
        }
        return out + "\u{2026}"
    }

    /// PDF-041 `TaskWhen`: nil without a deadline; `{start} – {deadline}` (EN DASH) when the start is an earlier
    /// day; else `due {deadline}`.
    public static func taskWhen(deadline: CivilDate?, rangeStart: CivilDate?) -> String? {
        guard let d = deadline else { return nil }
        if let s = rangeStart, s < d { return "\(s.iso) \u{2013} \(d.iso)" }
        return "due \(d.iso)"
    }

    /// Subtask / task-summary meta: TaskWhen, then the lower-cased recurrence when not None (PDF-039/040).
    public static func meta(_ t: PdfTaskSnapshot) -> [String] {
        var m: [String] = []
        if let w = taskWhen(deadline: t.deadline, rangeStart: t.rangeStart) { m.append(w) }
        if t.recurrence != .none { m.append(NetText.toLowerInvariant(t.recurrence.name)) }
        return m
    }

    static func metaInlines(_ m: [String]) -> [PdfInline] {
        guard !m.isEmpty else { return [] }
        return PdfText.inlines("  ") + PdfText.inlines("(" + m.joined(separator: ", ") + ")",
                                                      PdfCharFormat(italic: true, color: .muted))
    }

    /// The item PDF (product A). `stamp` = `yyyy-MM-dd HH:mm` local time at export.
    public static func build(_ s: PdfItemSnapshot, stamp: String) -> PdfDoc {
        var doc = PdfDoc(title: "\(s.kind.name) - \(s.name)", styles: .pdfExporter, pageSetup: .pdfExporter)
        doc.header = [PdfScaffold.header("\(kindLabel(s.kind)): \(s.name)", stamp: stamp)]
        doc.footer = [PdfScaffold.footer()]
        var b: [PdfBlock] = []
        b.append(.paragraph(PdfParagraph(s.name, style: .title)))
        b.append(.paragraph(PdfParagraph(kindLabel(s.kind), style: .subtitle)))
        if !NetText.isBlank(s.description) { b.append(.paragraph(PdfParagraph(s.description, style: .bodyItalic))) }
        b += PdfRichText.body(s.container.xaml, heading: "Notes")
        switch s.specifics {
        case let .equipment(components, procedureIds, taskIds):
            b += equipmentSpecifics(components: components, procedureIds: procedureIds, taskIds: taskIds, lookup: s.lookup)
        case .task(let t):
            b += taskSpecifics(t)
        case .procedure(let steps):
            b += procedureSpecifics(steps, lookup: s.lookup)
        case .vessel:
            break                                                           // PDF-043
        }
        b += relationships(s.related)
        b += fileBank(s.container.files)
        doc.body = b
        return doc
    }

    // MARK: PDF-037

    static func equipmentSpecifics(components: [PdfComponentSnapshot], procedureIds: [UUID], taskIds: [UUID],
                                   lookup: PdfLookup) -> [PdfBlock] {
        if components.isEmpty && procedureIds.isEmpty && taskIds.isEmpty { return [] }
        var b: [PdfBlock] = [.paragraph(PdfParagraph("Equipment/Area Details", style: .h1))]
        if !components.isEmpty {
            b.append(.paragraph(PdfParagraph("Components (\(components.count))", style: .h2)))
            let bold = PdfParagraphFormat(font: .bold)
            var t = PdfTable(columns: [5, 11], borders: PdfBorder(width: 0.5, color: PdfColor(180, 180, 180)),
                             padding: PdfPadding(left: 3, right: 3, top: 2, bottom: 2))
            t.rows.append(PdfRow(headingFormat: true, shading: .tableHeader,
                                 cells: [PdfCell("Component", format: bold), PdfCell("Notes", format: bold)]))
            for c in components { t.rows.append(PdfRow(cells: [PdfCell(c.name), PdfCell(c.notes)])) }
            b.append(.table(t))
        }
        if !procedureIds.isEmpty {
            b.append(.paragraph(PdfParagraph("Linked Procedures (\(procedureIds.count))", style: .h2)))   // raw count
            for id in procedureIds {
                guard let p = lookup.find(id), p.kind == .procedure else { continue }
                b.append(.paragraph(PdfParagraph(p.name, style: .h3)))
                if p.isGated { continue }                                     // DECISIONS 11 Q6
                if !NetText.isBlank(p.description) { b.append(.paragraph(PdfParagraph(p.description, style: .bodyItalic))) }
                for (i, st) in p.steps.enumerated() {
                    b.append(.paragraph(PdfParagraph("\(i + 1). \(st.done ? "[x]" : "[ ]") \(st.title)", style: .bullet)))
                }
            }
        }
        if !taskIds.isEmpty {
            b.append(.paragraph(PdfParagraph("Linked Tasks (\(taskIds.count))", style: .h2)))              // raw count
            for id in taskIds {
                guard let e = lookup.find(id), e.kind == .task else { continue }
                if e.isGated {                                                // DECISIONS 11 Q6: name only
                    b.append(.paragraph(PdfParagraph(style: .bullet, inlines: PdfText.inlines(e.name, .bold))))
                } else if let t = e.task {
                    b += taskSummary(t)
                }
            }
        }
        return b
    }

    // MARK: PDF-040

    static func taskSummary(_ t: PdfTaskSnapshot) -> [PdfBlock] {
        var inl = PdfText.inlines(t.isComplete ? "[x] " : "[ ] ", .bold)
        inl += PdfText.inlines(t.name, .bold)
        inl += metaInlines(meta(t))
        var b: [PdfBlock] = [.paragraph(PdfParagraph(style: .bullet, inlines: inl))]
        if !NetText.isBlank(t.description) {
            var d = PdfParagraph(t.description, style: .muted)
            d.format.leftIndent = 0.6
            b.append(.paragraph(d))
        }
        return b
    }

    // MARK: PDF-038 / PDF-039

    static func taskSpecifics(_ t: PdfTaskSnapshot) -> [PdfBlock] {
        var b: [PdfBlock] = [.paragraph(PdfParagraph("Task Details", style: .h1))]
        var kv = PdfTable(columns: [4, 12], borders: nil, padding: .migraDocDefault)
        func add(_ key: String, _ value: String) {
            let keyFormat = PdfParagraphFormat(font: PdfCharFormat(bold: true, color: PdfColor(80, 80, 80)))
            kv.rows.append(PdfRow(cells: [PdfCell(key, format: keyFormat), PdfCell(value)]))
        }
        if let s = t.rangeStart, let d = t.deadline, s < d { add("Working range", "\(s.iso) \u{2192} \(d.iso)") }
        add("Deadline", t.deadline?.iso ?? "(none)")
        add("Recurrence", t.recurrence.name)
        add("Status", t.isComplete ? "Completed" : "Open")
        b.append(.table(kv))
        if !t.subtasks.isEmpty {
            b.append(.paragraph(PdfParagraph("Subtasks (\(t.subtasks.count))", style: .h2)))
            for st in t.subtasks { b += subtaskDetailed(st, depth: 1) }
        }
        return b
    }

    /// `min(depth, 4) × 0.6` cm (PDF-039).
    public static func subtaskIndent(depth: Int) -> Double { Double(min(depth, 4)) * 0.6 }

    static func subtaskDetailed(_ t: PdfTaskSnapshot, depth: Int) -> [PdfBlock] {
        let indent = subtaskIndent(depth: depth)
        var head = PdfParagraph(style: .normal, format: PdfParagraphFormat(
            leftIndent: indent, spaceBefore: depth == 1 ? 6 : 3, spaceAfter: 2, keepWithNext: true))
        head.inlines = PdfText.inlines(t.isComplete ? "[x] " : "[ ] ", .bold) + PdfText.inlines(t.name, .bold)
            + metaInlines(meta(t))
        var b: [PdfBlock] = [.paragraph(head)]
        if !NetText.isBlank(t.description) {
            var d = PdfParagraph(t.description, style: .muted)
            d.format.leftIndent = indent
            b.append(.paragraph(d))
        }
        b += PdfRichText.body(t.container.xaml, heading: "", leftIndentCm: indent)
        for c in t.subtasks { b += subtaskDetailed(c, depth: depth + 1) }
        return b
    }

    // MARK: PDF-042

    static func procedureSpecifics(_ steps: [PdfStepSnapshot], lookup: PdfLookup) -> [PdfBlock] {
        guard !steps.isEmpty else { return [] }
        var b: [PdfBlock] = [.paragraph(PdfParagraph("Checklist (\(steps.count) step\(steps.count == 1 ? "" : "s"))",
                                                     style: .h1))]
        for (i, s) in steps.enumerated() {
            var head = PdfParagraph(style: .normal, format: PdfParagraphFormat(spaceBefore: 6, spaceAfter: 2,
                                                                               keepWithNext: true))
            head.inlines = PdfText.inlines("\(i + 1). \(s.done ? "[x]" : "[ ]") ",
                                           PdfCharFormat(bold: true, color: s.done ? PdfColor(0, 120, 0) : PdfColor(100, 100, 100)))
            head.inlines += PdfText.inlines(s.title, .bold)
            if let d = s.deadline {
                head.inlines += PdfText.inlines("   (due \(d.iso))", PdfCharFormat(italic: true, color: PdfColor(100, 100, 100)))
            }
            b.append(.paragraph(head))
            if !s.equipmentIds.isEmpty {
                b.append(.paragraph(namesLine("Equipment/Area: ", s.equipmentIds.compactMap { lookup.find($0)?.name })))
            }
            if !s.taskIds.isEmpty {
                b.append(.paragraph(namesLine("Tasks: ", s.taskIds.compactMap { lookup.find($0)?.name })))
            }
            b += PdfRichText.body(s.container.xaml, heading: "", leftIndentCm: 0.6)
        }
        return b
    }

    static func namesLine(_ label: String, _ names: [String]) -> PdfParagraph {
        var p = PdfParagraph(style: .muted, inlines: PdfText.inlines(label, .italic) + PdfText.inlines(names.joined(separator: ", ")))
        p.format.leftIndent = 0.6
        return p
    }

    // MARK: PDF-044

    static func relationships(_ related: [PdfIndexEntry]) -> [PdfBlock] {
        guard !related.isEmpty else { return [] }
        var b: [PdfBlock] = [.paragraph(PdfParagraph("Relationships (\(related.count))", style: .h1)),
                             .paragraph(PdfParagraph("Items linked to this one, grouped by tab.", style: .bodyItalic))]
        for kind in [ItemKind.equipment, .task, .procedure, .vessel] {
            let group = related.enumerated().filter { $0.element.kind == kind }
                .sorted { a, c in
                    let r = NetText.compareIgnoreCase(a.element.name, c.element.name)
                    return r == .orderedSame ? a.offset < c.offset : r == .orderedAscending
                }
                .map(\.element)
            guard !group.isEmpty else { continue }
            b.append(.paragraph(PdfParagraph("\(kindLabel(kind)) (\(group.count))", style: .h2)))
            for r in group {
                var inl = PdfText.inlines(r.name, .bold)
                if !r.isGated && !NetText.isBlank(r.description) {           // DECISIONS 11 Q6
                    inl += PdfText.inlines(" \u{2014} ") + PdfText.inlines(shorten(r.description, 180))
                }
                b.append(.paragraph(PdfParagraph(style: .bullet, inlines: inl)))
            }
        }
        return b
    }

    // MARK: PDF-045

    static func fileBank(_ files: [PdfFileSnapshot]) -> [PdfBlock] {
        guard !files.isEmpty else { return [] }
        let bold = PdfParagraphFormat(font: .bold)
        var t = PdfTable(columns: [5, 2, 9], borders: PdfBorder(width: 0.5, color: PdfColor(200, 200, 200)),
                         padding: PdfPadding(left: 3, right: 3, top: 2, bottom: 2))
        t.rows.append(PdfRow(headingFormat: true, shading: .tableHeader, cells: [
            PdfCell("Name", format: bold), PdfCell("Kind", format: bold), PdfCell("Path / Link", format: bold)]))
        for f in files {
            t.rows.append(PdfRow(cells: [PdfCell(f.name), PdfCell(f.kind.name),
                                         PdfCell(f.path, format: PdfParagraphFormat(font: PdfCharFormat(size: 9)))]))
        }
        return [.paragraph(PdfParagraph("Attached Files (\(files.count))", style: .h1)), .table(t)]
    }
}
