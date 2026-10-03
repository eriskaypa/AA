// Spec: 03 SHELL-004, 01 DATA-002 (hard-coded gate 44233 / redemption), DECISIONS 01 Q-1 (keep exactly);
//       03 SHELL-161 (password dialog validation order). Vectors: 03 §7.1 "Login", "Password dialog".
import Foundation

/// The login gate's credential check (a basic gate, not security — 03 SHELL-004).
public enum ShellLogin {
    public static let windowTitle = "AA — Sign in"
    public static let subtitle = "Please sign in to continue"
    public static let failureMessage = "Incorrect username or password."

    static let username = "44233"
    static let password = "redemption"

    /// Username: .NET `Trim()` then ordinal equality; password: exact ordinal equality, no trim.
    public static func check(username u: String, password p: String) -> Bool {
        Ordinal.equals(NetText.trim(u), username) && Ordinal.equals(p, password)
    }
}

/// SHELL-161 password-sheet modes and their exact texts and validation.
public enum ShellPasswordMode: Sendable, Equatable {
    case unlock, setNew, changeExisting

    public var heading: String {
        switch self {
        case .unlock: return "Unlock"
        case .setNew: return "Set app password"
        case .changeExisting: return "Change app password"
        }
    }

    public var prompt: String {
        switch self {
        case .unlock: return "Enter the app password to unlock locked containers:"
        case .setNew: return "Pick a password (used to lock/unlock every container).\nConfirm it on the second line."
        case .changeExisting: return "Enter your current password, then the new password and confirm it on the line below."
        }
    }

    public var hasConfirmation: Bool { self != .unlock }

    /// DECISIONS 01 Q-4: changing an existing password asks for the current one (Mac addition).
    public var asksCurrentPassword: Bool { self == .changeExisting }

    /// Validation in Windows order; `verifyCurrent` is consulted for the current-password field (change mode) and
    /// `verifyUnlock` for unlock mode. Returns the error text, nil when the input is accepted.
    public func validate(password: String, confirm: String, current: String?,
                         verifyUnlock: (String) -> Bool, verifyCurrent: (String) -> Bool) -> String? {
        switch self {
        case .unlock:
            if password.isEmpty { return "Password cannot be empty." }
            return verifyUnlock(password) ? nil : "Wrong password."
        case .setNew:
            return PasswordService.validationMessage(password: password, confirm: confirm)
        case .changeExisting:
            if let current, !verifyCurrent(current) { return "Wrong password." }
            if current == nil { return "Wrong password." }
            return PasswordService.validationMessage(password: password, confirm: confirm)
        }
    }
}
