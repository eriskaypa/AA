// TV: ARCHITECTURE.md §6.1 (ContractStatus registry wiring), §11 (stub behaviour F1 must keep "correct enough":
//     NetDateParser = the three exact formats, XamlPlainText = regex tag strip, XamlReader = .empty / .unparseable,
//     XamlWriter = "", AttachmentStore.normalizeFilePaths = no-op), 01 §7.10 (ParseDate exact formats via F2's
//     parser). Assertions that only hold for a placeholder are gated on the owner's ContractStatus flag; the rest
//     hold for the stubs and the real implementations alike.
import Foundation
import Testing
@testable import AACore

@Suite struct FoundationContractStatusTests {
    @Test func everyOwnerHasAFlagAndTheRegistryReadsIt() {
        let flags: [ContractOwner: Bool] = [
            .wShell: ContractStatus.wShellImplemented, .wPersist: ContractStatus.wPersistImplemented,
            .wRich: ContractStatus.wRichImplemented, .wCont: ContractStatus.wContImplemented,
            .wFiles: ContractStatus.wFilesImplemented, .wHier: ContractStatus.wHierImplemented,
            .wBuild: ContractStatus.wBuildImplemented, .wPlan: ContractStatus.wPlanImplemented,
            .wQuick: ContractStatus.wQuickImplemented, .wCrew: ContractStatus.wCrewImplemented,
            .wVessel: ContractStatus.wVesselImplemented, .wPdf: ContractStatus.wPdfImplemented,
            .wSire: ContractStatus.wSireImplemented, .wFlash: ContractStatus.wFlashImplemented,
            .wDrive: ContractStatus.wDriveImplemented,
        ]
        #expect(ContractOwner.allCases.count == 15)
        #expect(Set(flags.keys) == Set(ContractOwner.allCases))
        for owner in ContractOwner.allCases {
            #expect(ContractStatus.isImplemented(owner) == flags[owner], "\(owner)")
        }
    }
}

@Suite struct FoundationSharedParserContractTests {
    // TV: 01 §7.10 / 09 §7.1 — the exact-format rows hold for the F1 stub and for F2's full parser.
    @Test func netDateParserExactFormats() {
        for s in ["2026-03-04", "2026/03/04", "2026.03.04", "  2026-03-04\t"] {
            let d = NetDateParser.parse(s)
            #expect(d?.civilDate == CivilDate(year: 2026, month: 3, day: 4) && d?.kind == .unspecified, "\(s)")
            #expect(d?.minutesOfDay == 0, "\(s)")
        }
        #expect(NetDateParser.parse(nil) == nil)
        #expect(NetDateParser.parse("") == nil && NetDateParser.parse(" \t ") == nil)
        #expect(NetDateParser.parse("2026-02-30") == nil)
    }

    // The F1 model helpers forward to the shared parser (ARCHITECTURE.md §6.5): same answer for every input.
    @Test func crewMemberParseDateForwardsToTheSharedParser() {
        for s in ["2026-03-04", "2026/03/04", "03/04/2026", "12 Mar 2026", "abc", "", "  ", "2026-02-30"] {
            #expect(CrewMember.parseDate(s) == NetDateParser.parse(s), "\(s)")
        }
        #expect(CrewMember.parseDate(nil) == nil)
    }

    // ARCH §11: XamlPlainText stub = regex tag strip (F2's real search text keeps the same visible text).
    @Test func xamlPlainTextStripsTags() {
        let xaml = #"<Section xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><Paragraph><Run>Check oil</Run></Paragraph><Paragraph><Run>A &amp; B</Run></Paragraph></Section>"#
        let search = XamlPlainText.searchText(xaml)
        #expect(search.contains("Check oil") && !search.contains("<") && !search.contains(">"))
        #expect(XamlPlainText.diffText(xaml) == "Check oil A & B")
        #expect(XamlPlainText.searchText("") == "" && XamlPlainText.diffText("") == "")
    }
}

@MainActor @Suite struct FoundationPlaceholderSafetyTests {
    // ARCH §6.7 / §11: an editor built against the placeholder reader can never blank a note.
    @Test(.enabled(if: !ContractStatus.isImplemented(.wRich)))
    func placeholderReaderNeverReturnsEmptyForContent() {
        let xaml = "<Section><Paragraph><Run>Keep me</Run></Paragraph></Section>"
        switch XamlReader.read(xaml, context: .containerEditor) {
        case .unparseable(let raw): #expect(raw == xaml)
        default: Issue.record("the placeholder reader must return .unparseable for non-empty input")
        }
        switch XamlReader.read("", context: .containerEditor) {
        case .empty(let metadata):
            #expect(metadata.isPlaceholderResult)
            #expect(metadata.context == .containerEditor)
        default: Issue.record("the placeholder reader must return .empty for \"\"")
        }
        #expect(XamlWriter.write(NSAttributedString(string: "x"), metadata: RichTextMetadata(context: .pdf),
                                 context: .pdf) == "")
        #expect(XamlWriter.emptyDocument() == "")
    }

    // ARCH §11: while W-PERSIST is a placeholder, load/save leave every stored attachment path untouched.
    @Test(.enabled(if: !ContractStatus.isImplemented(.wPersist)))
    func placeholderPathNormalisationIsANoOp() throws {
        let data = AppData()
        let item = Equipment(name: "Pump")
        let stored = #"C:\Users\x\AppData\Local\AA\files\0123456789abcdef0123456789abcdef_manual.pdf"#
        item.container.files = [FileItem(name: "manual.pdf", path: stored)]
        data.equipment = [item]
        let made = StoreFactory.make(data: data)
        let bytes = try made.dataStore.serializeForSave(data)
        #expect(data.equipment[0].container.files[0].path == stored)
        try made.folder.write("copy.data-json.json", bytes)
        let loaded = try made.dataStore.loadFrom(made.folder.file("copy.data-json.json"))
        #expect(loaded.equipment.first?.container.files.first?.path == stored)
    }

    @Test func richTextContextsMatchXD25() {
        #expect(XamlContext.containerEditor == XamlContext.containerViewer)
        #expect(XamlContext.containerEditor.fontFamily == "Consolas" && XamlContext.containerEditor.fontSize == 14)
        #expect(XamlContext.containerEditor.foreground == 0xFF1A_1A1A && XamlContext.pdf.foreground == 0xFF00_0000)
        #expect(XamlContext.pdf.fontFamily == "Segoe UI" && XamlContext.pdf.fontSize == 12)
        #expect(XamlContext.sirePane.fontSize == 13 && XamlContext.sirePane.lineHeight.isNaN)
        #expect(XamlFontFamily(raw: " Consolas , ,Segoe UI ").canon == "consolas,segoe ui")
        #expect(LockRules.sentinel == ARGB(a: 0xFF, r: 0xFF, g: 0xE6, b: 0x99))
    }
}
