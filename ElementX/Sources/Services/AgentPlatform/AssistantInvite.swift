//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (1.0.3 A2, ADR-0017): the person's own assistant asking for its chat with them. The server creates
// that chat once, when it sets the assistant up, and never invites again, so declining it would lose the assistant's
// chat for good. Accepting stays the person's own tap: it is the consent.
//

import Foundation

/// What a pending invite is to the person, as far as their assistant goes.
enum AssistantInvite: Equatable {
    /// Not an assistant's chat invite, or someone else's assistant.
    case none
    /// An assistant's chat invite whose owner isn't known yet. `isReading`: an answer is on its way.
    case unconfirmed(isReading: Bool)
    /// The person's own assistant asking for their chat.
    case own
    /// An assistant's chat invite whose owner still isn't known after the wait (a platform that keeps failing, a
    /// provisioning that never ends, another server's assistant). Decline is offered, but only behind a warning that
    /// the person's own assistant's chat couldn't be restored.
    case undetermined

    /// Declining the assistant's chat would end it for good, so it's offered only for an invite known not to be it, or,
    /// with a warning, once its owner couldn't be told for a while.
    var allowsDecline: Bool {
        self == .none || self == .undetermined
    }

    /// Declining it says first that the person's own assistant's chat can't be restored afterwards.
    var declineNeedsWarning: Bool {
        self == .undetermined
    }

    /// The server's assistants send their chat invite as a direct one; only the person's own personal assistant counts.
    /// `ownership` is nil without the agent platform.
    static func recognise(inviterID: String?, isDirect: Bool, ownership: (String) -> AgentOwnership?) -> AssistantInvite {
        guard isDirect, let inviterID, SpiralAppPostSession.agentIDKind(inviterID) == .assistant,
              let ownership = ownership(inviterID) else {
            return .none
        }

        switch ownership {
        case .own(let card):
            return card.isPersonalAssistant ? .own : .none
        case .someoneElses:
            return .none
        case .unknown(let isReading):
            return .unconfirmed(isReading: isReading)
        }
    }

    /// Whether an invite from `inviterID` may be the person's assistant's, before its owner is known.
    static func isCandidate(inviterID: String?, isDirect: Bool) -> Bool {
        guard isDirect, let inviterID else { return false }
        return SpiralAppPostSession.agentIDKind(inviterID) == .assistant
    }
}

/// Keeps the person's agent spaces read while a screen holds an assistant's invite, and tells whose assistant asks.
///
/// Two answers are checked before they're trusted. «Someone else's» is read again once: spaces read before the
/// person's assistant existed (a new account's first minute) say so of their own assistant too. «Can't tell» hides
/// Decline for a while, a read on its way or not; once the bound passes without an answer the invite is `undetermined`
/// until a real answer comes, so a stranger's assistant can still be declined and blocked, behind a warning (1.0.3).
/// Later reads don't hide Decline again, and the bound's timer is the re-render that ends a join screen's wait.
final class AssistantInviteSpacesWatch {
    private let store: AgentsStore
    private let onChange: () -> Void
    private let unconfirmedLimit: Duration
    private var isShowing = false
    /// Inviters whose «someone else's» is being read again, and those whose answer survived that read.
    private var rechecking: Set<String> = []
    private var rechecked: Set<String> = []
    /// Since when each inviter's owner hasn't been told; reset by an answer.
    private var unconfirmedSince: [String: ContinuousClock.Instant] = [:]
    private var limitTasks: [String: Task<Void, Never>] = [:]

    init(store: AgentsStore, unconfirmedLimit: Duration = .seconds(30), onChange: @escaping () -> Void) {
        self.store = store
        self.unconfirmedLimit = unconfirmedLimit
        self.onChange = onChange
        store.observe { [weak self] in
            guard let self else { return false }
            if isShowing {
                self.onChange()
            }
            return true
        }
    }

    isolated deinit {
        limitTasks.values.forEach { $0.cancel() }
        if isShowing {
            store.stopShowing(.spaces, by: self)
        }
    }

    /// What the invite is to the person; reads the spaces while it may be their assistant's.
    func invite(inviterID: String?, isDirect: Bool) -> AssistantInvite {
        guard AssistantInvite.isCandidate(inviterID: inviterID, isDirect: isDirect), let inviterID else { return .none }
        update(isNeeded: true)
        let ownership = ownership(of: inviterID)
        if case .unknown = ownership, let since = unconfirmedSince[inviterID], ContinuousClock.now - since >= unconfirmedLimit {
            return .undetermined
        }
        return AssistantInvite.recognise(inviterID: inviterID, isDirect: isDirect) { _ in ownership }
    }

    /// Reads the spaces while an assistant's invite is on screen; nothing is read for a person without one.
    func update(isNeeded: Bool) {
        guard isNeeded != isShowing else { return }
        isShowing = isNeeded
        if isNeeded {
            store.show(.spaces, by: self)
        } else {
            store.stopShowing(.spaces, by: self)
        }
    }

    /// The screen shows again: an invite whose owner couldn't be told is asked about again.
    func refreshIfUnconfirmed() {
        guard isShowing, unconfirmedSince.keys.contains(where: { store.ownership(matrixUserID: $0) == .unknown(isReading: false) }) else {
            return
        }
        store.refresh(.spaces)
    }

    private func ownership(of inviterID: String) -> AgentOwnership {
        var ownership = store.ownership(matrixUserID: inviterID)
        if ownership == .someoneElses, !rechecked.contains(inviterID) {
            recheck(inviterID)
            ownership = .unknown(isReading: true)
        }

        if case .unknown = ownership {
            if unconfirmedSince[inviterID] == nil {
                startClock(for: inviterID)
            }
        } else {
            unconfirmedSince[inviterID] = nil
            limitTasks.removeValue(forKey: inviterID)?.cancel()
        }
        return ownership
    }

    private func recheck(_ inviterID: String) {
        guard rechecking.insert(inviterID).inserted else { return }
        Task { [weak self, store] in
            await store.reread(.spaces)
            guard let self else { return }
            rechecking.remove(inviterID)
            rechecked.insert(inviterID)
            onChange()
        }
    }

    private func startClock(for inviterID: String) {
        unconfirmedSince[inviterID] = ContinuousClock.now
        limitTasks[inviterID] = Task { [weak self, unconfirmedLimit] in
            try? await Task.sleep(for: unconfirmedLimit)
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }
}
