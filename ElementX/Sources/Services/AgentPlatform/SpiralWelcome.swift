//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (1.0.3 A3, operator's concept A, 2026-11-20): the assistant's welcome in its chat with the person.
// The server posts the fact once, on join (`com.spiral.notice` kind `welcome`); the app writes a short hello and, until
// the person writes anything, offers three starters. Without the person's AI consent the assistant can't read what they
// write, so the welcome offers the way to allow AI instead (decision 150).
//

import Foundation

/// What the assistant's welcome offers under its hello.
enum SpiralWelcomeExtras: Equatable {
    /// Just the hello: not the person's assistant, the person has written already, or their consent is being read.
    case none
    case starters
    /// The person hasn't allowed third-party AI: starters would only bounce.
    case allowAI

    /// A read that failed still offers the starters: the assistant answers one without consent with the notice that
    /// asks for it.
    static func decide(needsStarters: Bool, consent: AgentsReadState<AIConsent>?) -> SpiralWelcomeExtras {
        guard needsStarters else { return .none }
        switch consent {
        case nil, .failed:
            return .starters
        case .loading:
            return .none
        case .loaded(let consent):
            return consent.isGranted ? .starters : .allowAI
        }
    }
}

/// The starters the welcome offers, each one of the assistant's tools in its chat with the person. Chosen for someone
/// who has just signed up: a chat to sum up, a contact to remember and a reminder need nothing they don't have yet.
/// The message is an open request the assistant follows up on with a question.
enum SpiralWelcomeStarter: CaseIterable {
    case summary
    case contact
    case reminder

    var title: String {
        switch self {
        case .summary: UntranslatedL10n.noticeWelcomeStarterSummary
        case .contact: UntranslatedL10n.noticeWelcomeStarterContact
        case .reminder: UntranslatedL10n.noticeWelcomeStarterReminder
        }
    }

    var message: String {
        switch self {
        case .summary: UntranslatedL10n.noticeWelcomeStarterSummaryMessage
        case .contact: UntranslatedL10n.noticeWelcomeStarterContactMessage
        case .reminder: UntranslatedL10n.noticeWelcomeStarterReminderMessage
        }
    }
}

/// Follows what a timeline's welcome offers: whether its sender is the person's own assistant, whether the person has
/// written since, and their AI consent, read for as long as the starters may show. Anyone can post a notice, so only the
/// person's own personal assistant's welcome, as their agent spaces name it, gets starters.
final class SpiralWelcomeWatch {
    private let store: AgentsStore?
    private let onChange: (SpiralWelcomeExtras) -> Void
    /// The sender of a personal welcome the person hasn't answered yet.
    private var pendingWelcomeSender: String?
    private var isShowing = false
    /// A starter was sent: they stay hidden while the timeline catches up with the message.
    private var hasSentStarter = false

    init(store: AgentsStore?, onChange: @escaping (SpiralWelcomeExtras) -> Void) {
        self.store = store
        self.onChange = onChange
        store?.observe { [weak self] in
            guard let self else { return false }
            if isShowing {
                deliver()
            }
            return true
        }
    }

    isolated deinit {
        if isShowing {
            store?.stopShowing(.spaces, by: self)
            store?.stopShowing(.aiConsent, by: self)
        }
    }

    /// `welcomeSender`: who posted the personal welcome the timeline holds, nil without one. `ownerHasWritten`: it
    /// holds a message of the person's, a starter's included.
    func update(welcomeSender: String?, ownerHasWritten: Bool) {
        pendingWelcomeSender = ownerHasWritten || hasSentStarter ? nil : welcomeSender
        let needsReads = pendingWelcomeSender != nil
        if let store, needsReads != isShowing {
            isShowing = needsReads
            if needsReads {
                store.show(.spaces, by: self)
                store.show(.aiConsent, by: self)
            } else {
                store.stopShowing(.spaces, by: self)
                store.stopShowing(.aiConsent, by: self)
            }
        }
        deliver()
    }

    func noteStarterSent() {
        hasSentStarter = true
        update(welcomeSender: nil, ownerHasWritten: true)
    }

    private func deliver() {
        let isOwnAssistant = pendingWelcomeSender.flatMap { store?.card(matrixUserID: $0) }?.isPersonalAssistant == true
        onChange(SpiralWelcomeExtras.decide(needsStarters: isOwnAssistant,
                                            consent: store?.readState(.aiConsent) { $0.aiConsent }))
    }
}
