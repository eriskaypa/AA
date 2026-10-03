// Spec: 03 §6.1 (scenes, splash/login/main), §6.10 (secondary windows), SHELL-526 (`.commandsRemoved()` on Tools
//       windows), DECISIONS 08 OQ-3 (single Search / Activity log), DECISIONS Q-13 (MenuBarExtra), 01 DATA-186 (one main
//       window); ARCHITECTURE.md §7.1 (every scene restoration-disabled; bootstrap presented, every other scene suppressed).
import AppKit
import SwiftUI
import AACore

struct AAApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var coordinator = LaunchCoordinator.shared

    init() {
        // ARCH §7.1: the system never reopens windows before the instance check and the login gate.
        UserDefaults.standard.register(defaults: [
            "NSQuitAlwaysKeepsWindows": false,
            "ApplePersistenceIgnoreState": true,
        ])
    }

    var body: some Scene {
        Window("", id: SceneID.bootstrap.rawValue) { BootstrapView() }
            .defaultLaunchBehavior(.presented)
            .windowStyle(.plain)
            .restorationBehavior(.disabled)
            .commandsRemoved()
            .windowResizability(.contentSize)
            .defaultPosition(.bottomTrailing)

        Window("AA", id: SceneID.splash.rawValue) { SplashView().aaWindowRoot(.splash) }
            .defaultLaunchBehavior(.suppressed)
            .windowStyle(.plain)
            .windowLevel(.floating)
            .windowResizability(.contentSize)
            .restorationBehavior(.disabled)
            .commandsRemoved()
            .defaultWindowPlacement { content, context in
                WindowPlacement(.center, size: content.sizeThatFits(.unspecified))
            }

        Window(ShellLogin.windowTitle, id: SceneID.login.rawValue) { LoginView().aaWindowRoot(.login) }
            .defaultLaunchBehavior(.suppressed)
            .windowResizability(.contentSize)
            .restorationBehavior(.disabled)
            .commandsRemoved()
            .defaultWindowPlacement { content, context in
                WindowPlacement(.center, size: CGSize(width: 420, height: 280))
            }

        Window("AA", id: SceneID.main.rawValue) { MainWindowView().aaWindowRoot(.main) }
            .defaultLaunchBehavior(.suppressed)
            .restorationBehavior(.disabled)
            .defaultSize(width: 1280, height: 820)
            .defaultWindowPlacement { content, context in
                WindowPlacement(.center, size: CGSize(width: 1280, height: 820))
            }
            .commands { AppCommands(coordinator: coordinator) }

        WindowGroup("Item", id: SceneID.item.rawValue, for: UUID.self) { $id in
            ShellItemSceneContent(id: id)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()
        .defaultSize(width: 980, height: 720)

        Window("Quick work — all tasks & procedures", id: SceneID.quickWork.rawValue) {
            QuickWorkView().aaWindowRoot(.quickWork)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()
        .defaultSize(width: 1200, height: 800)

        Window("Search", id: SceneID.search.rawValue) { SearchWindowView().aaWindowRoot(.search) }
            .defaultLaunchBehavior(.suppressed)
            .restorationBehavior(.disabled)
            .commandsRemoved()
            .defaultSize(width: 860, height: 620)

        Window("Activity log", id: SceneID.activityLog.rawValue) { ActivityLogView().aaWindowRoot(.activityLog) }
            .defaultLaunchBehavior(.suppressed)
            .restorationBehavior(.disabled)
            .commandsRemoved()
            .defaultSize(width: 900, height: 600)

        WindowGroup("Unit converter", id: SceneID.unitConverter.rawValue, for: UUID.self) { $session in
            UnitConverterView(sessionID: session ?? UUID()).aaWindowRoot(.unitConverter)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()
        .defaultSize(width: 560, height: 520)

        Window("Folder builder", id: SceneID.folderBuilder.rawValue) { FolderBuilderView().aaWindowRoot(.folderBuilder) }
            .defaultLaunchBehavior(.suppressed)
            .restorationBehavior(.disabled)
            .commandsRemoved()
            .defaultSize(width: 760, height: 600)

        Window("Date calculator", id: SceneID.dateCalculator.rawValue) {
            DateCalculatorView().aaWindowRoot(.dateCalc).frame(width: 540, height: 520)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()
        .windowResizability(.contentSize)

        Window("Flash Sync with iPhone", id: SceneID.flashSync.rawValue) { FlashSyncView().aaWindowRoot(.flashSync) }
            .defaultLaunchBehavior(.suppressed)
            .restorationBehavior(.disabled)
            .commandsRemoved()
            .defaultSize(width: 920, height: 760)

        Window("Crew — Table View", id: SceneID.crewTable.rawValue) { CrewTableView().aaWindowRoot(.crewTable) }
            .defaultLaunchBehavior(.suppressed)
            .restorationBehavior(.disabled)
            .commandsRemoved()
            .defaultSize(width: 1100, height: 700)

        Window("AA Keyboard Shortcuts", id: SceneID.shortcuts.rawValue) { KeyboardShortcutsView().aaWindowRoot(.shortcuts) }
            .defaultLaunchBehavior(.suppressed)
            .restorationBehavior(.disabled)
            .commandsRemoved()
            .defaultSize(width: 860, height: 640)

        Window("About AA", id: SceneID.about.rawValue) { AboutView().aaWindowRoot(.about) }
            .defaultLaunchBehavior(.suppressed)
            .restorationBehavior(.disabled)
            .commandsRemoved()
            .windowResizability(.contentSize)

        Settings { SettingsView().aaWindowRoot(.settings) }

        MenuBarExtra(isInserted: Binding(get: { coordinator.menuBarExtraVisible }, set: { coordinator.setMenuBarExtra($0) })) {
            MenuBarExtraContent().aaWindowRoot(.other)
        } label: {
            ShellMenuBarIcon()
        }
    }
}

/// Item windows: one per item id (W-HIER's view).
struct ShellItemSceneContent: View {
    let id: UUID?
    var body: some View {
        if let id {
            ItemWindowView(itemID: id).aaWindowRoot(.item(id))
        } else {
            AAEmptyState(title: "No item", symbol: "questionmark.square.dashed").aaWindowRoot(.other)
        }
    }
}

/// The MenuBarExtra template image (a disc with "A"), from the bundled template PNG when available.
struct ShellMenuBarIcon: View {
    var body: some View {
        if let url = AAResources.url(name: "MenuBarIconTemplate", ext: "png"), let img = NSImage(contentsOf: url) {
            let _ = { img.isTemplate = true }()
            Image(nsImage: img)
        } else {
            Image(systemName: "a.circle")
        }
    }
}
