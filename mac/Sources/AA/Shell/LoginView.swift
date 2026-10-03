// Spec: 03 SHELL-004 (login gate layout, strings, Enter submits, failure clears and focuses the password, Exit /
//       close → terminate; Esc not bound), §6.1 (Mac rendition), 01 DATA-002, DECISIONS 01 Q-1, BD.3.12
//       (`LoginModel.submit` is the entry point the smoke harness drives).
import AppKit
import SwiftUI
import AACore

/// The login gate's state; `submit` is what the Sign in button and the smoke harness call.
@MainActor @Observable
final class ShellLoginModel {
    static let shared = ShellLoginModel()

    var username = ""
    var password = ""
    var errorText = ""
    /// Bumped after a failure so the view moves focus to the password field.
    var failureCount = 0

    @discardableResult
    func submit(username u: String, password p: String) -> Bool {
        username = u
        password = p
        return submit()
    }

    @discardableResult
    func submit() -> Bool {
        if ShellLogin.check(username: username, password: password) {
            errorText = ""
            password = ""
            LaunchCoordinator.shared.loginSucceeded()
            return true
        }
        errorText = ShellLogin.failureMessage
        password = ""
        failureCount += 1
        return false
    }

    func exit() { NSApp.terminate(nil) }
}

struct LoginView: View {
    @State private var model = ShellLoginModel.shared
    @FocusState private var focus: Field?
    private enum Field { case username, password }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 2) {
                Text("AA").font(.aaMono(AAType.loginBrand, weight: .bold)).foregroundStyle(AAColor.accent)
                Text(ShellLogin.subtitle).font(.aaMono(AAType.small)).foregroundStyle(AAColor.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)

            Text("Username").font(.aaMono(AAType.small)).foregroundStyle(AAColor.fg)
            TextField("", text: $model.username)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .username)
                .onSubmit { model.submit() }
                .padding(.bottom, AASpacing.s)
                .accessibilityLabel("Username")

            Text("Password").font(.aaMono(AAType.small)).foregroundStyle(AAColor.fg)
            SecureField("", text: $model.password)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .password)
                .onSubmit { model.submit() }
                .accessibilityLabel("Password")

            Text(model.errorText)
                .font(.aaMono(AAType.small))
                .foregroundStyle(AAColor.Status.danger)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 18, alignment: .topLeading)
                .padding(.top, 6)
                .animation(.easeOut(duration: 0.15), value: model.errorText)

            Spacer(minLength: 0)

            HStack(spacing: AASpacing.s) {
                Spacer()
                Button("Exit") { model.exit() }
                    .frame(width: 90)
                Button("Sign in") { model.submit() }
                    .keyboardShortcut(.defaultAction)
                    .aaProminent()
                    .frame(width: 110)
            }
        }
        .padding(22)
        .frame(width: 420, height: 280)
        .background(AAColor.bg)
        .onAppear { focus = .username }
        .onChange(of: model.failureCount) { _, _ in focus = .password }
    }
}
