// Spec: 03 §6.1 (scenes), SHELL-505/513/514 (sheet kinds: ⌘W / ⎋ rules), §6.5.1.13 (close-type sheets add a hidden
//       ⌘W button), SHELL-526 (Window-menu exclusions); ARCHITECTURE.md §7.1 (`.aaWindowRoot` registers the window with
//       SceneOpener), §7.5 (sheet contract), §7.6 (`.aaWindowRoot`, `.aaSheet`).
import AppKit
import SwiftUI
import AACore

/// Reports the NSWindow hosting a SwiftUI view (on attach and whenever it moves to another window).
struct ShellWindowCapture: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> ShellWindowCaptureView {
        let v = ShellWindowCaptureView()
        v.onWindow = onWindow
        return v
    }

    func updateNSView(_ nsView: ShellWindowCaptureView, context: Context) {
        nsView.onWindow = onWindow
        if let w = nsView.window { onWindow(w) }
    }
}

final class ShellWindowCaptureView: NSView {
    var onWindow: (@MainActor (NSWindow) -> Void)?
    private weak var reported: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let w = window, w !== reported else { return }
        reported = w
        let cb = onWindow
        MainActor.assumeIsolated { cb?(w) }
    }
}

extension View {
    /// Applied by F3 to every scene's content: environment, dialog presenter, window registration, root font.
    func aaWindowRoot(_ role: KeyWindowRole) -> some View { ShellWindowRoot(role: role) { self } }

    /// Marks a custom sheet (decision: refuses ⌘W/⌘Q; close-type: ⌘W / ⎋ close = save). `role: .viewer` for the
    /// read-only viewer.
    func aaSheet(_ kind: SheetKind, role: KeyWindowRole? = nil, onClose: (() -> Void)? = nil) -> some View {
        modifier(ShellSheetModifier(kind: kind, role: role, onClose: onClose, explicit: true))
    }
}

/// The root of every AA scene.
struct ShellWindowRoot<Content: View>: View {
    let role: KeyWindowRole
    @ViewBuilder var content: () -> Content
    @State private var presenter = DialogPresenter()

    var body: some View {
        if let env = LaunchCoordinator.shared.env {
            content()
                .modifier(ShellDialogHost(presenter: presenter))
                .environment(env)
                .environment(\.aaRouter, env.router)
                .environment(\.aaWindowRole, role)
                .font(.aaMono(AAType.body))
                .tint(AAColor.tint)
                .background(ShellWindowCapture { window in
                    SceneOpener.shared.register(window: window, role: role, dialogs: presenter)
                })
        } else {
            content()
                .environment(\.aaWindowRole, role)
                .background(ShellWindowCapture { window in
                    SceneOpener.shared.register(window: window, role: role, dialogs: presenter)
                })
        }
    }
}

struct ShellSheetModifier: ViewModifier {
    let kind: SheetKind
    let role: KeyWindowRole?
    let onClose: (() -> Void)?
    /// False for the generic root F3 wraps around presented sheets (the sheet's own `.aaSheet` wins).
    var explicit = true
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .background(ShellWindowCapture { window in
                SceneOpener.shared.registerSheet(window: window, kind: kind, role: role, explicit: explicit)
            })
            .background {
                if kind == .closeType {
                    // §6.5.1.13: an in-view ⌘W wins inside the sheet (R-b); closing a close-type sheet saves.
                    Button("") { close() }.keyboardShortcut("w", modifiers: .command).hidden()
                        .accessibilityHidden(true)
                }
            }
            .onExitCommand { if kind == .closeType { close() } }
    }

    private func close() {
        onClose?()
        dismiss()
    }
}
