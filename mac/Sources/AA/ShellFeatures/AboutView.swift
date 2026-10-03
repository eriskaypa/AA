// Spec: 03 SHELL-115 / D26 (About AA: "Created by B.E.P. Avida - May 2026" — the splash says "B.E.P Avida"; each
//       kept as is), §6.4 (custom About: icon, "AA", credits), BD.3.11 (standard panel shows "Version 1.0.0 (412)" with
//       the credits unchanged), SHELL-182 (AABuildDate / AAGitCommit), SHELL-021 (brand tagline), §6.9 (data folder).
import AppKit
import SwiftUI
import AACore

/// AA ▸ About AA — a single, non-resizable window.
struct AboutView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    private let version = ShellXVersionInfo.current

    var body: some View {
        VStack(spacing: 0) {
            ShellXAppIcon(size: 112)
                .padding(.bottom, AASpacing.m)

            Text("AA")
                .font(.aaMono(AAType.loginBrand, weight: .bold))
                .foregroundStyle(AAColor.accent)
            Text("Equipment/Area / Tasks / Procedures with containers, files & relationships")   // SHELL-021 tagline
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            VStack(spacing: 3) {
                Text(version.versionLine)
                    .font(.system(size: AAType.small, weight: .medium))
                if let build = version.buildLine {
                    Text(build).font(.system(size: AAType.caption)).foregroundStyle(.secondary)
                }
            }
            .textSelection(.enabled)
            .padding(.top, AASpacing.m)

            Divider().frame(width: 240).padding(.vertical, AASpacing.m)

            Text(ShellXVersionInfo.credits)
                .font(.aaMono(AAType.body))
                .foregroundStyle(AAColor.fg)
                .textSelection(.enabled)

            HStack(spacing: AASpacing.xs) {
                Image(systemName: AASymbol.folder).foregroundStyle(.secondary)
                Text(env.dataStore.appFolder.path)
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(env.dataStore.appFolder.path)
                Button("Show") {
                    Task { @MainActor in await ShellFlows.perform(.openDataFolder, env: env, dialogs: dialogs) }
                }
                .buttonStyle(.link)
                .font(.system(size: AAType.caption))
            }
            .padding(.top, AASpacing.s)
            .frame(maxWidth: 320)
        }
        .padding(.horizontal, AASpacing.xl + 8)
        .padding(.top, AASpacing.xl)
        .padding(.bottom, AASpacing.xl)
        .frame(width: 400)
        .background(AAColor.bg)
    }
}
