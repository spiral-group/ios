//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0072, ADR-0084): «Share presence» belongs to the account.
//
// The toggle in Advanced settings (`AccountSettings.sharePresence`, upstream) is a
// device setting: it decides what THIS device sends (presence, public read
// receipts, typing). Presence privacy is the server's (ADR-0084): Synapse
// reads the global account data `com.spiral.presence` `{"share": Bool}` to
// decide what others may see of the user — and what the user may see of
// others. This keeps the two in step:
//
// - a toggle here is written to the account data, one write at a time, the
//   latest value last, retried on the next sync until it lands;
// - after every sync the synced account data is read, and a value set on
//   another device wins;
// - our own write takes a sync or two to come back: until it does (or
//   `echoSyncs` syncs pass without it — another device changed it since),
//   the stale synced value is not taken for an answer;
// - never written on the server and this device does not share: written as
//   `false`, the direction that only hides more. A fresh install, sharing by
//   default, never overwrites a choice made elsewhere.
//

import Combine
import Foundation

final class SharePresenceSettingSync {
    static let accountDataType = "com.spiral.presence"
    
    private let clientProxy: ClientProxyProtocol
    private let accountSettings: AccountSettings
    private let echoSyncs: Int
    private var cancellables = Set<AnyCancellable>()
    
    /// Toggled on this device, not yet accepted by the server.
    private var pendingValue: Bool?
    private var isWriting = false
    /// Accepted by the server, not yet seen back through sync.
    private var awaitingEcho: (value: Bool, syncsLeft: Int)?
    /// Set while a value read from the server is applied locally, so the
    /// local change it causes is not written straight back.
    private var applyingServerValue = false
    
    init(clientProxy: ClientProxyProtocol,
         accountSettings: AccountSettings,
         syncThrottle: DispatchQueue.SchedulerTimeType.Stride = .seconds(5),
         echoSyncs: Int = 3) {
        self.clientProxy = clientProxy
        self.accountSettings = accountSettings
        self.echoSyncs = echoSyncs
        
        accountSettings.sharePresencePublisher
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] share in self?.localValueChanged(share) }
            .store(in: &cancellables)
        
        // The first sync after launch reads what changed while the app was
        // closed; there is nothing to reconcile before it.
        clientProxy.actionsPublisher
            .filter(\.isSyncUpdate)
            .throttle(for: syncThrottle, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                Task { await self?.reconcile() }
            }
            .store(in: &cancellables)
    }
    
    /// Bring the device setting and the account data together: push what is
    /// pending, or take what the server holds.
    func reconcile() async {
        if pendingValue != nil {
            await flush()
            return
        }
        guard case let .success(json) = await clientProxy.accountData(eventType: Self.accountDataType) else {
            return
        }
        let serverValue = json.flatMap(Self.share(fromJSON:))
        
        if let awaitingEcho {
            if serverValue != awaitingEcho.value, awaitingEcho.syncsLeft > 1 {
                self.awaitingEcho = (awaitingEcho.value, awaitingEcho.syncsLeft - 1)
                return
            }
            self.awaitingEcho = nil
        }
        
        if let serverValue {
            guard serverValue != accountSettings.sharePresence else { return }
            MXLog.info("Share presence set to \(serverValue) on another device")
            applyingServerValue = true
            accountSettings.sharePresence = serverValue
            applyingServerValue = false
        } else if !accountSettings.sharePresence {
            pendingValue = false
            await flush()
        }
    }
    
    /// `{"share": Bool}` from the synced event (`{"type", "content"}`) or from
    /// bare content. Anything else is no answer.
    static func share(fromJSON json: String) -> Bool? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let content = (object["content"] as? [String: Any]) ?? object
        // `as? Bool` would take the number 0 or 1 for a Bool; the server's
        // rule is the JSON literal `false` only.
        guard let share = content["share"] as? NSNumber, CFGetTypeID(share) == CFBooleanGetTypeID() else {
            return nil
        }
        return share.boolValue
    }
    
    // MARK: - Private
    
    private func localValueChanged(_ share: Bool) {
        guard !applyingServerValue else { return }
        pendingValue = share
        Task { await flush() }
    }
    
    /// Writes until nothing is pending. One writer at a time: a toggle while
    /// a write is in flight is picked up after it, so the server ends with the
    /// latest value whatever order the requests would have finished in.
    private func flush() async {
        guard !isWriting else { return }
        isWriting = true
        defer { isWriting = false }
        
        while let value = pendingValue {
            switch await clientProxy.setAccountData(eventType: Self.accountDataType, content: #"{"share":\#(value)}"#) {
            case .success:
                awaitingEcho = (value, echoSyncs)
                if pendingValue == value {
                    pendingValue = nil
                }
            case .failure(let error):
                // Kept pending: the next sync retries.
                MXLog.error("Failed writing \(Self.accountDataType): \(error)")
                return
            }
        }
    }
}
