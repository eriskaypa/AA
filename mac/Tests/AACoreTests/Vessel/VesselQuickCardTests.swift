// TV: 10 §7.14 (quick cards), §4.6–4.7 (icon set, palette, readable foreground), §3.1.3, 03 SHELL-157 / App. C.
import Foundation
import Testing
@testable import AACore

@Suite("W-VESSEL — Maritime icons and palette")
struct VesselMaritimeIconsTests {
    // TV: 10 §4.6
    @Test func iconSetOrderAndCodePoints() {
        #expect(MaritimeIcons.all.count == 50)
        #expect(MaritimeIcons.all.first == MaritimeIcons.Icon(glyph: "⚓", name: "Anchor"))
        #expect(MaritimeIcons.all.last == MaritimeIcons.Icon(glyph: "⭐", name: "Favourite"))
        let ferry = MaritimeIcons.all[2]
        #expect(ferry.name == "Ferry")
        #expect(ferry.glyph.unicodeScalars.map(\.value) == [0x26F4, 0xFE0F])
        let crew = MaritimeIcons.all[44]
        #expect(crew.name == "Crew")
        #expect(crew.glyph.unicodeScalars.map(\.value) == [0x1F9D1, 0x200D, 0x2708, 0xFE0F])
        // #48 deliberately repeats #8's glyph.
        #expect(MaritimeIcons.all[47].name == "Navigation")
        #expect(MaritimeIcons.all[47].glyph == MaritimeIcons.all[7].glyph)
        #expect(MaritimeIcons.defaultIcon.unicodeScalars.map(\.value) == [0x2693])
        let names = MaritimeIcons.all.map(\.name)
        #expect(names[10...14] == ["Engine", "Wrench", "Tools", "Toolbox", "Fasteners"])
        #expect(names[38...43] == ["Medical", "Lab/Test", "Hook/Crane", "Link", "Door/Hatch", "Bridge"])
    }

    // TV: 10 §4.7
    @Test func paletteAndReadableForeground() {
        #expect(MaritimeIcons.palette.count == 20)
        #expect(MaritimeIcons.palette.first == "#FF1E88E5")
        #expect(MaritimeIcons.palette.last == "#FFFFFFFF")
        let darkText: Set<String> = ["#FFFDD835", "#FFFB8C00", "#FF9E9E9E", "#FFEEEEEE", "#FFFFFFFF"]
        for hex in MaritimeIcons.palette {
            let dark = MaritimeIcons.readableForegroundIsDark(MaritimeIcons.parseColor(hex))
            #expect(dark == darkText.contains(hex), "\(hex)")
        }
        // l = 0.587 → white; 0.6166 → dark.
        #expect(!MaritimeIcons.readableForegroundIsDark(MaritimeIcons.parseColor("#FF7CB342")))
        #expect(MaritimeIcons.readableForegroundIsDark(MaritimeIcons.parseColor("#FFFB8C00")))
        #expect(MaritimeIcons.readableForeground(MaritimeIcons.parseColor("#FFFB8C00")) == ARGB(a: 255, r: 0x1A, g: 0x1A, b: 0x1A))
        // Alpha is ignored.
        #expect(MaritimeIcons.readableForegroundIsDark(ARGB(a: 0, r: 255, g: 255, b: 255)))
    }

    // TV: 10 §7.14 ParseColor
    @Test func parseColorVectors() {
        #expect(MaritimeIcons.parseColor("") == ARGB(a: 0xFF, r: 0x1E, g: 0x88, b: 0xE5))
        #expect(MaritimeIcons.parseColor(nil) == ARGB(a: 0xFF, r: 0x1E, g: 0x88, b: 0xE5))
        #expect(MaritimeIcons.parseColor("   ") == ARGB(a: 0xFF, r: 0x1E, g: 0x88, b: 0xE5))
        #expect(MaritimeIcons.parseColor("#1AF") == ARGB(a: 0xFF, r: 0x11, g: 0xAA, b: 0xFF))
        #expect(MaritimeIcons.parseColor("#80FF0000") == ARGB(a: 0x80, r: 0xFF, g: 0, b: 0))
        #expect(MaritimeIcons.parseColor("Red") == ARGB(a: 0xFF, r: 0xFF, g: 0, b: 0))
        #expect(MaritimeIcons.parseColor("bogus") == ARGB(a: 0xFF, r: 0x1E, g: 0x88, b: 0xE5))
        #expect(MaritimeIcons.parseColor("#8F00") == ARGB(a: 0x88, r: 0xFF, g: 0, b: 0))
        #expect(MaritimeIcons.parseColor("#123456") == ARGB(a: 0xFF, r: 0x12, g: 0x34, b: 0x56))
    }

    @Test func iconNames() {
        #expect(MaritimeIcons.name(of: "🚢") == "Ship")
        #expect(MaritimeIcons.name(of: "🧭") == "Compass")
        #expect(MaritimeIcons.name(of: "x") == nil)
    }
}

@Suite("W-VESSEL — Quick card rules")
@MainActor struct VesselQuickCardLayoutTests {
    // TV: 10 §7.14 add positions
    @Test func cascadePositions() {
        let expected: [Double] = [24, 52, 80, 108, 136, 164, 24, 52]
        for (n, v) in expected.enumerated() {
            let p = QuickCardLayout.cascadePosition(existingCount: n)
            #expect(p.x == v && p.y == v, "n=\(n)")
        }
        let c = QuickCardLayout.newCard(existingCount: 7)
        #expect(c.x == 52 && c.y == 52 && c.width == 180 && c.height == 120 && c.icon == "⚓" && c.color == "#FF1E88E5")
        #expect(c.title.isEmpty && c.target.isEmpty && !c.isLink && !c.linkInPlace && !c.isFolder)
    }

    // TV: 10 §7.14 icon size
    @Test func iconSizes() {
        #expect(abs(QuickCardLayout.iconSize(width: 180, height: 120) - 43.2) < 1e-9)
        #expect(abs(QuickCardLayout.iconSize(width: 90, height: 64) - 23.04) < 1e-9)
        #expect(QuickCardLayout.iconSize(width: 300, height: 400) == 108)
        #expect(QuickCardLayout.iconSize(width: 200, height: 40) == 18)
    }

    // TV: 10 §7.14 SizeCanvas
    @Test func canvasSize() {
        let one = QuickCardLayout.canvasSize([(x: 900, y: 700, width: 180, height: 120)])
        #expect(one.width == 1120 && one.height == 860)
        let none = QuickCardLayout.canvasSize([])
        #expect(none.width == 1000 && none.height == 640)
        let card = QuickCard()
        card.x = 10; card.y = 10
        let small = QuickCardLayout.canvasSize(cards: [card])
        #expect(small.width == 1000 && small.height == 640)
    }

    // TV: 10 §7.14 drag clamp and resize
    @Test func dragAndResize() {
        let p = QuickCardLayout.dragged(originX: 10, originY: 10, dx: -50, dy: 30)
        #expect(p.x == 0 && p.y == 40)
        let far = QuickCardLayout.dragged(originX: 10, originY: 10, dx: 5000, dy: 9000)
        #expect(far.x == 5010 && far.y == 9010)                       // no upper clamp
        let r = QuickCardLayout.resized(width: 100, height: 70, dx: -30, dy: -30)
        #expect(r.width == 90 && r.height == 64)
        let big = QuickCardLayout.resized(width: 100, height: 70, dx: 2000, dy: 2000)
        #expect(big.width == 2100 && big.height == 2070)               // no maximum on drag
    }

    // TV: 10 §7.14 editor sizes
    @Test func editorSizes() {
        let en = Locale(identifier: "en_US")
        #expect(QuickCardLayout.editorWidth(from: "50", locale: en) == nil)
        #expect(QuickCardLayout.editorWidth(from: "80", locale: en) == 80)
        #expect(QuickCardLayout.editorWidth(from: "1200", locale: en) == 900)
        #expect(QuickCardLayout.editorWidth(from: "abc", locale: en) == nil)
        #expect(QuickCardLayout.editorWidth(from: "", locale: en) == nil)
        #expect(QuickCardLayout.editorWidth(from: "1,000", locale: en) == 900)
        #expect(QuickCardLayout.editorWidth(from: " 123.5 ", locale: en) == 123.5)
        #expect(QuickCardLayout.editorHeight(from: "59", locale: en) == nil)
        #expect(QuickCardLayout.editorHeight(from: "60", locale: en) == 60)
        #expect(QuickCardLayout.editorHeight(from: "800", locale: en) == 700)
        #expect(QuickCardLayout.editorHeight(from: "abc", locale: en) == nil)
        let de = Locale(identifier: "de_DE")
        #expect(QuickCardLayout.editorWidth(from: "123,5", locale: de) == 123.5)
        #expect(QuickCardLayout.editorWidth(from: "123.5", locale: de) == 123.5)   // "." also accepted
        #expect(QuickCardLayout.editorSizeText(180.9) == "180")
        #expect(QuickCardLayout.editorSizeText(64) == "64")
    }

    // TV: 10 §7.14 custom colour
    @Test func customColour() {
        #expect(QuickCardLayout.customColorHex(r: 10, g: 20, b: 255) == "#FF0A14FF")
        #expect(QuickCardLayout.customColorHex(red: 10.0 / 255, green: 20.0 / 255, blue: 1) == "#FF0A14FF")
    }

    // TV: 10 §7.14 tooltip, delete prompt; VESSEL-015 kinds
    @Test func tooltipAndPrompt() {
        #expect(QuickCardLayout.tooltip(title: "", target: "", kind: .importedCopy)
                == "(untitled)\nImported copy: (no target — right-click ▸ Edit)\nDouble-click to open • drag to move • drag corner to resize")
        let c = QuickCard()
        c.title = "PMS"; c.target = "files/0f_a.pdf"
        #expect(QuickCardLayout.tooltip(c) == "PMS\nImported copy: files/0f_a.pdf\nDouble-click to open • drag to move • drag corner to resize")
        c.isLink = true; c.isFolder = true; c.linkInPlace = true
        #expect(QuickCardLayout.kind(of: c) == .webLink)
        c.isLink = false
        #expect(QuickCardLayout.kind(of: c) == .folder)
        c.isFolder = false
        #expect(QuickCardLayout.kind(of: c) == .liveFile)
        #expect(QuickCardLayout.deletePrompt(title: "  ", icon: "🚢") == "Delete quick card '🚢'?")
        #expect(QuickCardLayout.deletePrompt(title: "Manuals", icon: "🚢") == "Delete quick card 'Manuals'?")
        #expect(QuickCardLayout.targetTypeLabel(target: "", kind: .webLink) == "")
        #expect(QuickCardLayout.targetTypeLabel(target: "https://a", kind: .webLink) == "Web link")
        #expect(QuickCardLayout.targetDisplay("") == "(none — pick a file, folder, or web link)")
        #expect(QuickCardLayout.previewTitle(" ") == "(untitled)")
    }

    // TV: 10 §3.1.11 flag table
    @Test func targetFlags() {
        let c = QuickCard()
        QuickCardLayout.setTarget(c, "/Volumes/ships/Manual.pdf", kind: .liveFile)
        #expect(!c.isLink && c.linkInPlace && !c.isFolder)
        QuickCardLayout.setTarget(c, "files/0123_x.pdf", kind: .importedCopy)
        #expect(!c.isLink && !c.linkInPlace && !c.isFolder && c.target == "files/0123_x.pdf")
        QuickCardLayout.setTarget(c, "/Volumes/ships", kind: .folder)
        #expect(!c.isLink && c.linkInPlace && c.isFolder)
        QuickCardLayout.setTarget(c, "https://", kind: .webLink)
        #expect(c.isLink && !c.linkInPlace && !c.isFolder)
    }

    // TV: 10 VESSEL-047 title auto-fill
    @Test func titleAutoFill() {
        #expect(QuickCardLayout.titleForFile(URL(fileURLWithPath: "/Users/x/Manual v2.pdf")) == "Manual v2")
        #expect(QuickCardLayout.titleForFile(URL(fileURLWithPath: "/Users/x/archive.tar.gz")) == "archive.tar")
        #expect(QuickCardLayout.titleForFile(URL(fileURLWithPath: "/Users/x/README")) == "README")
        #expect(QuickCardLayout.titleForFolder(URL(fileURLWithPath: "/Volumes/ships/Drawings", isDirectory: true)) == "Drawings")
        #expect(QuickCardLayout.titleForFolder(URL(fileURLWithPath: "/", isDirectory: true)) == "/")
    }

    // TV: 10 VESSEL-023 duplicate
    @Test func duplicateKeepsTargetNewIdOffset() {
        let c = QuickCard()
        c.title = "Docs"; c.target = "files/abc_x.pdf"; c.x = 100; c.y = 40; c.icon = "🚢"; c.color = "#FF43A047"
        let d = QuickCardLayout.duplicate(c)
        #expect(d.id != c.id)
        #expect(d.x == 124 && d.y == 64)
        #expect(d.target == c.target && d.title == "Docs" && d.icon == "🚢" && d.color == "#FF43A047")
    }

    // TV: 10 §7.14 safe file name
    @Test func safeFileNames() {
        #expect(VesselText.workOrdersExportName("BW Pavilion: Aranda?") == "WorkOrders-BW Pavilion_ Aranda_.xlsx")
        #expect(VesselText.portsExportName("BW Pavilion: Aranda?") == "Ports-BW Pavilion_ Aranda_.xlsx")
        #expect(VesselText.safeFileName(nil) == "vessel")
        #expect(VesselText.safeFileName("a/b\\c|d\"e<f>g*h\u{1}") == "a_b_c_d_e_f_g_h_")
        #expect(VesselText.safeFileName(" spaced ") == " spaced ")
    }
}

@Suite("W-VESSEL — JSON round trip of vessel records")
@MainActor struct VesselJSONTests {
    // TV: 10 §7.15
    @Test func windowsFragmentRoundTrips() throws {
        let fragment = ##"{"QuickCards":[{"Id":"0b6e0000-0000-4000-8000-0000000000aa","Title":"PMS","Target":"files/0f00000000000000000000000000000a_a.pdf","IsLink":false,"LinkInPlace":false,"IsFolder":false,"Icon":"\u2693","Color":"#FF1E88E5","X":24,"Y":24,"Width":180,"Height":120}],"Jobs":[],"NotificationsEnabled":true,"PortCalls":[],"Id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","Name":"V"}"##
        let obj = try JSONParser.parse(fragment).objectValue!
        let v = try Vessel(json: obj, context: JSONDecodeContext())
        #expect(v.quickCards.count == 1)
        #expect(v.quickCards[0].icon.unicodeScalars.map(\.value) == [0x2693])
        let out = try JSONWriter.string(.object(v.toJSON()))
        #expect(out.contains(#""Icon":"\u2693""#))
        #expect(out.contains(#""X":24,"Y":24,"Width":180,"Height":120"#))
        #expect(out.contains("3f2504e0-4f89-11d3-9a0c-0305e82c3301"))
        #expect(!out.contains("3F2504E0"))
    }

    // TV: 10 §7.15 defaults
    @Test func legacyDefaults() throws {
        let v = try Vessel(json: try JSONParser.parse(#"{"Name":"Old","QuickCards":[{"Title":"x"}]}"#).objectValue!,
                           context: JSONDecodeContext())
        #expect(v.notificationsEnabled)
        #expect(v.quickCards[0].icon == "⚓" && v.quickCards[0].color == "#FF1E88E5" && v.quickCards[0].width == 180)
        let visit = try PortVisit(json: try JSONParser.parse(#"{"VesselName":"A","ArrivalDate":"2026-07-15"}"#).objectValue!,
                                  context: JSONDecodeContext())
        #expect(visit.vesselId == nil)
        #expect(!(try JSONWriter.string(.object(visit.toJSON()))).contains("VesselId"))
        let job = ShipJob(jobNo: "ARA.1")
        job.overdueDays = 5
        let jobText = try JSONWriter.string(.object(job.toJSON()))
        #expect(jobText.contains(#""OverdueDays":5,"#))
        #expect(!jobText.contains("5.0"))
    }
}
