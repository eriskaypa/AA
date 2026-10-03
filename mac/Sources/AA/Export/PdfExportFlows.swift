// PLACEHOLDER(W-PDF) — contract: ARCHITECTURE.md §7.7
// Spec: 11 (PDF & checklist export). Compiling stub created by F3; W-PDF replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

enum SavedListsExportScope { case list(UUID), group(ofList: UUID), all }

@MainActor enum PdfExportFlows {
    static func exportItem(itemID: UUID, env: AppEnvironment, dialogs: DialogPresenter) async {
        // PLACEHOLDER(W-PDF)
    }

    static func printItem(itemID: UUID, env: AppEnvironment, dialogs: DialogPresenter) async {
        // PLACEHOLDER(W-PDF)
    }

    static func exportChecklistPDF(procedureID: UUID, env: AppEnvironment, dialogs: DialogPresenter) async {
        // PLACEHOLDER(W-PDF)
    }

    static func exportChecklistXLSX(procedureID: UUID, env: AppEnvironment, dialogs: DialogPresenter) async {
        // PLACEHOLDER(W-PDF)
    }

    static func exportSavedLists(_ scope: SavedListsExportScope, env: AppEnvironment, dialogs: DialogPresenter) async {
        // PLACEHOLDER(W-PDF)
    }
}
