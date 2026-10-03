// Spec: 06 Addendum BUILD-136…150, A22 (TextPromptRequest / Result), 04 HIER-131/132, 07 VIEW-203, VIEW-208…216,
//       03 SHELL-161 (password modes), DECISIONS 01 Q-4, 08 QUICK-190…196 (review request), 03 §6.5 (alert button
//       semantics), 06 §6.2 / OC-55 (OptionalDatePicker); ARCHITECTURE.md §7.5.
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

enum SheetKind { case decision, closeType }

struct TextPromptRequest: Equatable, Sendable {
    var title: String
    var prompt: String
    var initial: String = ""
    var isSecure = false
    var helpText: String? = nil
}

enum TextPromptResult: Equatable, Sendable { case ok(String), cancelled }

struct DatePromptRequest: Equatable {
    var title: String
    var prompt: String
    var initial: NetDateTime?
    var clearTitle = "Clear deadline"
    var clearHelp: String? = "Remove the deadline from every selected item."
    var emptyMessage = "Pick a date, or use \"Clear deadline\" to remove it."
}

/// `ok` carries an `.unspecified` midnight (DECISIONS Q-6).
enum DatePromptResult: Equatable { case ok(NetDateTime), cleared, cancelled }

struct ItemPickerRow<Tag: Hashable & Sendable>: Hashable { var display: String; var tag: Tag }
enum ItemPickerMode { case single, multi }
enum ItemPickerResultOrder { case selection, candidate }

struct ItemPickerRequest<Tag: Hashable & Sendable> {
    var prompt: String
    var rows: [ItemPickerRow<Tag>]
    var preselected: [Tag] = []
    var mode: ItemPickerMode = .multi
    var resultOrder: ItemPickerResultOrder = .selection
}

struct AlertButton {
    var title: String
    var role: AlertButtonRole = .normal
}

enum AlertButtonRole { case normal, `default`, cancel, destructive }

struct AlertSpec {
    var title: String
    var message: String
    var style: NSAlert.Style = .informational
    var buttons: [AlertButton]
    var suppressionKey: MacPreferences.Key? = nil
}

enum PasswordSheetMode { case unlock(prompt: String), setNew, changeExisting }
enum PasswordSheetResult: Equatable { case ok(password: String, current: String?), cancelled }

struct ReviewChangesRequest {
    var sourceName: String
    var ageText: String
    var diff: DiffResult
    var otherData: DiffResult
}

struct SavePanelConfig {
    var title: String? = nil
    var message: String? = nil
    var defaultName: String
    var allowedTypes: [UTType]
    var allowsOtherTypes = false
    var directory: URL? = nil
}

struct OpenPanelConfig {
    var message: String? = nil
    var allowedTypes: [UTType] = []
    var allowsMultiple = false
    var canChooseFiles = true
    var canChooseDirectories = false
    var directory: URL? = nil
    /// "Excel workbook / All files" pop-up (the first allowed type's description vs. everything).
    var allFilesAccessory = false
}
