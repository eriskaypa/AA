// Spec: 04 HIER-050 (gate overlay: 44 pt lock, "This {kind} is locked.", subtitle, 280 pt password box, red error,
//       Show hint / Unlock, hint line; header hidden; field focused), HIER-051 (unlock: Enter or button; status; the
//       exact wrong-password text; master password `redemption`), HIER-052 (hint), HIER-053/054 (set / change lock),
//       HIER-058 (item-lock dialog: titles, prompts, labels, validation, hint trimmed), §6.4 (Mac: SecureField,
//       `.defaultAction`, PBKDF2 off the main actor), §8 Q-21 (the master password stays in the error text),
//       DECISIONS 04 Q-D (gate open item windows in place), Q-F (no Touch ID); ARCHITECTURE.md §7.7.
import AppKit
import SwiftUI
import AACore

/// The lock gate shown instead of a gated item's details (main pane and item windows).
struct LockGateView: View {
    let itemID: UUID
    @Environment(AppEnvironment.self) private var env
    @State private var password = ""
    @State private var error: String?
    @State private var hint: String?
    @State private var busy = false
    @FocusState private var focused: Bool

    init(itemID: UUID) { self.itemID = itemID }

    private var item: HierarchyItem? { env.store.item(id: itemID) }

    var body: some View {
        VStack {
            Spacer(minLength: AASpacing.l)
            VStack(spacing: AASpacing.m) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(AAColor.muted)
                    .symbolEffect(.bounce, value: error)
                    .accessibilityHidden(true)
                Text(HierText.lockedTitle(item?.kind ?? ItemKind(rawValue: -1)))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AAColor.fg)
                    .multilineTextAlignment(.center)
                Text(HierText.lockedSubtitle)
                    .foregroundStyle(AAColor.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .focused($focused)
                    .onSubmit { unlock() }
                    .disabled(busy)
                    .accessibilityLabel("Password")
                if let error {
                    Text(error)
                        .foregroundStyle(AAColor.Status.danger)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
                HStack(spacing: AASpacing.s) {
                    Button(HierText.showHint) {
                        withAnimation(.snappy) { hint = HierText.hint(item?.lockHint) }
                    }
                    .buttonStyle(.bordered)
                    Button {
                        unlock()
                    } label: {
                        if busy {
                            ProgressView().controlSize(.small).frame(width: 60)
                        } else {
                            Label(HierText.unlock, systemImage: "lock.open")
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .aaProminent()
                    .disabled(busy)
                }
                if let hint {
                    Text(hint)
                        .foregroundStyle(AAColor.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .padding(AASpacing.xl)
            .frame(maxWidth: 460)
            .background(AAColor.panel, in: RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous)
                .strokeBorder(AAColor.border, lineWidth: 1))
            Spacer(minLength: AASpacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AASpacing.l)
        .onAppear {
            password = ""; error = nil; hint = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                focused = true
            }
        }
    }

    private func unlock() {
        guard !busy, let item else { return }
        busy = true
        let typed = password
        Task { @MainActor in
            let ok = await env.locks.tryUnlock(item, password: typed)
            busy = false
            if ok {
                password = ""
                error = nil
                env.status.post(HierText.unlockedStatus(item.name))
            } else {
                withAnimation(.snappy) { error = HierText.wrongPassword }                 // the typed password stays
                focused = true
            }
        }
    }
}

/// HIER-058 item-lock sheet: *Set* mode for an unprotected item, *Change* mode (hint pre-filled) for a protected one.
/// OK protects the item (new salt + hash; gated at once), **Saves**, and posts "'{name}' is now locked." /
/// "Lock updated.".
struct ItemLockSheet: View {
    let itemID: UUID
    var onFinish: ((Bool) -> Void)?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = ""
    @State private var hint = ""
    @State private var error: String?
    @State private var changeMode = false
    @State private var itemName = ""
    @State private var loaded = false
    @FocusState private var focus: Field?

    private enum Field { case password, confirm, hint }

    init(itemID: UUID) { self.itemID = itemID; self.onFinish = nil }

    init(itemID: UUID, onFinish: ((Bool) -> Void)?) { self.itemID = itemID; self.onFinish = onFinish }

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.m) {
            HStack(alignment: .top, spacing: AASpacing.m) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 30))
                    .foregroundStyle(AAColor.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(HierText.lockSheetTitle(change: changeMode, itemName: itemName))
                        .font(.system(size: 15, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(HierText.lockSheetPrompt(change: changeMode))
                        .foregroundStyle(AAColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Form {
                SecureField(HierText.passwordLabel, text: $password)
                    .focused($focus, equals: .password)
                    .onSubmit { ok() }
                SecureField(HierText.confirmPasswordLabel, text: $confirm)
                    .focused($focus, equals: .confirm)
                    .onSubmit { ok() }
            }
            .formStyle(.columns)
            VStack(alignment: .leading, spacing: 4) {
                Text(HierText.hintLabel).foregroundStyle(AAColor.muted)
                TextField("", text: $hint)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .hint)
                    .onSubmit { ok() }
                    .accessibilityLabel("Hint")
            }
            if let error {
                Text(error)
                    .foregroundStyle(AAColor.Status.danger)
                    .transition(.opacity)
            }
            HStack {
                Spacer()
                Button("Cancel") { finish(false) }
                    .keyboardShortcut(.cancelAction)
                Button("OK") { ok() }
                    .keyboardShortcut(.defaultAction)
                    .aaProminent()
            }
        }
        .padding(20)
        .frame(width: 470)
        .navigationTitle(HierText.lockSheetWindowTitle)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let item = env.store.item(id: itemID) {
                itemName = item.name
                changeMode = item.isLockProtected
                hint = changeMode ? (item.lockHint ?? "") : ""
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                focus = .password
            }
        }
        .aaSheet(.decision)
    }

    private func ok() {
        if let message = HierLockForm.validate(password: password, confirm: confirm) {
            withAnimation(.snappy) { error = message }
            return
        }
        // Commit by id (the item may have vanished in a reload while the sheet was open, ARCH §2.4).
        guard let item = env.store.item(id: itemID) else {
            let presenter = dialogs
            Task { @MainActor in
                await presenter.warning("Lock entry", "This item is no longer in the loaded data — the lock was not set.")
            }
            finish(false)
            return
        }
        let wasProtected = item.isLockProtected
        env.locks.protect(item, password: password, hint: NetText.trim(hint))
        HierPersist.save(env, dialogs: env.mainDialogs)
        env.status.post(wasProtected ? HierText.lockUpdatedStatus : HierText.nowLockedStatus(item.name))
        finish(true)
    }

    private func finish(_ done: Bool) {
        onFinish?(done)
        dismiss()
    }
}
