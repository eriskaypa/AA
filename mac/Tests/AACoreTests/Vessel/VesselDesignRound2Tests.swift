// TV: Stage V round 2 (FIX2-W-VESSEL) — VESSEL-253 visits columns (Vessel 220, wrapped), design rule 11 (the Quick
//     Cards header hint wraps, never truncated) and rule 17 (no legacy scroller corner square in the Quick Cards
//     canvas). The AA target is not linked into the tests, so the view wiring is pinned by reading the view source.
import AppKit
import Foundation
import Testing
@testable import AACore

@Suite("W-VESSEL — round-2 design regressions")
@MainActor struct VesselDesignRound2Tests {
    static var macRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()      // Vessel
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()   // mac/
    }

    static func source(_ rel: String) throws -> String {
        try String(contentsOf: macRoot.appending(path: rel), encoding: .utf8)
    }

    /// The text of the declaration that starts at `marker`, up to the next top-level `struct` / `enum` / `extension`.
    static func block(_ src: String, from marker: String) -> String {
        guard let start = src.range(of: marker) else { return "" }
        let rest = src[start.upperBound...]
        let ends = ["\nstruct ", "\nenum ", "\n@MainActor enum ", "\nextension ", "\nprivate struct "]
        let end = ends.compactMap { rest.range(of: $0)?.lowerBound }.min() ?? rest.endIndex
        return String(rest[..<end])
    }

    // VESSEL-253: Vessel wrapped, then Arrival / Departure / Imported; the four ideals fit the visits pane of the
    // default 1280-pt window (a 220 + 3 × 140 layout pushed `Imported` past the pane edge in the snapshot).
    @Test func visitsColumnsFollowSpec() {
        let c = PortsAnalysis.visitsColumns
        #expect(c.map(\.title) == ["Vessel", "Arrival", "Departure", "Imported"])
        #expect(c.map(\.idealWidth) == [110, 130, 130, 126])
        #expect(c.map(\.wraps) == [true, false, false, false])
        #expect(c.allSatisfy { $0.minWidth <= $0.idealWidth })
        #expect(c.reduce(0) { $0 + $1.idealWidth } <= PortsAnalysis.visitsColumnsBudget)
    }

    // Design rule 5: a column's ideal width is at least its header text width in the header font.
    @Test func visitsColumnIdealsFitHeaders() {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        for col in PortsAnalysis.visitsColumns {
            let w = (col.title as NSString).size(withAttributes: [.font: font]).width + 16    // cell padding
            #expect(Double(w) <= col.minWidth, "\(col.title) header needs \(w) pt")
        }
    }

    // V2-J5 journey: Ports Database, port Bonny — the Vessel cell showed `BW Pavilion…` (one line, tail-truncated).
    // The view must use the shared column widths and let the vessel name wrap.
    @Test func visitsTableWrapsVesselName() throws {
        let src = try Self.source("Sources/AA/Vessel/PortsDatabaseTabView.swift")
        let table = Self.block(src, from: "struct PortsDatabaseVisitsTable")
        #expect(table.contains("PortsAnalysis.visitsColumns"))
        #expect(table.contains("ideal: c[0].idealWidth"))
        #expect(!table.contains(".width(min: 100)\n"))
        let vesselCell = table.components(separatedBy: "TableColumn(c[1].title)").first ?? ""
        #expect(vesselCell.contains("r.visit.vesselName"))
        #expect(vesselCell.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(!vesselCell.contains(".lineLimit(1)"))
    }

    // Design rule 11: the header hint (a required string) wraps; it is never cut with `lineLimit(1)` / tail truncation.
    @Test func quickCardsHeaderHintWraps() throws {
        let src = try Self.source("Sources/AA/Vessel/QuickCardsPanel.swift")
        let header = Self.block(src, from: "private var header: some View")
            .components(separatedBy: "// MARK: Canvas").first ?? ""
        #expect(header.contains("AAHelpText(QuickCardLayout.headerHint)"))
        #expect(!header.contains(".lineLimit(1)"))
        #expect(!header.contains(".truncationMode(.tail)"))
    }

    // Design rule 17: the two-axis canvas hides its scrollers (`.never` also overrides "Show scroll bars: Always"),
    // so NSScrollView draws no corner square inside the rounded border.
    @Test func quickCardsCanvasHasNoScrollers() throws {
        #expect(QuickCardLayout.canvasShowsScrollers == false)
        let src = try Self.source("Sources/AA/Vessel/QuickCardsPanel.swift")
        let canvas = Self.block(src, from: "private var canvasArea: some View")
        #expect(canvas.contains("ScrollView([.horizontal, .vertical])"))
        #expect(canvas.contains(".scrollIndicators(QuickCardLayout.canvasShowsScrollers ? .automatic : .never)"))
    }
}
