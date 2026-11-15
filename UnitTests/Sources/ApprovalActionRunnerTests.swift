//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: what a lock-screen Approve / Reject leaves behind for each
// answer of the decide route — the retry queue and the local notification.
//

import Foundation
@testable import Spiral
import Testing
import UserNotifications

@MainActor
struct ApprovalActionRunnerTests {
    private let service = AgentPlatformServiceMock()
    private let notificationCenter = UserNotificationCenterMock()
    private let pendingStore: PendingApprovalActionStore
    private let runner: ApprovalActionRunner

    init() throws {
        let suite = "test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        pendingStore = PendingApprovalActionStore(userDefaults: defaults)
        runner = ApprovalActionRunner(resolveService: { [service] in service },
                                      pendingStore: pendingStore,
                                      notificationCenter: notificationCenter,
                                      strings: Self.strings)
    }

    // MARK: - From the lock screen

    /// An approve of a cold-outreach card to someone the owner blocked is
    /// refused and the card closed: the owner hears it was not sent, and it
    /// is not queued, because no retry can change the answer.
    @Test
    func aRefusedApproveSaysNotSentAndIsNotQueued() async {
        service.decideApprovalIdDecisionReturnValue = .failure(.targetBlocked)

        await runner.run(approvalID: "appr-1", decision: .approve, userInfo: Self.userInfo, threadIdentifier: "thread-1")

        #expect(pendingStore.allPending().isEmpty)
        #expect(notificationCenter.addCallsCount == 1)
        let request = notificationCenter.addReceivedRequest
        #expect(request?.identifier == "agent-platform.approval-refused.appr-1")
        #expect(request?.content.title == Self.strings.targetBlockedTitle)
        #expect(request?.content.body == Self.strings.targetBlockedBody)
        #expect(request?.content.threadIdentifier == "thread-1")
        // No Approve / Reject on it and no route to the closed card.
        #expect(request?.content.categoryIdentifier.isEmpty == true)
        #expect(request?.content.userInfo.isEmpty == true)
        // An earlier "couldn't deliver" for this card offers a retry that cannot succeed.
        #expect(notificationCenter.removeDeliveredNotificationsWithIdentifiersReceivedIdentifiers == ["agent-platform.approval-failed.appr-1"])
    }

    /// A paused agent's card: nothing was decided. The owner hears so, and
    /// the tap is not queued — a replay after the resume would act on it later.
    @Test
    func anApproveWhilePausedSaysSoAndIsNotQueued() async {
        service.decideApprovalIdDecisionReturnValue = .failure(.agentPaused)

        await runner.run(approvalID: "appr-1", decision: .approve, userInfo: Self.userInfo, threadIdentifier: "thread-1")

        #expect(pendingStore.allPending().isEmpty)
        let request = notificationCenter.addReceivedRequest
        #expect(request?.identifier == "agent-platform.approval-paused.appr-1")
        #expect(request?.content.title == Self.strings.agentPausedTitle)
        #expect(request?.content.body == Self.strings.agentPausedBody)
        #expect(request?.content.categoryIdentifier.isEmpty == true)
    }

    @Test
    func aQueuedApproveWhilePausedIsDropped() async {
        pendingStore.enqueue(approvalID: "appr-1", decision: .approve)
        service.decideApprovalIdDecisionReturnValue = .failure(.agentPaused)

        await runner.reconcile()

        #expect(pendingStore.allPending().isEmpty)
        #expect(notificationCenter.addReceivedRequest?.identifier == "agent-platform.approval-paused.appr-1")
    }

    /// Already decided elsewhere: idempotent, nothing to tell.
    @Test
    func anAlreadyDecidedApproveIsDroppedQuietly() async {
        pendingStore.enqueue(approvalID: "appr-1", decision: .approve)
        service.decideApprovalIdDecisionReturnValue = .failure(.conflict(detail: "approval has already been decided"))

        await runner.run(approvalID: "appr-1", decision: .approve, userInfo: Self.userInfo, threadIdentifier: nil)

        #expect(pendingStore.allPending().isEmpty)
        #expect(!notificationCenter.addCalled)
    }

    /// Anything else is queued for the next foreground, with a notification
    /// that keeps the Approve / Reject actions.
    @Test
    func aFailedApproveIsQueuedForRetry() async {
        service.decideApprovalIdDecisionReturnValue = .failure(.serverError(status: 500))

        await runner.run(approvalID: "appr-1", decision: .approve, userInfo: Self.userInfo, threadIdentifier: nil)

        #expect(pendingStore.allPending().map(\.approvalID) == ["appr-1"])
        #expect(notificationCenter.addReceivedRequest?.identifier == "agent-platform.approval-failed.appr-1")
        #expect(notificationCenter.addReceivedRequest?.content.categoryIdentifier == NotificationConstants.Category.approval)
    }

    // MARK: - A card that is gone

    /// The platform answers 404 `/errors/approval-not-found` when the card is
    /// gone: its person was erased, so it was deleted and nothing was sent.
    /// That is final, like a target the owner blocked. It went to the retry
    /// queue, which replayed it into the same 404 five times, with a
    /// "couldn't deliver" offering a retry.
    @Test
    func aDecideOfACardThatIsGoneIsFinalAndNotQueued() async {
        service.decideApprovalIdDecisionReturnValue = .failure(.approvalNotFound)

        await runner.run(approvalID: "appr-1", decision: .approve, userInfo: Self.userInfo, threadIdentifier: "thread-1")

        #expect(pendingStore.allPending().isEmpty, "no retry can bring the card back")
        let request = notificationCenter.addReceivedRequest
        #expect(request?.identifier == "agent-platform.approval-gone.appr-1")
        #expect(request?.content.title == Self.strings.notFoundTitle)
        #expect(request?.content.body == Self.strings.notFoundBody)
        #expect(request?.content.categoryIdentifier.isEmpty == true, "no actions and no route to a card that is gone")
        #expect(notificationCenter.removeDeliveredNotificationsWithIdentifiersReceivedIdentifiers == ["agent-platform.approval-failed.appr-1"])
    }

    /// A queued decide that meets the 404 on replay leaves the queue too.
    @Test
    func aQueuedDecideOfACardThatIsGoneLeavesTheQueue() async {
        pendingStore.enqueue(approvalID: "appr-1", decision: .reject)
        service.decideApprovalIdDecisionReturnValue = .failure(.approvalNotFound)

        await runner.reconcile()

        #expect(pendingStore.allPending().isEmpty)
        #expect(notificationCenter.addReceivedRequest?.identifier == "agent-platform.approval-gone.appr-1")
    }

    /// A bare `/errors/not-found` is also a route the platform does not serve
    /// (one a deploy can bring), so it says nothing about the card: retried.
    @Test
    func aBareNotFoundOnDecideIsQueuedForRetry() async {
        service.decideApprovalIdDecisionReturnValue = .failure(.notFound)

        await runner.run(approvalID: "appr-1", decision: .reject, userInfo: Self.userInfo, threadIdentifier: nil)

        #expect(pendingStore.allPending().map(\.approvalID) == ["appr-1"])
        #expect(notificationCenter.addReceivedRequest?.identifier == "agent-platform.approval-failed.appr-1")
    }

    @Test
    func aQueuedDecideThatMeetsABareNotFoundCountsAnAttempt() async {
        pendingStore.enqueue(approvalID: "appr-1", decision: .reject)
        service.decideApprovalIdDecisionReturnValue = .failure(.notFound)

        await runner.reconcile()

        #expect(pendingStore.allPending().map(\.attempts) == [2])
        #expect(!notificationCenter.addCalled)
    }

    // MARK: - Replayed on the next foreground

    /// A queued approve that the platform now refuses leaves the queue and
    /// says so; it is not retried again.
    @Test
    func aQueuedApproveRefusedOnReplayLeavesTheQueueAndSaysSo() async {
        pendingStore.enqueue(approvalID: "appr-1", decision: .approve)
        service.decideApprovalIdDecisionReturnValue = .failure(.targetBlocked)

        await runner.reconcile()

        #expect(pendingStore.allPending().isEmpty)
        #expect(notificationCenter.addCallsCount == 1)
        #expect(notificationCenter.addReceivedRequest?.identifier == "agent-platform.approval-refused.appr-1")
        #expect(notificationCenter.addReceivedRequest?.content.title == Self.strings.targetBlockedTitle)
        #expect(notificationCenter.removeDeliveredNotificationsWithIdentifiersReceivedIdentifiers == ["agent-platform.approval-failed.appr-1"])
    }

    @Test
    func aQueuedApproveThatStillFailsCountsAnAttempt() async {
        pendingStore.enqueue(approvalID: "appr-1", decision: .approve)
        service.decideApprovalIdDecisionReturnValue = .failure(.serverError(status: 500))

        await runner.reconcile()

        #expect(pendingStore.allPending().map(\.attempts) == [2])
        #expect(!notificationCenter.addCalled)
    }

    // MARK: - Fixtures

    static let strings = ApprovalActionRunnerStrings(failureTitle: "Couldn't deliver",
                                                     failureBody: "Try again",
                                                     authRequiredTitle: "Sign in",
                                                     authRequiredBody: "Open the app",
                                                     targetBlockedTitle: "Not sent",
                                                     targetBlockedBody: "You blocked them",
                                                     notFoundTitle: "Gone",
                                                     notFoundBody: "Nothing was sent",
                                                     agentPausedTitle: "Paused",
                                                     agentPausedBody: "Resume it")

    static let userInfo: [AnyHashable: Any] = [NotificationConstants.UserInfoKey.agentApprovalIdentifier: "appr-1"]
}
