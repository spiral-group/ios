//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: extracts the approve/reject notification-
// action plumbing out of AppCoordinator to keep that file under
// SwiftLint's `type_body_length` cap.
//
// Lifecycle:
//   1. User taps Approve or Reject on a notification.
//   2. Main app's UNUserNotificationCenterDelegate dispatches to
//      `AppCoordinator.handleApprovalAction(_:content:decision:)`.
//   3. AppCoordinator forwards to `ApprovalActionRunner.run(...)`,
//      passing in the live `userSession` resolver (the session
//      may still be coming up if iOS cold-launched us).
//   4. The runner guards the POST with `beginBackgroundTask`,
//      waits up to 5s for the session, calls
//      `decideApproval(id:decision:)`, and on failure enqueues
//      to `PendingApprovalActionStore` + posts a local
//      "couldn't deliver" notification. A refusal (the owner
//      blocked the card's target) is neither a success nor a
//      retry: a local "not sent" notification says why.
//
// Tested via injected dependencies — see ApprovalActionRunnerTests.

import Foundation
@preconcurrency import UIKit
import UserNotifications

/// Resolves an `AgentPlatformServiceProtocol` once the user
/// session has come up. Returns nil during the bootstrap window
/// before login or while iOS is cold-launching us; the runner
/// polls this for up to `sessionWaitBudget` before giving up.
typealias AgentPlatformServiceResolver = () -> AgentPlatformServiceProtocol?

@MainActor
final class ApprovalActionRunner {
    private let resolveService: AgentPlatformServiceResolver
    private let pendingStore: PendingApprovalActionStore?
    private let notificationCenter: UserNotificationCenterProtocol
    private let strings: ApprovalActionRunnerStrings

    /// Maximum time we wait for the user session to come up
    /// before giving up and enqueueing for the next foreground.
    /// 5s is well under the ~25s `beginBackgroundTask` budget
    /// so we leave headroom for the POST itself.
    static let sessionWaitBudget: TimeInterval = 5

    init(resolveService: @escaping AgentPlatformServiceResolver,
         pendingStore: PendingApprovalActionStore?,
         notificationCenter: UserNotificationCenterProtocol = UNUserNotificationCenter.current(),
         strings: ApprovalActionRunnerStrings = .live) {
        self.resolveService = resolveService
        self.pendingStore = pendingStore
        self.notificationCenter = notificationCenter
        self.strings = strings
    }

    /// Run the approve/reject POST. Returns when done — caller
    /// is expected to be the notification delegate which itself
    /// awaits and then signals iOS via the completion handler.
    func run(approvalID: String,
             decision: ApprovalDecision,
             userInfo: [AnyHashable: Any],
             threadIdentifier: String?) async {
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "agent-platform.approval.\(approvalID)",
                                                              expirationHandler: nil)
        defer {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
            }
        }

        // Wait briefly for the session — iOS may have cold-
        // launched us into the background.
        let service = await waitForService()
        guard let service else {
            MXLog.error("ApprovalActionRunner: no session after wait — enqueueing for next foreground")
            pendingStore?.enqueue(approvalID: approvalID, decision: decision)
            await postFailureNotification(for: approvalID,
                                          userInfo: userInfo,
                                          threadIdentifier: threadIdentifier)
            return
        }

        switch await service.decideApproval(id: approvalID, decision: decision) {
        case .success:
            MXLog.info("ApprovalActionRunner: succeeded for \(approvalID)")
            pendingStore?.markCompleted(approvalID: approvalID)
        case .failure(.conflict):
            // Already decided elsewhere (likely another device).
            // Idempotent on the server; drop the queue entry.
            MXLog.info("ApprovalActionRunner: 409 conflict for \(approvalID), treating as success")
            pendingStore?.markCompleted(approvalID: approvalID)
        case .failure(.targetBlocked):
            // Refused, not decided: the owner blocked the card's target, so
            // the platform closed the card. No retry can change that.
            MXLog.info("ApprovalActionRunner: \(approvalID) refused — target blocked, card closed")
            pendingStore?.markCompleted(approvalID: approvalID)
            await postTargetBlockedNotification(for: approvalID, threadIdentifier: threadIdentifier)
        case .failure(.approvalNotFound):
            // The card is gone (its person was erased, so it was deleted and
            // nothing was sent): final, like a blocked target. A bare 404 is
            // not this: it is retried below.
            MXLog.info("ApprovalActionRunner: \(approvalID) is gone (404) — nothing to decide")
            pendingStore?.markCompleted(approvalID: approvalID)
            await postGoneNotification(for: approvalID, threadIdentifier: threadIdentifier)
        case .failure(.agentPaused):
            // Refused, not decided: the card stays pending. Not queued — a
            // replay after the resume would act on a tap made while paused.
            MXLog.info("ApprovalActionRunner: \(approvalID) refused — the agent is paused")
            pendingStore?.markCompleted(approvalID: approvalID)
            await postAgentPausedNotification(for: approvalID, threadIdentifier: threadIdentifier)
        case .failure(.unauthorized):
            // Can't refresh interactively from a background launch
            // — surface a "sign in required" notification that
            // opens the app instead.
            MXLog.warning("ApprovalActionRunner: 401 for \(approvalID) — needs interactive auth")
            await postAuthRequiredNotification(for: approvalID,
                                               userInfo: userInfo,
                                               threadIdentifier: threadIdentifier)
        case .failure(let error):
            MXLog.error("ApprovalActionRunner: decide failed: \(error) — enqueueing for retry")
            pendingStore?.enqueue(approvalID: approvalID, decision: decision)
            await postFailureNotification(for: approvalID,
                                          userInfo: userInfo,
                                          threadIdentifier: threadIdentifier)
        }
    }

    /// Replay every retriable queued action. Called by
    /// `AppCoordinator.applicationDidBecomeActive`.
    func reconcile() async {
        guard let pendingStore else { return }
        let pending = pendingStore.retriable()
        if pending.isEmpty { return }
        guard let service = resolveService() else {
            MXLog.warning("ApprovalActionRunner: reconcile skipped — no session")
            return
        }
        MXLog.info("ApprovalActionRunner: replaying \(pending.count) queued action(s)")
        for entry in pending {
            switch await service.decideApproval(id: entry.approvalID, decision: entry.decision) {
            case .success, .failure(.conflict):
                pendingStore.markCompleted(approvalID: entry.approvalID)
            case .failure(.targetBlocked):
                MXLog.info("ApprovalActionRunner: queued \(entry.approvalID) refused — target blocked, card closed")
                pendingStore.markCompleted(approvalID: entry.approvalID)
                await postTargetBlockedNotification(for: entry.approvalID, threadIdentifier: nil)
            case .failure(.approvalNotFound):
                MXLog.info("ApprovalActionRunner: queued \(entry.approvalID) is gone (404)")
                pendingStore.markCompleted(approvalID: entry.approvalID)
                await postGoneNotification(for: entry.approvalID, threadIdentifier: nil)
            case .failure(.agentPaused):
                MXLog.info("ApprovalActionRunner: queued \(entry.approvalID) refused — the agent is paused")
                pendingStore.markCompleted(approvalID: entry.approvalID)
                await postAgentPausedNotification(for: entry.approvalID, threadIdentifier: nil)
            case .failure(let error):
                MXLog.warning("ApprovalActionRunner: still failing for \(entry.approvalID): \(error)")
                pendingStore.incrementAttempt(approvalID: entry.approvalID)
            }
        }
    }

    // MARK: - Private

    private func waitForService() async -> AgentPlatformServiceProtocol? {
        if let service = resolveService() { return service }
        var waited: TimeInterval = 0
        let pollInterval: TimeInterval = 0.2
        while waited < Self.sessionWaitBudget {
            try? await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
            waited += pollInterval
            if let service = resolveService() { return service }
        }
        return nil
    }

    private func postFailureNotification(for approvalID: String,
                                         userInfo: [AnyHashable: Any],
                                         threadIdentifier: String?) async {
        let failure = UNMutableNotificationContent()
        failure.title = strings.failureTitle
        failure.body = strings.failureBody
        failure.userInfo = userInfo
        failure.categoryIdentifier = NotificationConstants.Category.approval
        if let threadIdentifier { failure.threadIdentifier = threadIdentifier }
        failure.interruptionLevel = .active
        await postNotification(failure, identifier: Self.failureNotificationIdentifier(approvalID))
    }

    /// Plain, without the approval category or its route: Approve would only
    /// be refused again, and the card it opens is closed. It replaces this
    /// card's "couldn't deliver", whose retry cannot succeed.
    private func postTargetBlockedNotification(for approvalID: String, threadIdentifier: String?) async {
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [Self.failureNotificationIdentifier(approvalID)])
        let refused = UNMutableNotificationContent()
        refused.title = strings.targetBlockedTitle
        refused.body = strings.targetBlockedBody
        if let threadIdentifier { refused.threadIdentifier = threadIdentifier }
        refused.interruptionLevel = .active
        await postNotification(refused, identifier: "agent-platform.approval-refused.\(approvalID)")
    }

    /// Plain, like the blocked-target notice: there is no card left to open or
    /// decide. It replaces this card's "couldn't deliver".
    private func postGoneNotification(for approvalID: String, threadIdentifier: String?) async {
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [Self.failureNotificationIdentifier(approvalID)])
        let gone = UNMutableNotificationContent()
        gone.title = strings.notFoundTitle
        gone.body = strings.notFoundBody
        if let threadIdentifier { gone.threadIdentifier = threadIdentifier }
        gone.interruptionLevel = .active
        await postNotification(gone, identifier: "agent-platform.approval-gone.\(approvalID)")
    }

    /// Plain: Approve would only be refused again until the resume. The card
    /// stays in the hub, to decide then. It replaces this card's "couldn't deliver".
    private func postAgentPausedNotification(for approvalID: String, threadIdentifier: String?) async {
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [Self.failureNotificationIdentifier(approvalID)])
        let paused = UNMutableNotificationContent()
        paused.title = strings.agentPausedTitle
        paused.body = strings.agentPausedBody
        if let threadIdentifier { paused.threadIdentifier = threadIdentifier }
        paused.interruptionLevel = .active
        await postNotification(paused, identifier: "agent-platform.approval-paused.\(approvalID)")
    }

    private static func failureNotificationIdentifier(_ approvalID: String) -> String {
        "agent-platform.approval-failed.\(approvalID)"
    }

    private func postAuthRequiredNotification(for approvalID: String,
                                              userInfo: [AnyHashable: Any],
                                              threadIdentifier: String?) async {
        let auth = UNMutableNotificationContent()
        auth.title = strings.authRequiredTitle
        auth.body = strings.authRequiredBody
        auth.userInfo = userInfo
        auth.categoryIdentifier = NotificationConstants.Category.approval
        if let threadIdentifier { auth.threadIdentifier = threadIdentifier }
        auth.interruptionLevel = .active
        await postNotification(auth, identifier: "agent-platform.approval-auth.\(approvalID)")
    }

    private func postNotification(_ content: UNNotificationContent, identifier: String) async {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await notificationCenter.add(request)
    }
}

/// Externalises the localised strings the runner uses so
/// tests don't depend on the SwiftGen-generated L10n constants.
nonisolated struct ApprovalActionRunnerStrings {
    let failureTitle: String
    let failureBody: String
    let authRequiredTitle: String
    let authRequiredBody: String
    let targetBlockedTitle: String
    let targetBlockedBody: String
    let notFoundTitle: String
    let notFoundBody: String
    let agentPausedTitle: String
    let agentPausedBody: String

    static let live = ApprovalActionRunnerStrings(failureTitle: UntranslatedL10n.notificationApprovalActionFailedTitle,
                                                  failureBody: UntranslatedL10n.notificationApprovalActionFailedBody,
                                                  authRequiredTitle: UntranslatedL10n.notificationApprovalActionAuthRequiredTitle,
                                                  authRequiredBody: UntranslatedL10n.notificationApprovalActionAuthRequiredBody,
                                                  targetBlockedTitle: UntranslatedL10n.notificationApprovalActionTargetBlockedTitle,
                                                  targetBlockedBody: UntranslatedL10n.notificationApprovalActionTargetBlockedBody,
                                                  notFoundTitle: UntranslatedL10n.notificationApprovalActionNotFoundTitle,
                                                  notFoundBody: UntranslatedL10n.notificationApprovalActionNotFoundBody,
                                                  agentPausedTitle: UntranslatedL10n.notificationApprovalActionAgentPausedTitle,
                                                  agentPausedBody: UntranslatedL10n.notificationApprovalActionAgentPausedBody)
}
