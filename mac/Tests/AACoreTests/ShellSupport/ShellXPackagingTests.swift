// TV: 03 BD.4.1 (Info.plist template: required values, UTF-8 camera text with ▸, document types, exported UTIs incl.
//     the in-app drag types of ARCH §9.4), SHELL-182 (keys that must be absent), BD.4.2 (exactly one entitlement),
//     BD.4.3 (sandbox profile is reference only), BD.4.6 (portable launcher), BD.7.3 (AA.ico copy checksum), BD.3.11
//     (VERSION), SHELL-202 (build-app.sh exists, is executable and strict). Reads the package tree beside the tests.
import Foundation
import CryptoKit
import Testing
@testable import AACore

@Suite struct ShellXPackagingTests {
    /// `mac/` (this file is `mac/Tests/AACoreTests/ShellSupport/ShellXPackagingTests.swift`).
    private static let macRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func file(_ relative: String) -> URL { macRoot.appending(path: relative) }

    private static func plist(_ relative: String) throws -> [String: Any] {
        let data = try Data(contentsOf: file(relative))
        guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return dict
    }

    @Test func infoPlistTemplateValues() throws {
        let p = try Self.plist("Packaging/Info.plist")
        #expect(p["CFBundleIdentifier"] as? String == Identifiers.bundleID)
        #expect(p["CFBundleExecutable"] as? String == "AA")
        #expect(p["CFBundleName"] as? String == "AA" && p["CFBundleDisplayName"] as? String == "AA")
        #expect(p["CFBundlePackageType"] as? String == "APPL" && p["CFBundleSignature"] as? String == "????")
        #expect(p["CFBundleShortVersionString"] as? String == "@VERSION@")
        #expect(p["CFBundleVersion"] as? String == "@BUILD@")
        #expect(p["AABuildDate"] as? String == "@BUILDDATE@" && p["AAGitCommit"] as? String == "@GITCOMMIT@")
        #expect(p["CFBundleIconFile"] as? String == "AppIcon")
        #expect(p["LSMinimumSystemVersion"] as? String == "26.0")
        #expect(p["LSApplicationCategoryType"] as? String == "public.app-category.productivity")
        #expect(p["NSPrincipalClass"] as? String == "NSApplication")
        #expect(p["NSHighResolutionCapable"] as? Bool == true)
        #expect(p["NSSupportsAutomaticTermination"] as? Bool == false)
        #expect(p["NSSupportsSuddenTermination"] as? Bool == false)
        #expect(p["NSHumanReadableCopyright"] as? String == ShellXVersionInfo.credits)
        #expect(p["NSCameraUsageDescription"] as? String
                == "AA uses the camera only during Flash Sync \u{25B8} Receive, to read the QR codes your iPhone shows on its screen. Video is never recorded, saved or sent anywhere.")
        #expect(p["NSCameraUseContinuityCameraDeviceType"] as? Bool == true)
        for key in ["NSDesktopFolderUsageDescription", "NSDocumentsFolderUsageDescription",
                    "NSDownloadsFolderUsageDescription", "NSRemovableVolumesUsageDescription",
                    "NSNetworkVolumesUsageDescription", "NSFileProviderDomainUsageDescription"] {
            #expect((p[key] as? String)?.hasPrefix("AA ") == true, "\(key)")
        }
    }

    @Test func forbiddenKeysAreAbsent() throws {
        let p = try Self.plist("Packaging/Info.plist")
        for key in ["LSUIElement", "LSBackgroundOnly", "NSRequiresAquaSystemAppearance", "CFBundleURLTypes",
                    "LSMultipleInstancesProhibited", "NSMicrophoneUsageDescription", "NSAppTransportSecurity",
                    "NSAppSleepDisabled", "NSLocalNetworkUsageDescription", "LSEnvironment", "ATSApplicationFontsPath",
                    "CFBundleIconName"] {
            #expect(p[key] == nil, "\(key) must be absent")
        }
    }

    @Test func documentAndExportedTypes() throws {
        let p = try Self.plist("Packaging/Info.plist")
        let docs = try #require(p["CFBundleDocumentTypes"] as? [[String: Any]])
        #expect(docs.count == 2)
        #expect(docs[0]["LSItemContentTypes"] as? [String] == [Identifiers.utBundle])
        #expect(docs[0]["LSHandlerRank"] as? String == "Owner" && docs[0]["CFBundleTypeRole"] as? String == "Viewer")
        #expect(docs[1]["LSItemContentTypes"] as? [String] == ["public.zip-archive"])
        #expect(docs[1]["LSHandlerRank"] as? String == "Alternate")
        let exported = try #require(p["UTExportedTypeDeclarations"] as? [[String: Any]])
        let ids = exported.compactMap { $0["UTTypeIdentifier"] as? String }
        #expect(ids.first == Identifiers.utBundle)                        // BD.7.4 checks index 0
        #expect(Set(ids) == [Identifiers.utBundle, Identifiers.utSchedule, Identifiers.utXaml, Identifiers.utTaskRef,
                             Identifiers.utJobRef, Identifiers.utItemRef])
        let bundle = exported[0]
        #expect(bundle["UTTypeConformsTo"] as? [String] == ["public.zip-archive"])
        let tags = bundle["UTTypeTagSpecification"] as? [String: Any]
        #expect(tags?["public.filename-extension"] as? [String] == ["aaz"])
        let schedule = try #require(exported.first { $0["UTTypeIdentifier"] as? String == Identifiers.utSchedule })
        #expect(schedule["UTTypeConformsTo"] as? [String] == ["public.json"])
        // Never claim public.json or public.zip-archive as owner, and no document type for the schedule (SHELL-186).
        #expect(!ids.contains("public.json") && !ids.contains("public.zip-archive"))
        #expect(!docs.contains { ($0["LSItemContentTypes"] as? [String])?.contains(Identifiers.utSchedule) == true })
    }

    @Test func entitlements() throws {
        let shipped = try Self.plist("Packaging/AA.entitlements")
        #expect(shipped.count == 1 && shipped["com.apple.security.device.camera"] as? Bool == true)
        let reference = try Self.plist("Packaging/AA-sandbox.entitlements")
        #expect(reference["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(reference["com.apple.security.device.camera"] as? Bool == true)
        // build-app.sh signs only with the shipped file.
        let script = try String(contentsOf: Self.file("Scripts/build-app.sh"), encoding: .utf8)
        #expect(script.contains("Packaging/AA.entitlements"))
        #expect(!script.contains("AA-sandbox.entitlements"))
    }

    @Test func buildScriptAndLauncher() throws {
        let fm = FileManager.default
        let script = Self.file("Scripts/build-app.sh")
        #expect(fm.isExecutableFile(atPath: script.path))
        let text = try String(contentsOf: script, encoding: .utf8)
        #expect(text.hasPrefix("#!/bin/bash"))
        #expect(text.contains("set -euo pipefail"))
        #expect(text.contains("--options runtime"))
        #expect(text.contains("ditto -c -k --keepParent"))
        let launcher = Self.file("Packaging/AA (portable).command")
        #expect(fm.isExecutableFile(atPath: launcher.path))
        let lines = try String(contentsOf: launcher, encoding: .utf8)
        #expect(!lines.contains("\r"))
        #expect(lines == """
            #!/bin/sh
            # Start AA with its data in the "AA Data" folder beside this file (portable use, e.g. on a USB stick).
            here="$(cd "$(dirname "$0")" && pwd -P)"
            exec /usr/bin/open -n -a "$here/AA.app" --args --data-dir "$here/AA Data"

            """)
        let install = try String(contentsOf: Self.file("Packaging/Install.txt"), encoding: .utf8)
        #expect(install.contains("Open Anyway") && install.contains("xattr -dr com.apple.quarantine"))
        #expect(install.contains("~/Library/Application Support/AA") && install.contains("--data-dir"))
    }

    @Test func versionFileAndIconSources() throws {
        let version = try String(contentsOf: Self.file("VERSION"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil)
        let ico = try Data(contentsOf: Self.file("Resources/AA.ico"))
        let digest = SHA256.hash(data: ico).map { String(format: "%02x", $0) }.joined()
        #expect(digest == "699efada2d9160395562903ce37aa32acbe4a9a983fb85c585c5469555497f12")   // BD.7.3
        #expect(ico.count == 45_294)
        let png = try Data(contentsOf: Self.file("Resources/AppIcon-1024.png"))
        #expect(png.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        // IHDR width/height = 1024 × 1024.
        let w = png[16..<20].reduce(0) { $0 << 8 | Int($1) }, h = png[20..<24].reduce(0) { $0 << 8 | Int($1) }
        #expect(w == 1024 && h == 1024)
    }
}
