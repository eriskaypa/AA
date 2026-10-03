// Spec: 03 BD.1.3 steps 0a/0b (parse arguments; --version before any UI or file access), SHELL-192 (--snapshot in
//       release builds), SHELL-205 / BD.3.12 (--smoke-test dispatch to W-SHELL); ARCHITECTURE.md §7.1, §9.6.
import AppKit
import SwiftUI
import AACore

/// The custom entry point: parses the command line, handles `--version`, dispatches `--smoke-test`, then runs the app.
@main
enum AAMain {
    @MainActor
    static func main() {
        let opts = LaunchArguments.parse(CommandLine.arguments)
        if opts.version {
            print(ShellLaunchEnvironment.currentVersionLine)
            exit(0)
        }
        LaunchCoordinator.shared.options = opts
        if opts.smokeTest {
            // W-SHELL's harness: a non-zero code means it refused to run (e.g. exit 3); 0 = armed, launch normally.
            let code = SmokeTest.run(options: opts)
            if code != 0 { exit(code) }
        }
        if opts.snapshot != nil {
            #if DEBUG
            LaunchCoordinator.shared.snapshotMode = true
            #else
            FileHandle.standardError.write(Data((LaunchArguments.snapshotUnavailableMessage + "\n").utf8))
            #endif
        }
        AAApp.main()
    }
}
