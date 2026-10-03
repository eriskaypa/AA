// Spec: 03 §6.1 / §6.5 (MessageBox → window-modal sheets; title → messageText, body → informativeText; destructive
//       confirmations default to Cancel), SHELL-505/513 (decision vs close-type sheets), 06 BUILD-147 (sheets attach to the
//       window the command came from; sheet on sheet), 01 DATA-223 (one shared component per dialog type);
//       ARCHITECTURE.md §7.5 (one presenter per window, `@Entry` default `.unbound`).
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

extension EnvironmentValues {
    @Entry var dialogs: DialogPresenter = .unbound
}

/// One queued sheet.
struct ShellPresentedSheet: Identifiable {
    let id = UUID()
    let kind: SheetKind
    let make: (_ dismiss: @escaping () -> Void) -> AnyView
    let finish: () -> Void
}

/// Presents sheets, alerts and panels on its window. Every window root (and every presented sheet) owns one.
@MainActor @Observable
final class DialogPresenter {
    nonisolated init() {}

    /// The default when no window root installed a presenter: logs and returns cancel / nil / [] / false.
    nonisolated static let unbound = DialogPresenter()

    /// The window this presenter attaches its sheets, alerts and panels to.
    @ObservationIgnored weak var window: NSWindow?
    /// The sheet currently shown by this presenter's host (observed by `ShellDialogHost`).
    var presented: ShellPresentedSheet?
    @ObservationIgnored private var queue: [ShellPresentedSheet] = []

    private var isUnbound: Bool { self === DialogPresenter.unbound }
    private static let log = AALog.logger("dialogs")

    private func unboundCall(_ what: String) -> Bool {
        if isUnbound { DialogPresenter.log.error("dialog \(what, privacy: .public) requested without a window root") }
        return isUnbound
    }

    // MARK: Sheets

    func presentSheet<Content: View>(_ kind: SheetKind,
                                     @ViewBuilder _ content: @escaping (_ dismiss: @escaping () -> Void) -> Content) async {
        if unboundCall("sheet") { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let item = ShellPresentedSheet(kind: kind, make: { dismiss in AnyView(content(dismiss)) },
                                           finish: { cont.resume() })
            if presented == nil { presented = item } else { queue.append(item) }
        }
    }

    /// Called by the host's `onDismiss`.
    func sheetDidDismiss(_ id: UUID?) {
        if let current = presented, current.id == id { presented = nil }
        finished(id)
    }

    @ObservationIgnored private var finishedIDs = Set<UUID>()
    /// The id of the sheet the host last showed (its `onDismiss` finishes that one).
    @ObservationIgnored var shownID: UUID?

    private func finished(_ id: UUID?) {
        guard let id, !finishedIDs.contains(id) else { return }
        finishedIDs.insert(id)
        pendingFinish[id]?()
        pendingFinish[id] = nil
        if presented == nil, !queue.isEmpty {
            let next = queue.removeFirst()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                self.presented = next
            }
        }
    }

    @ObservationIgnored private var pendingFinish: [UUID: () -> Void] = [:]

    func register(_ item: ShellPresentedSheet) { pendingFinish[item.id] = item.finish }

    // MARK: Text prompt (06 BUILD-136…150)

    func prompt(_ r: TextPromptRequest) async -> TextPromptResult {
        if unboundCall("prompt") { return .cancelled }
        var result = TextPromptResult.cancelled
        await presentSheet(.decision) { dismiss in
            TextPromptSheet(request: r) { res in result = res; dismiss() }
        }
        return result
    }

    // MARK: Date prompt (04 HIER-132, 07 VIEW-203, 08 QUICK-230)

    func datePrompt(_ r: DatePromptRequest) async -> DatePromptResult {
        if unboundCall("datePrompt") { return .cancelled }
        var result = DatePromptResult.cancelled
        await presentSheet(.decision) { dismiss in
            DatePromptSheet(request: r) { res in result = res; dismiss() }
        }
        return result
    }

    // MARK: Item picker (07 VIEW-208…216, 04 HIER-131)

    func pickItems<Tag: Hashable & Sendable>(_ r: ItemPickerRequest<Tag>) async -> [Tag]? {
        if unboundCall("pickItems") { return nil }
        let pre = Set(r.preselected)
        let preIdx = Set(r.rows.indices.filter { pre.contains(r.rows[$0].tag) })
        var picked: [Int]?
        await presentSheet(.decision) { dismiss in
            ItemPickerSheet(prompt: r.prompt, displays: r.rows.map(\.display), preselected: preIdx,
                            single: r.mode == .single, candidateOrder: r.resultOrder == .candidate) { res in
                picked = res
                dismiss()
            }
        }
        return picked.map { $0.map { r.rows[$0].tag } }
    }

    // MARK: Password (03 SHELL-161, DECISIONS 01 Q-4)

    func password(_ mode: PasswordSheetMode) async -> PasswordSheetResult {
        if unboundCall("password") { return .cancelled }
        var result = PasswordSheetResult.cancelled
        await presentSheet(.decision) { dismiss in
            PasswordSheet(mode: mode) { res in result = res; dismiss() }
        }
        return result
    }

    // MARK: Review changes (03 SHELL-120 — W-QUICK's sheet)

    func reviewChanges(_ r: ReviewChangesRequest) async -> Bool {
        if unboundCall("reviewChanges") { return false }
        var ok = false
        await presentSheet(.decision) { dismiss in
            ReviewChangesSheet(request: r) { confirmed in ok = confirmed; dismiss() }
        }
        return ok
    }

    // MARK: Alerts

    /// Returns the index of the pressed button. Button 0 is the default unless another button has the `.default`
    /// role; a `.cancel` button answers ⎋; destructive confirmations may default to Cancel.
    func alert(_ spec: AlertSpec) async -> Int {
        if unboundCall("alert") { return spec.buttons.firstIndex { $0.role == .cancel } ?? max(spec.buttons.count - 1, 0) }
        if let key = spec.suppressionKey, MacPreferences.shared.bool(key, default: false) {
            return spec.buttons.firstIndex { $0.role == .default } ?? 0
        }
        let alert = NSAlert()
        alert.messageText = spec.title
        alert.informativeText = spec.message
        alert.alertStyle = spec.style
        let buttons = spec.buttons.isEmpty ? [AlertButton(title: "OK", role: .default)] : spec.buttons
        let defaultIndex = buttons.firstIndex { $0.role == .default } ?? 0
        for (i, b) in buttons.enumerated() {
            let nb = alert.addButton(withTitle: b.title)
            nb.keyEquivalent = ""
            if i == defaultIndex { nb.keyEquivalent = "\r" }
            if b.role == .cancel { nb.keyEquivalent = i == defaultIndex ? "\r" : "\u{1b}" }
            if b.role == .destructive { nb.hasDestructiveAction = true }
        }
        if spec.suppressionKey != nil { alert.showsSuppressionButton = true }
        let response = await run(alert)
        if let key = spec.suppressionKey, alert.suppressionButton?.state == .on { MacPreferences.shared.set(true, key) }
        let idx = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return (0..<buttons.count).contains(idx) ? idx : (buttons.firstIndex { $0.role == .cancel } ?? 0)
    }

    private func run(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        if let w = window ?? NSApp.keyWindow, w.isVisible, w.attachedSheet == nil {
            return await withCheckedContinuation { cont in
                alert.beginSheetModal(for: w) { cont.resume(returning: $0) }
            }
        }
        return alert.runModal()
    }

    func info(_ title: String, _ message: String) async {
        _ = await alert(AlertSpec(title: title, message: message, style: .informational,
                                  buttons: [AlertButton(title: "OK", role: .default)]))
    }

    func warning(_ title: String, _ message: String) async {
        _ = await alert(AlertSpec(title: title, message: message, style: .warning,
                                  buttons: [AlertButton(title: "OK", role: .default)]))
    }

    func error(_ title: String, _ message: String) async {
        _ = await alert(AlertSpec(title: title, message: message, style: .critical,
                                  buttons: [AlertButton(title: "OK", role: .default)]))
    }

    /// Two-button confirmation; destructive confirmations default to Cancel when `defaultIsCancel`.
    func confirm(_ title: String, _ message: String, confirm: String, cancel: String = "Cancel",
                 destructive: Bool = false, defaultIsCancel: Bool = false) async -> Bool {
        let buttons: [AlertButton] = defaultIsCancel
            ? [AlertButton(title: confirm, role: destructive ? .destructive : .normal), AlertButton(title: cancel, role: .default)]
            : [AlertButton(title: confirm, role: .default), AlertButton(title: cancel, role: .cancel)]
        var spec = AlertSpec(title: title, message: message, style: destructive ? .warning : .informational, buttons: buttons)
        if defaultIsCancel, destructive { spec.buttons[0].role = .destructive }
        return await alert(spec) == 0
    }

    // MARK: Panels

    func savePanel(_ c: SavePanelConfig) async -> URL? {
        if unboundCall("savePanel") { return nil }
        let p = NSSavePanel()
        if let t = c.title { p.title = t }
        if let m = c.message { p.message = m }
        p.nameFieldStringValue = c.defaultName
        p.allowedContentTypes = c.allowedTypes
        p.allowsOtherFileTypes = c.allowsOtherTypes
        p.canCreateDirectories = true
        if let d = c.directory { p.directoryURL = d }
        let r = await runPanel(p)
        return r == .OK ? p.url : nil
    }

    func openPanel(_ c: OpenPanelConfig) async -> [URL] {
        if unboundCall("openPanel") { return [] }
        let p = NSOpenPanel()
        if let m = c.message { p.message = m }
        p.allowsMultipleSelection = c.allowsMultiple
        p.canChooseFiles = c.canChooseFiles
        p.canChooseDirectories = c.canChooseDirectories
        p.allowedContentTypes = c.allowedTypes
        if let d = c.directory { p.directoryURL = d }
        var helper: ShellOpenPanelFilter?
        if c.allFilesAccessory, let first = c.allowedTypes.first {
            let h = ShellOpenPanelFilter(panel: p, types: c.allowedTypes, label: first.localizedDescription ?? "Matching files")
            helper = h
            p.accessoryView = h.view
            p.isAccessoryViewDisclosed = true
        }
        let r = await runPanel(p)
        _ = helper
        return r == .OK ? p.urls : []
    }

    func chooseFolder(message: String, directory: URL?) async -> URL? {
        let urls = await openPanel(OpenPanelConfig(message: message, canChooseFiles: false, canChooseDirectories: true,
                                                   directory: directory))
        return urls.first
    }

    private func runPanel(_ p: NSSavePanel) async -> NSApplication.ModalResponse {
        if let w = window ?? NSApp.keyWindow, w.isVisible, w.attachedSheet == nil {
            return await withCheckedContinuation { cont in p.beginSheetModal(for: w) { cont.resume(returning: $0) } }
        }
        return p.runModal()
    }
}

/// "Excel workbook / All files" accessory for open panels.
@MainActor final class ShellOpenPanelFilter: NSObject {
    let view: NSView
    private weak var panel: NSOpenPanel?
    private let types: [UTType]
    private let popup: NSPopUpButton

    init(panel: NSOpenPanel, types: [UTType], label: String) {
        self.panel = panel
        self.types = types
        popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: [label, "All files"])
        let text = NSTextField(labelWithString: "Show:")
        let stack = NSStackView(views: [text, popup])
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        view = stack
        super.init()
        popup.target = self
        popup.action = #selector(changed(_:))
    }

    @objc private func changed(_ sender: NSPopUpButton) {
        panel?.allowedContentTypes = sender.indexOfSelectedItem == 0 ? types : []
    }
}

// MARK: Host

/// Installs a window's presenter: shows its queued sheets (each sheet gets its own nested presenter).
struct ShellDialogHost: ViewModifier {
    let presenter: DialogPresenter

    func body(content: Content) -> some View {
        @Bindable var p = presenter
        return content
            .environment(\.dialogs, presenter)
            .background(ShellWindowCapture { presenter.window = $0 })
            .sheet(item: $p.presented, onDismiss: { presenter.sheetDidDismiss(presenter.lastPresentedID) }) { item in
                ShellNestedDialogRoot(kind: item.kind) {
                    item.make { presenter.dismissCurrent(item.id) }
                }
                .onAppear { presenter.didShow(item) }
            }
    }
}

extension DialogPresenter {
    var lastPresentedID: UUID? { shownID }

    func didShow(_ item: ShellPresentedSheet) {
        shownID = item.id
        register(item)
    }

    func dismissCurrent(_ id: UUID) {
        if presented?.id == id { presented = nil }
    }
}

/// The root of every presented sheet: a nested presenter (sheet on sheet, BUILD-147) and the sheet's window capture.
struct ShellNestedDialogRoot<Content: View>: View {
    let kind: SheetKind
    @ViewBuilder var content: () -> Content
    @State private var nested = DialogPresenter()

    var body: some View {
        content()
            .modifier(ShellDialogHost(presenter: nested))
            .modifier(ShellSheetModifier(kind: kind, role: nil, onClose: nil, explicit: false))
    }
}
