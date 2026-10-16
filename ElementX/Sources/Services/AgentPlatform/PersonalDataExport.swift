//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0078, GDPR): what the person can take with them —
// the account export, one call's export — and the calls to choose from.
//

import Foundation

/// A call one of the caller's agents took part in, as `GET /voice-sessions`
/// lists it.
nonisolated struct VoiceSessionRecord: Equatable, Identifiable {
    let id: String
    let agentMXID: String
    let roomID: String
    let createdAt: Date
    let startedAt: Date?
    let endedAt: Date?

    var isEnded: Bool {
        endedAt != nil
    }

    /// When the call started for the assistant; a session that never got that
    /// far (declined, failed) counts from its creation.
    var date: Date {
        startedAt ?? createdAt
    }
}

nonisolated struct VoiceSessionsPage: Equatable {
    let sessions: [VoiceSessionRecord]
    let nextCursor: String?
}

/// An export written to a file the share sheet can hand on. The file holds
/// personal data: `discard()` once the sheet is gone.
nonisolated struct PersonalDataExportFile: Identifiable, Equatable {
    enum Kind: Equatable {
        case account
        case call(date: Date)
    }

    let url: URL
    var id: URL {
        url
    }

    enum WriteError: Error {
        /// The server answered 200 with something that is not a JSON object
        /// (a proxy's error page, say) — not an export.
        case notJSON
    }
    
    /// An export older than this is a leftover — its sheet is long gone, or
    /// the screen went away before the sheet opened — and is removed.
    static let leftoverAge: TimeInterval = 60 * 60
    
    static var exportsFolder: URL {
        URL.temporaryDirectory.appending(path: "PersonalDataExports", directoryHint: .isDirectory)
    }
    
    /// Writes the server's bytes, as they came, under a fresh temporary folder
    /// and removes leftover exports. The body is parsed once only to check it
    /// is a JSON object; the parse is dropped before the write.
    @concurrent
    static func write(_ data: Data, kind: Kind, now: Date = .now) async throws -> PersonalDataExportFile {
        guard isJSONObject(data) else {
            throw WriteError.notJSON
        }
        
        await removeLeftovers(now: .now)
        
        let folder = exportsFolder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        
        let url = folder.appending(path: fileName(for: kind, now: now))
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return PersonalDataExportFile(url: url)
    }
    
    @concurrent
    static func removeLeftovers(now: Date) async {
        let folders = (try? FileManager.default.contentsOfDirectory(at: exportsFolder,
                                                                    includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for folder in folders {
            guard let modified = try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(modified) > leftoverAge else {
                continue
            }
            try? FileManager.default.removeItem(at: folder)
        }
    }
    
    func discard() {
        do {
            try FileManager.default.removeItem(at: url.deletingLastPathComponent())
        } catch {
            MXLog.error("Failed to remove a personal data export: \(error)")
        }
    }

    private static func isJSONObject(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
    }
    
    static func fileName(for kind: Kind, now: Date) -> String {
        switch kind {
        case .account:
            "spiral-data-\(now.formatted(.iso8601.year().month().day())).json"
        case .call(let date):
            "spiral-call-\(date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted).timeZone(separator: .omitted))).json"
        }
    }
}
