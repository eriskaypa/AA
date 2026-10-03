// Spec: 03 SHELL-161 (password dialog: heading, prompt, one or two boxes, red error line, Cancel / OK; validation order;
//       the master password always verifies), 01 DATA-080/081, DECISIONS 01 Q-4 (change asks for the current password);
//       ARCHITECTURE.md §7.5.
import AppKit
import SwiftUI
import AACore

struct PasswordSheet: View {
    let mode: PasswordSheetMode
    let finish: (PasswordSheetResult) -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var current = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var error = ""
    @State private var done = false
    @FocusState private var focus: Field?
    private enum Field { case current, password, confirm }

    private var shellMode: ShellPasswordMode {
        switch mode {
        case .unlock: return .unlock
        case .setNew: return .setNew
        case .changeExisting: return .changeExisting
        }
    }

    private var promptText: String {
        if case .unlock(let p) = mode, !p.isEmpty { return p }
        return shellMode.prompt
    }

    private func complete(_ r: PasswordSheetResult) {
        guard !done else { return }
        done = true
        finish(r)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(shellMode.heading).font(.system(size: 14, weight: .bold))
            Text(promptText).fixedSize(horizontal: false, vertical: true)
            if shellMode.asksCurrentPassword {
                SecureField("Current password", text: $current)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .current)
            }
            SecureField(shellMode == .unlock ? "Password" : "New password", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .password)
                .onSubmit { if !shellMode.hasConfirmation { ok() } }
            if shellMode.hasConfirmation {
                SecureField("Confirm password", text: $confirm)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .confirm)
                    .onSubmit { ok() }
            }
            Text(error)
                .foregroundStyle(AAColor.Status.danger)
                .font(.system(size: AAType.small))
                .frame(minHeight: 16, alignment: .topLeading)
            HStack {
                Spacer()
                Button("Cancel") { complete(.cancelled) }.keyboardShortcut(.cancelAction).frame(minWidth: 80)
                Button("OK") { ok() }.keyboardShortcut(.defaultAction).aaProminent().frame(minWidth: 80)
            }
        }
        .padding(16)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { focus = shellMode.asksCurrentPassword ? .current : .password }
        .onDisappear { complete(.cancelled) }
        .aaSheet(.decision)
    }

    private func ok() {
        let passwords = env.passwords
        if let message = shellMode.validate(password: password, confirm: confirm,
                                            current: shellMode.asksCurrentPassword ? current : nil,
                                            verifyUnlock: { passwords.verify($0) },
                                            verifyCurrent: { passwords.verify($0) }) {
            withAnimation(.snappy) { error = message }
            if message == "Wrong password.", shellMode.asksCurrentPassword { current = ""; focus = .current } else {
                focus = .password
            }
            return
        }
        complete(.ok(password: password, current: shellMode.asksCurrentPassword ? current : nil))
    }
}
