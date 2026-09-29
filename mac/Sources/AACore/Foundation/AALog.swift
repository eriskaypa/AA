// Spec: ARCHITECTURE.md §6.1, §9.2 — os.Logger, subsystem com.eriskay.aa; never log secrets or personal data.
import Foundation
import os

public enum AALog {
    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: Identifiers.logSubsystem, category: category)
    }
}
