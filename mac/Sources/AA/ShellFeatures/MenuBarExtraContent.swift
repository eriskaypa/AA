// Spec: 03 §6.8 (tray icon → MenuBarExtra: headline counts, crew suffix, `Show Due Dates…` (balloon click),
//       `Show AA` (tray double-click)), SHELL-130, SHELL-133, 02 REPO-112, DECISIONS 02 Q-13, 03 Q-4 (on by default,
//       toggle in Settings ▸ General); ARCHITECTURE.md §7.1 (F3 declares the scene), §9.3.
import AppKit
import SwiftUI
import AACore

/// The menu of AA's menu-bar item (menu style: every element becomes an NSMenuItem).
struct MenuBarExtraContent: View {
    @State private var reminders = ReminderCenter.shared

    var body: some View {
        Section {
            Text(reminders.headline)
            if reminders.summary.any {
                if reminders.summary.overdue > 0 {
                    Label("\(reminders.summary.overdue) overdue", systemImage: "exclamationmark.circle")
                }
                if reminders.summary.dueToday > 0 {
                    Label("\(reminders.summary.dueToday) due today", systemImage: "calendar")
                }
                if reminders.summary.dueWeek > 0 {
                    Label("\(reminders.summary.dueWeek) due this week", systemImage: "calendar.badge.clock")
                }
            }
            if reminders.crewExpiring > 0 {
                Label("\(reminders.crewExpiring) crew contract(s) expiring", systemImage: "person.badge.clock")
            }
        } header: {
            Text("AA")
        }
        Divider()
        Button {
            NSApp.activate()
            LaunchCoordinator.shared.env?.open(.dueDates)
        } label: {
            Label(ShellXText.showDueDates, systemImage: AASymbol.due)
        }
        Button {
            NSApp.activate()
            LaunchCoordinator.shared.env?.showMainWindow()
        } label: {
            Label(ShellXText.showAA, systemImage: "macwindow")
        }
        Divider()
        Button {
            NSApp.activate()
            LaunchCoordinator.shared.env?.open(.settings(tab: .general))
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        Button("Quit AA") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
