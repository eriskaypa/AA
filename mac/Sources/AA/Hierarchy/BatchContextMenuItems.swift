// PLACEHOLDER(W-HIER) — contract: ARCHITECTURE.md §7.7
// Spec: 04 HIER-133…135 (batch menus). Compiling stub created by F3; W-HIER replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

struct BatchContextMenuItems: View {
    let selection: () -> [AnyObject]
    let refresh: () -> Void
    let done: Bool
    let deadline: Bool

    init(selection: @escaping () -> [AnyObject], refresh: @escaping () -> Void, done: Bool = true, deadline: Bool = true) {
        self.selection = selection; self.refresh = refresh; self.done = done; self.deadline = deadline
    }

    var body: some View {
        // PLACEHOLDER(W-HIER)
        EmptyView()
    }
}

@MainActor enum BatchActions {
    static func markDone(_ items: [AnyObject], done: Bool, env: AppEnvironment) -> Int {
        // PLACEHOLDER(W-HIER)
        0
    }

    static func setDeadline(_ items: [AnyObject], env: AppEnvironment, dialogs: DialogPresenter) async -> Int {
        // PLACEHOLDER(W-HIER)
        0
    }

    static func confirmAndTrash(_ items: [AnyObject], env: AppEnvironment, dialogs: DialogPresenter) async -> Int {
        // PLACEHOLDER(W-HIER)
        0
    }
}
