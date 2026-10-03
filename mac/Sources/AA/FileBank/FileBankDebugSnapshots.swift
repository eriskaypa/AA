// Debug snapshot registrations of W-FILES (ARCHITECTURE.md §9.6; sheet ids "w-files.<name>"). They render the file
// bank, the read-only viewer and the backlinks section over the fixture data folder
// `Tests/AACoreTests/Fixtures/ui/w-files/` (copied to a scratch folder, `sample-data.json` → `data.json`).
import SwiftUI
import AACore

extension SnapshotRegistry {
    static func registerW_FILES() {
        register("w-files.file-bank") { env in
            FileBankDebug.bank(env, item: "Main engine", initial: FileBankInitialState(scope: .tab(.all), mode: .list,
                                                                                         selectFirst: 2))
        }
        register("w-files.file-bank-icons") { env in
            FileBankDebug.bank(env, item: "Main engine", initial: FileBankInitialState(scope: .tab(.all), mode: .icons,
                                                                                         selectFirst: 1), height: 420)
        }
        register("w-files.file-bank-images") { env in
            FileBankDebug.bank(env, item: "Main engine", initial: FileBankInitialState(scope: .tab(.images), mode: .list))
        }
        register("w-files.file-bank-links") { env in
            FileBankDebug.bank(env, item: "Main engine", initial: FileBankInitialState(scope: .tab(.links), mode: .list))
        }
        register("w-files.file-bank-shared") { env in
            FileBankDebug.bank(env, item: "Main engine", initial: FileBankInitialState(scope: .shared, mode: .list))
        }
        register("w-files.file-bank-narrow") { env in
            FileBankDebug.bank(env, item: "Main engine", initial: FileBankInitialState(scope: .tab(.all), mode: .list),
                               width: 640)
        }
        register("w-files.file-bank-empty") { env in
            FileBankDebug.bank(env, item: "Cargo pump 1", initial: FileBankInitialState())
        }
        register("w-files.viewer") { env in
            let c = FileBankDebug.savedListItemContainer(env) ?? Container()
            return AnyView(ContainerViewerSheet(title: "Check lube oil", container: FileBankDebug.absolutized(c, env),
                                                subtitle: FileBankText.savedListSubtitle(listName: "Engine rounds")))
        }
        register("w-files.viewer-empty") { _ in
            AnyView(ContainerViewerSheet(title: "Close sea chest valves", container: Container()))
        }
        register("w-files.backlinks") { env in
            let id = env.store.data.equipment.first { $0.name == "Main engine" }?.id ?? UUID()
            return AnyView(FileBacklinksSection(itemID: id)
                .padding(AASpacing.l)
                .frame(width: 620)
                .background(AAColor.panel))
        }
    }
}

@MainActor enum FileBankDebug {
    static func bank(_ env: AppEnvironment, item name: String, initial: FileBankInitialState, width: CGFloat = 1040,
                     height: CGFloat = 330) -> AnyView {
        let source = env.store.allItems().first { $0.name == name }?.container ?? Container()
        let c = absolutized(source, env)
        return AnyView(FileBankView(container: c, context: FileBankContext(host: .mainPane(.equipment)), initial: initial)
            .frame(width: width, height: height))
    }

    static func savedListItemContainer(_ env: AppEnvironment) -> Container? {
        env.store.data.checklistTemplates.first?.items.first?.container
    }

    /// A display copy whose `files/…` copies point at the scratch data folder by absolute path, so thumbnails and
    /// Quick Look work whatever the attachment resolver of this build is. Same ids (sharing and links resolve).
    static func absolutized(_ c: Container, _ env: AppEnvironment) -> Container {
        let folder = env.dataStore.appFolder
        let files = c.files.map { f -> FileItem in
            let p = (!f.isLink && !f.linkInPlace && f.path.hasPrefix("files/")) ? folder.appending(path: f.path).path : f.path
            return FileItem(id: f.id, name: f.name, path: p, kind: f.kind, added: f.added, isLink: f.isLink,
                            linkInPlace: f.linkInPlace, linkedItemIds: f.linkedItemIds)
        }
        return Container(id: c.id, richTextXaml: c.richTextXaml, files: files,
                         sharedWithContainerIds: c.sharedWithContainerIds, isLocked: c.isLocked)
    }
}
