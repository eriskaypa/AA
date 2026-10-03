// Tests for 14 §7.3 (Folder builder Parse vectors and create outcomes), TOOLS-043…050, Q-15, Q-17.
import Foundation
import Testing
@testable import AACore

@Suite struct ToolFolderPlanTests {
    /// Flattens the tree to `A▸{B▸C, D}`-style text for compact assertions.
    private func shape(_ nodes: [ToolFolderNode]) -> String {
        nodes.map { n in
            guard let kids = n.children else { return n.name }
            return kids.count == 1 ? "\(n.name)▸\(shape(kids))" : "\(n.name)▸{\(shape(kids))}"
        }.joined(separator: ", ")
    }

    // TV: 14 §7.3 Parse table
    @Test func exampleText() {
        let p = ToolFolderPlan.parse(ToolFolderPlan.exampleText)
        #expect(shape(p.roots) == "Project A▸{Documents, Images, Reports▸2026}, Project B▸Drawings, Shared▸Templates")
        #expect(p.rels == ["Project A", "Project A/Documents", "Project A/Images", "Project A/Reports",
                           "Project A/Reports/2026", "Project B", "Project B/Drawings", "Shared", "Shared/Templates"])
        #expect(p.header == "Preview (9 folders)")
        #expect(ToolFolderPlan.exampleText.hasSuffix("Templates\n"))
    }

    @Test(arguments: [
        ("A\n  B\n    C\n   D\n E\n", "A▸{B▸C, D}, E", ["A", "A/B", "A/B/C", "A/D", "E"]),
        ("\t\tDeep\n\t\t\tDeeper\nTop\n\t\t\tJump", "Deep▸Deeper, Top▸Jump", ["Deep", "Deep/Deeper", "Top", "Top/Jump"]),
        ("Bad:Name?\nTrail. . \n..\n.\n a / b \\ c \nx//y", "Bad_Name_, Trail, a▸b▸c, x▸y",
         ["Bad_Name_", "Trail", "a", "a/b", "a/b/c", "x", "x/y"]),
        ("Docs\ndocs/Sub\nDOCS\n\tInner", "Docs▸{Sub, Inner}", ["Docs", "docs/Sub", "DOCS/Inner"]),
        ("Shared/Templates\n\tX\n\t\tY", "Shared▸Templates▸X▸Y",
         ["Shared", "Shared/Templates", "Shared/Templates/X", "Shared/Templates/X/Y"]),
        ("R\n\t  M\n", "R▸M", ["R", "R/M"]),
        ("", "", []),
        ("\n\n  \n", "", []),
        ("One", "One", ["One"]),
        ("a\r\nb", "a, b", ["a", "b"]),
    ])
    func parseVectors(input: String, tree: String, rels: [String]) {
        let p = ToolFolderPlan.parse(input)
        #expect(shape(p.roots) == tree)
        #expect(p.rels == rels)
        #expect(p.count == rels.count)
    }

    @Test func headers() {
        #expect(ToolFolderPlan.parse("").header == "Preview (0 folders)")
        #expect(ToolFolderPlan.parse("One").header == "Preview (1 folder)")
        #expect(ToolFolderPlan.parse(nil).header == "Preview (0 folders)")
    }

    // TV: 14 Q-15 (canonical spelling for creation)
    @Test func canonicalCreationPaths() {
        let p = ToolFolderPlan.parse("Docs\ndocs/Sub\nDOCS\n\tInner")
        #expect(p.creationPaths == ["Docs", "Docs/Sub", "Docs/Inner"])
    }

    // TV: 14 §3.3.2
    @Test func sanitize() {
        #expect(ToolFolderPlan.sanitize("  a<b>c:d\"e|f?g*h  ") == "a_b_c_d_e_f_g_h")
        #expect(ToolFolderPlan.sanitize("Trail. . ") == "Trail")
        #expect(ToolFolderPlan.sanitize("..") == "")
        #expect(ToolFolderPlan.sanitize("x\u{0001}y") == "x_y")
        #expect(ToolFolderPlan.sanitize("\u{00A0}nb\u{00A0}") == "nb")
        #expect(ToolFolderPlan.sanitize("CON") == "CON")
        #expect(ToolFolderPlan.parse("a\rb").rels == ["a_b"])
        #expect(ToolFolderPlan.parse("\u{00A0}\u{00A0}x").rels == ["x"])
    }

    // TV: 14 §7.3 create outcome vectors
    @Test func createOutcomes() throws {
        let base = TempFolder("aa-folderbuilder")
        let plan = ToolFolderPlan.parse(ToolFolderPlan.exampleText)
        let first = plan.create(under: base.url)
        #expect(first == .init(created: 9, existed: 0, failed: 0))
        #expect(first.statusText == "Created 9, already existed 0.")
        let second = plan.create(under: base.url)
        #expect(second.statusText == "Created 0, already existed 9.")
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: base.url.appending(path: "Project A/Reports/2026").path, isDirectory: &isDir) && isDir.boolValue)

        let other = TempFolder("aa-folderbuilder")
        try other.write("Project B", "a regular file in the way")
        let third = plan.create(under: other.url)
        #expect(third.statusText == "Created 7, already existed 0, failed 2.")
    }

    // TV: TOOLS-049 messages, Q-17
    @Test func messagesAndStoredBase() {
        #expect(ToolFolderPlan.confirmCreate(count: 1, base: "/x") == "Create 1 folder under:\n/x?")
        #expect(ToolFolderPlan.confirmCreate(count: 9, base: "/x") == "Create 9 folders under:\n/x?")
        #expect(ToolFolderPlan.baseMissingQuestion("/x/y") == "The base location does not exist:\n/x/y\n\nCreate it?")
        #expect(ToolFolderPlan.openAfterCreate(created: 3) == "Created 3 folder(s). Open the base location?")
        #expect(ToolFolderPlan.usableStoredBase("D:\\Projects") == "")
        #expect(ToolFolderPlan.usableStoredBase(nil) == "")
        #expect(ToolFolderPlan.usableStoredBase("/Users/op/Projects") == "/Users/op/Projects")
    }
}
