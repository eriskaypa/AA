// Spec: 01 DATA-049, §3.10 `ApplySyncedData` (Flash Sync apply; also the DATA-181 conflict-copy restore), DATA-179
//       (external-file lock released when the active file goes back to the default), D-3 (validate before writing),
//       DATA-174 / §MP.3.5 (refused while the write gate is closed);
//       ARCHITECTURE.md §6.6.
import Foundation

extension DataStore {
    /// Points the active file at the default, writes `json` through the local-encryption policy, loads it back
    /// (schema migration + normalisation), migrates legacy absolute attachment paths, rewrites it and persists the
    /// active file in settings. Never touches `files/`. The caller has already shown the user what will change.
    /// Invalid JSON (or a document that does not decode) throws before anything is written (D-3, P2).
    public func applySyncedData(_ json: Data) throws -> AppData {
        try PersistWriteGate.check(self)                                           // DATA-174, §MP.3.5
        try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        let text = json.starts(with: [0xEF, 0xBB, 0xBF]) ? json.dropFirst(3) : json
        do {
            _ = try decode(try JSONParser.parse(text))
        } catch let e as DataLoadError {
            throw e
        } catch let e as JSONParseError {
            throw DataLoadError.parse(e)
        }
        setCurrentDataFile(defaultDataFile)
        InstanceGuard.releaseExternal()
        try persistWriteReplacing(Data(text), to: defaultDataFile)
        let data = try loadFrom(defaultDataFile)
        AttachmentStore.migrateLegacyAbsolutePaths(self, data: data)
        try persistWriteReplacing(try serializeForSave(data), to: defaultDataFile)
        return data
    }
}
