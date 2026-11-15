//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: the Agents tab (decision 289, contract § 5 "Agents", § 7).
// The session's one copy of what the Agents tab reads: the spaces and their
// agent cards, an agent's detail, activity, usage, blocks and queue, what
// waits for the owner (the badge and the hub), public profiles, a room's
// tools, the AI consent and an agent's edit limits. Every Agents screen renders
// from here and holds only ids and its own UI state, so a change shows on every
// screen holding the item. A sync change marks what it names stale; a stale
// thing on screen is read again once, coalesced, and one off screen when it
// shows again. A failed read keeps what was shown. Nothing here is kept on disk.
//

import Foundation
import Observation

/// What the Agents tab reads, named by what a sync change says to read again.
nonisolated enum AgentsResource: Hashable, CustomStringConvertible {
    /// The spaces and every space's agent cards.
    case spaces
    /// One agent's read model, rooms and pending verifications.
    case agent(agentID: String)
    case activity(agentID: String, filter: ActionOutcomeFilter)
    case usage(agentID: String)
    case blocks(agentID: String)
    case outreach(agentID: String, status: OutreachTargetStatus?)
    /// What waits for the owner and the visitors' entries: the badges and the hub's top.
    case needsAction
    /// The hub's activity, every agent's.
    case hubActivity
    case publicProfile(userID: String)
    case roomTools(roomID: String)
    case toolsCatalog(agentID: String, roomID: String)
    /// The person's AI consent. No sync kind names it: a control that writes it reads it first (`reread`).
    case aiConsent
    /// What an agent's edit form may hold. No sync kind names it either: the limits belong to the agent's kind.
    case editSchema(agentID: String)

    var isAgent: Bool {
        if case .agent = self { true } else { false }
    }

    /// Ids only, never an MXID (a log line).
    var description: String {
        switch self {
        case .spaces: "spaces"
        case .agent(let agentID): "agent \(agentID)"
        case .activity(let agentID, let filter): "activity \(agentID) \(filter.rawValue)"
        case .usage(let agentID): "usage \(agentID)"
        case .blocks(let agentID): "blocks \(agentID)"
        case .outreach(let agentID, _): "outreach \(agentID)"
        case .needsAction: "needs action"
        case .hubActivity: "hub activity"
        case .publicProfile: "a public profile"
        case .roomTools(let roomID): "room tools \(roomID)"
        case .toolsCatalog(let agentID, let roomID): "tools catalog \(agentID) \(roomID)"
        case .aiConsent: "AI consent"
        case .editSchema(let agentID): "edit schema \(agentID)"
        }
    }

    /// The page a first read asks for; `nil` for a resource that is not paged.
    var pageSize: Int? {
        switch self {
        case .activity, .hubActivity: 25
        case .blocks: 50
        default: nil
        }
    }
}

/// The spaces as last read. A space whose read failed keeps what was read of it before.
nonisolated struct AgentsSpaces: Equatable {
    let directory: AgentSpacesDirectory
    /// By space id; a space missing here has never been read.
    let details: [String: AgentSpaceDetail]
    /// The spaces whose last read failed; what `details` holds of one is older than the directory.
    let failedSpaceIDs: Set<String>

    /// Every listed space answered its last read and no assistant is being set up,
    /// so an agent that isn't here is not the person's.
    var isComplete: Bool {
        failedSpaceIDs.isEmpty && directory.provisioningStatus != .inProgress
    }

    /// The agent's card, from whichever space holds it.
    func card(agentID: String) -> AgentSpaceAgentCard? {
        for space in directory.spaces {
            if let card = details[space.orgID]?.agents.first(where: { $0.agentID == agentID }) {
                return card
            }
        }
        return nil
    }

    /// The company whose space holds the agent, as the Agents tab names it on the agent's screen; `nil` for the
    /// Personal space.
    func companyName(agentID: String) -> String? {
        directory.spaces.first { space in
            space.kind == .company && details[space.orgID]?.agents.contains { $0.agentID == agentID } == true
        }?.displayName
    }

    /// Every agent's card by id.
    var cards: [String: AgentSpaceAgentCard] {
        var cards: [String: AgentSpaceAgentCard] = [:]
        for detail in details.values {
            for card in detail.agents {
                cards[card.agentID] = card
            }
        }
        return cards
    }
}

extension AgentSpacesDirectory {
    /// The spaces the app reads and shows. With `SpiralFeatures.companySpaces` off (396), no company: one an older
    /// account still has is neither read nor listed, so its agents open nowhere.
    nonisolated var shown: AgentSpacesDirectory {
        guard !SpiralFeatures.companySpaces else { return self }
        return AgentSpacesDirectory(spaces: spaces.filter { $0.kind != .company }, provisioningStatus: provisioningStatus)
    }
}

/// Whose an agent is. Only a complete read says it isn't the person's: a space that failed may hold it.
nonisolated enum AgentOwnership: Equatable {
    case own(AgentSpaceAgentCard)
    case someoneElses
    /// `isReading`: an answer is on its way, the first or a retry's. Otherwise what was read can't say: a read failed,
    /// which the store retries, or an assistant is being set up, which a sync change ends.
    case unknown(isReading: Bool)
}

/// One agent as its screen reads it.
nonisolated struct AgentsAgentDetail: Equatable {
    let readModel: AgentReadModel
    let rooms: [AgentRoomEntry]
    /// `nil` until a read of them succeeded: a failed one keeps the last.
    let pendingVerifications: [VerificationSummary]?
}

/// A value of the store, by the kind of what was read.
nonisolated enum AgentsValue: Equatable {
    case spaces(AgentsSpaces)
    case agent(AgentsAgentDetail)
    case activity(AgentActivityPage)
    case usage(AgentUsage)
    case blocks(AgentBlockedContactsPage)
    case outreach([OutreachQueueEntry])
    case needsAction(NotificationsSnapshot)
    case hubActivity(AgentActivityPage)
    case publicProfile(UserProfileView)
    case roomTools(RoomToolsView)
    case toolsCatalog(ToolsCatalogView)
    case aiConsent(AIConsent)
    case editSchema(AgentEditSchema)

    var spaces: AgentsSpaces? {
        if case .spaces(let value) = self { value } else { nil }
    }

    var agent: AgentsAgentDetail? {
        if case .agent(let value) = self { value } else { nil }
    }

    var activity: AgentActivityPage? {
        if case .activity(let value) = self { value } else { nil }
    }

    var usage: AgentUsage? {
        if case .usage(let value) = self { value } else { nil }
    }

    var blocks: AgentBlockedContactsPage? {
        if case .blocks(let value) = self { value } else { nil }
    }

    var outreach: [OutreachQueueEntry]? {
        if case .outreach(let value) = self { value } else { nil }
    }

    var needsAction: NotificationsSnapshot? {
        if case .needsAction(let value) = self { value } else { nil }
    }

    var hubActivity: AgentActivityPage? {
        if case .hubActivity(let value) = self { value } else { nil }
    }

    var publicProfile: UserProfileView? {
        if case .publicProfile(let value) = self { value } else { nil }
    }

    var roomTools: RoomToolsView? {
        if case .roomTools(let value) = self { value } else { nil }
    }

    var toolsCatalog: ToolsCatalogView? {
        if case .toolsCatalog(let value) = self { value } else { nil }
    }

    var aiConsent: AIConsent? {
        if case .aiConsent(let value) = self { value } else { nil }
    }

    var editSchema: AgentEditSchema? {
        if case .editSchema(let value) = self { value } else { nil }
    }
}

/// Where a resource stands for a screen.
nonisolated enum AgentsReadState<Value> {
    /// Nothing to show yet; a read is on its way or about to start.
    case loading
    case loaded(Value)
    /// Nothing to show: the last read failed. Never "nothing there".
    case failed(AgentPlatformError)
}

@Observable
final class AgentsStore {
    /// A paged list read again reads what it held, up to the server's cap.
    static let rereadLimit = 100

    @ObservationIgnored let service: AgentPlatformServiceProtocol
    /// The waits before reading again a shown resource whose read failed; after
    /// the last one it is read on the next `ready` or return to the foreground.
    @ObservationIgnored private let retryDelays: [Duration]

    private(set) var values: [AgentsResource: AgentsValue] = [:]
    /// Why the last read of a resource failed; cleared by a read that succeeds.
    private(set) var failures: [AgentsResource: AgentPlatformError] = [:]
    /// Set by `PlatformSync`.
    var connectionState: PlatformSyncConnectionState = .idle
    /// Re-reads started by `ready.fresh` or `limited` that have not finished.
    private(set) var catchUpCount = 0

    @ObservationIgnored private var holders: [AgentsResource: Set<ObjectIdentifier>] = [:]
    @ObservationIgnored private var stale: Set<AgentsResource> = []
    @ObservationIgnored private var readsInFlight: Set<AgentsResource> = []
    @ObservationIgnored private var readsAgain: Set<AgentsResource> = []
    /// The reads running now, for tests to wait on.
    @ObservationIgnored private(set) var readTasks: [UUID: Task<Void, Never>] = [:]
    /// The read of each resource on its way.
    @ObservationIgnored private var currentReads: [AgentsResource: Task<Void, Never>] = [:]
    /// Failed reads in a row of a shown resource, and the wait before the next one.
    @ObservationIgnored private var failedReads: [AgentsResource: Int] = [:]
    @ObservationIgnored private var retries: [AgentsResource: Task<Void, Never>] = [:]
    /// Reads that answered with part of what was asked and kept the last of the rest.
    @ObservationIgnored private var partlyFailedReads: Set<AgentsResource> = []
    /// Moves whenever what waits may have changed (a read of it starts, or a change marks it):
    /// a hub answer to a request made before that is older and does not write what waits.
    @ObservationIgnored private var needsActionGeneration = 0
    /// Moves with every write of the consent that answered: a read that left before it is older and does not write.
    @ObservationIgnored private var aiConsentGeneration = 0
    /// Moves with each of the person's own edits written into a resource (S5): a read that left before it is older and
    /// does not write; the read after it, already asked for, does.
    @ObservationIgnored private var ownWrites: [AgentsResource: Int] = [:]

    init(service: AgentPlatformServiceProtocol, retryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15)]) {
        self.service = service
        self.retryDelays = retryDelays
    }

    isolated deinit {
        retries.values.forEach { $0.cancel() }
    }

    /// The line at the top of the Agents tab's screens (the feed's capsule).
    var syncStatus: PlatformSyncStatus? {
        connectionState.status(isCatchingUp: catchUpCount > 0)
    }

    /// Calls `onChange` after changes to what screens render, coalesced per
    /// turn of the main actor, for as long as it answers `true` (its owner lives).
    func observe(_ onChange: @escaping @MainActor @Sendable () -> Bool) {
        withObservationTracking {
            _ = values
            _ = failures
            _ = connectionState
            _ = catchUpCount
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, onChange() else { return }
                observe(onChange)
            }
        }
    }

    // MARK: - Reads

    func value(_ resource: AgentsResource) -> AgentsValue? {
        values[resource]
    }

    func readState<Value>(_ resource: AgentsResource, _ extract: (AgentsValue) -> Value?) -> AgentsReadState<Value> {
        if let value = values[resource].flatMap(extract) {
            return .loaded(value)
        }
        if let error = failures[resource] {
            return .failed(error)
        }
        return .loading
    }

    var spaces: AgentsSpaces? {
        if case .spaces(let spaces)? = values[.spaces] { spaces } else { nil }
    }

    /// The card as the spaces last read it, so a header follows the list.
    func card(agentID: String) -> AgentSpaceAgentCard? {
        spaces?.card(agentID: agentID)
    }

    /// The owner's card of the agent with this Matrix ID, as the spaces last read it.
    func card(matrixUserID: String) -> AgentSpaceAgentCard? {
        spaces?.cards.values.first { $0.matrixUserID == matrixUserID }
    }

    /// Whose the agent with this Matrix ID is. A card stands for what a read said, also after a later failure;
    /// no card is only an answer when nothing failed.
    func ownership(matrixUserID: String) -> AgentOwnership {
        if let card = card(matrixUserID: matrixUserID) {
            return .own(card)
        }
        let isReading = readsInFlight.contains(.spaces)
        guard let spaces else {
            return .unknown(isReading: isReading || failures[.spaces] == nil)
        }
        return spaces.isComplete && failures[.spaces] == nil ? .someoneElses : .unknown(isReading: isReading)
    }

    /// The person's consent as last read or written; `nil` before either.
    var aiConsent: AIConsent? {
        values[.aiConsent]?.aiConsent
    }

    /// What waits for the owner, as last read; `nil` before a read succeeded (never a made-up `0`).
    var needsAction: [NeedsActionItem]? {
        if case .needsAction(let snapshot)? = values[.needsAction] { snapshot.needsAction } else { nil }
    }

    var visitorMessages: [VisitorMessage]? {
        if case .needsAction(let snapshot)? = values[.needsAction] { snapshot.visitorMessages } else { nil }
    }

    func isStale(_ resource: AgentsResource) -> Bool {
        stale.contains(resource)
    }

    func isShown(_ resource: AgentsResource) -> Bool {
        holders[resource]?.isEmpty == false
    }

    // MARK: - What is shown

    /// `owner` shows `resource`: it is read now when nothing was read, or it went stale meanwhile.
    func show(_ resource: AgentsResource, by owner: AnyObject) {
        holders[resource, default: []].insert(ObjectIdentifier(owner))
        // A read on its way already reads it for this screen too.
        if (values[resource] == nil && !readsInFlight.contains(resource)) || stale.contains(resource) {
            readAnew(resource)
        }
    }

    func stopShowing(_ resource: AgentsResource, by owner: AnyObject) {
        holders[resource]?.remove(ObjectIdentifier(owner))
        if holders[resource]?.isEmpty == true {
            holders[resource] = nil
            // Nobody shows it: no retry; it is read when it shows again.
            retries.removeValue(forKey: resource)?.cancel()
            failedReads[resource] = nil
        }
    }

    /// Reads it now (Retry, or after the person's own write) and returns once
    /// it is read; a read on its way is followed by one more, which this waits for.
    func reread(_ resource: AgentsResource) async {
        readAnew(resource)
        while let task = currentReads[resource] {
            await task.value
            await Task.yield()
        }
    }

    /// A screen came into view, or the person tapped Retry: what it shows is read unless a read is on its way, so
    /// what the person looks at follows a change the stream didn't bring. A read on its way answers for it, which
    /// the screen shows as a new start like any other.
    func refresh(_ resource: AgentsResource) {
        guard !readsInFlight.contains(resource) else {
            forgetFailureOfNothingShown(resource)
            return
        }
        readAnew(resource)
    }

    /// The next page of a paged list, after what is held. `false` when it could not be read.
    @discardableResult
    func loadMore(_ resource: AgentsResource) async -> Bool {
        guard let pageSize = resource.pageSize, let value = values[resource] else { return false }
        switch (resource, value) {
        case (.activity(let agentID, let filter), .activity(let page)):
            guard let cursor = page.nextCursor else { return true }
            switch await service.listAgentActivity(agentID: agentID, filter: filter, cursor: cursor, limit: pageSize) {
            case .success(let next):
                append(next, to: resource) { .activity($0) } extract: { if case .activity(let page) = $0 { page } else { nil } }
                return true
            case .failure(let error):
                MXLog.error("Could not read more of \(resource): \(error)")
                return false
            }
        case (.hubActivity, .hubActivity(let page)):
            guard let cursor = page.nextCursor else { return true }
            switch await service.fetchNotifications(activityCursor: cursor, limit: pageSize) {
            case .success(let snapshot):
                let next = AgentActivityPage(items: snapshot.activity, nextCursor: snapshot.nextActivityCursor)
                append(next, to: resource) { .hubActivity($0) } extract: { if case .hubActivity(let page) = $0 { page } else { nil } }
                return true
            case .failure(let error):
                MXLog.error("Could not read more of \(resource): \(error)")
                return false
            }
        case (.blocks(let agentID), .blocks(let page)):
            guard let cursor = page.nextCursor else { return true }
            switch await service.listBlockedContacts(agentID: agentID, cursor: cursor, limit: pageSize) {
            case .success(let next):
                guard case .blocks(let current)? = values[resource] else { return true }
                // An unblock while the page was out may have removed a row; a person already held is never held twice.
                let held = Set(current.blocks.map(\.contactMXID))
                values[resource] = .blocks(AgentBlockedContactsPage(blocks: current.blocks + next.blocks.filter { !held.contains($0.contactMXID) },
                                                                    nextCursor: next.nextCursor))
                return true
            case .failure(let error):
                MXLog.error("Could not read more of \(resource): \(error)")
                return false
            }
        default:
            return false
        }
    }

    /// The person unblocked someone: the row goes at once, before the stream says so.
    func removeBlock(of contactMXID: String, agentID: String) {
        let resource = AgentsResource.blocks(agentID: agentID)
        guard case .blocks(let page)? = values[resource] else { return }
        values[resource] = .blocks(AgentBlockedContactsPage(blocks: page.blocks.filter { $0.contactMXID != contactMXID }, nextCursor: page.nextCursor))
    }

    /// Opening the hub is the "seen" gesture (decision 8); nothing shown counts unseen, so nothing changes here.
    func markNotificationsSeen() async {
        switch await service.markNotificationsSeen() {
        case .success:
            MXLog.info("The notifications' last-seen marker moved")
        case .failure(let error):
            MXLog.error("Could not move the notifications' last-seen marker: \(error)")
        }
    }

    // MARK: - Writes

    /// The person's own edit of an agent (S5): the server's answer shows at once on every screen holding the agent,
    /// the Agents tab's row included, before the stream says so. Its rooms and verifications stay as read; the
    /// agent and the spaces are read again, so what the answer doesn't carry follows.
    func agentEdited(_ readModel: AgentReadModel) {
        let agentResource = AgentsResource.agent(agentID: readModel.agentID)
        if case .agent(let detail)? = values[agentResource] {
            set(.agent(AgentsAgentDetail(readModel: readModel, rooms: detail.rooms, pendingVerifications: detail.pendingVerifications)),
                for: agentResource)
        }
        if case .spaces(let spaces)? = values[.spaces], spaces.card(agentID: readModel.agentID) != nil {
            let details = spaces.details.mapValues { detail in
                AgentSpaceDetail(orgID: detail.orgID, name: detail.name, kind: detail.kind, avatarMXC: detail.avatarMXC,
                                 industry: detail.industry, website: detail.website,
                                 agents: detail.agents.map { $0.agentID == readModel.agentID ? $0.edited(readModel) : $0 })
            }
            set(.spaces(AgentsSpaces(directory: spaces.directory, details: details, failedSpaceIDs: spaces.failedSpaceIDs)), for: .spaces)
        }
        // A read on its way left before the edit: it doesn't put the older copy back.
        ownWrites[agentResource, default: 0] += 1
        ownWrites[.spaces, default: 0] += 1
        markStale(agentResource)
        markStale(.spaces)
    }

    /// Records the person's decision, and every reader follows what the server answers. A write
    /// that failed may still have landed, so what is held is read again.
    func setAIConsent(granted: Bool) async -> Result<AIConsent, AgentPlatformError> {
        let result = await service.setAIConsent(granted: granted)
        switch result {
        case .success(let consent):
            aiConsentGeneration += 1
            set(.aiConsent(consent), for: .aiConsent)
            stale.remove(.aiConsent)
        case .failure:
            markStale(.aiConsent)
        }
        return result
    }

    // MARK: - The sync stream

    /// A resumed `ready` or the return to the foreground: what is shown and
    /// stale (a read that failed, retries spent or not) is read again now.
    func rereadStaleShown() {
        for resource in stale.intersection(holders.keys) {
            retries.removeValue(forKey: resource)?.cancel()
            failedReads[resource] = nil
            read(resource)
        }
    }

    /// `ready.fresh` or `limited`: anything may have changed. What is shown is read again now; the rest when it shows.
    func markEverythingStale() {
        stale.formUnion(values.keys)
        stale.formUnion(holders.keys)
        needsActionGeneration += 1
        for resource in holders.keys {
            read(resource, isCatchUp: true)
        }
    }

    func apply(_ changes: [AgentsSyncChange]) {
        for change in changes {
            apply(change)
        }
    }

    private func apply(_ change: AgentsSyncChange) {
        switch change {
        case .agentUpdated(let agentID, _), .agentConfig(let agentID):
            markStale(.spaces)
            markStale(.agent(agentID: agentID))
        case .spaceUpdated:
            markStale(.spaces)
        case .agentRooms(let agentID, let roomID):
            // A card counts the agent's rooms and tools.
            markStale(.spaces)
            markStale(.agent(agentID: agentID))
            markStale(.roomTools(roomID: roomID))
            markStale(.toolsCatalog(agentID: agentID, roomID: roomID))
        case .agentTools(let agentID, let roomID):
            markStale(.spaces)
            markStale(.agent(agentID: agentID))
            markStale(.roomTools(roomID: roomID))
        case .agentActivity(let agentID):
            markStale { resource in
                if case .activity(let id, _) = resource { agentID == nil || id == agentID } else { resource == .hubActivity }
            }
        case .agentUsage(let agentID):
            markStale { resource in
                if case .usage(let id) = resource { agentID == nil || id == agentID } else { false }
            }
        case .agentBlocks(let agentID):
            markStale(.blocks(agentID: agentID))
        case .agentOutreach(let agentID):
            markStale { resource in
                if case .outreach(let id, _) = resource { id == agentID } else { false }
            }
        case .approvalChanged, .notificationVisitor, .notificationSeen:
            markStale(.needsAction)
        case .verificationChanged(_, let agentID):
            markStale(.needsAction)
            markStale { resource in
                if case .agent(let id) = resource { agentID == nil || id == agentID } else { false }
            }
        case .profilePublic:
            // The change names the agent, the screen a person: every open profile reads again.
            markStale { resource in
                if case .publicProfile = resource { true } else { false }
            }
        }
    }

    private func markStale(_ resource: AgentsResource) {
        markStale { $0 == resource }
    }

    /// A resource nobody read nor shows is not stale: it is read when it shows.
    private func markStale(where matches: (AgentsResource) -> Bool) {
        let known = Set(values.keys).union(holders.keys)
        for resource in known where matches(resource) {
            stale.insert(resource)
            if resource == .needsAction {
                needsActionGeneration += 1
            }
            if isShown(resource) {
                read(resource)
            }
        }
    }

    // MARK: - Reading

    /// A screen asks: with nothing shown it says it is loading again, not that it failed. The store's own
    /// reads leave a failure up until an answer replaces it, so a failed page doesn't flicker at each retry.
    private func readAnew(_ resource: AgentsResource) {
        forgetFailureOfNothingShown(resource)
        read(resource)
    }

    private func forgetFailureOfNothingShown(_ resource: AgentsResource) {
        if values[resource] == nil, failures[resource] != nil {
            failures[resource] = nil
        }
    }

    private func read(_ resource: AgentsResource, isCatchUp: Bool = false) {
        guard !readsInFlight.contains(resource) else {
            readsAgain.insert(resource)
            return
        }
        stale.remove(resource)
        readsInFlight.insert(resource)
        if resource == .needsAction {
            needsActionGeneration += 1
        }
        if isCatchUp {
            catchUpCount += 1
        }
        let ownWritesBefore = ownWrites[resource, default: 0]
        currentReads[resource] = track { [weak self] in
            guard let self else { return }
            let result = await fetch(resource)
            readsInFlight.remove(resource)
            if isCatchUp {
                catchUpCount -= 1
            }
            switch result {
            case .success(let value):
                if ownWrites[resource, default: 0] == ownWritesBefore {
                    set(value, for: resource)
                }
                if partlyFailedReads.remove(resource) != nil {
                    // What was read shows; the rest is read again, as after any failed read.
                    stale.insert(resource)
                    scheduleRetry(resource)
                } else {
                    failedReads[resource] = nil
                    retries.removeValue(forKey: resource)?.cancel()
                }
            case .failure(.notFound) where resource.isAgent:
                // Deleted elsewhere: an answer, not a read to try again. What was shown of it goes.
                MXLog.info("\(resource) is gone")
                failedReads[resource] = nil
                retries.removeValue(forKey: resource)?.cancel()
                values[resource] = nil
                failures[resource] = .notFound
            case .failure(let error):
                // What is shown stays; it is read again soon, on the next `ready` or foreground, or when it next shows.
                MXLog.error("Could not read \(resource): \(error)")
                stale.insert(resource)
                failures[resource] = error
                scheduleRetry(resource)
            }
            currentReads[resource] = nil
            if readsAgain.remove(resource) != nil {
                read(resource)
            }
        }
    }

    private func set(_ value: AgentsValue, for resource: AgentsResource) {
        if failures[resource] != nil {
            failures[resource] = nil
        }
        if values[resource] != value {
            values[resource] = value
        }
    }

    /// A shown resource whose read failed is read again after the next wait, while it is still shown and stale.
    private func scheduleRetry(_ resource: AgentsResource) {
        let attempt = failedReads[resource, default: 0]
        guard isShown(resource), attempt < retryDelays.count, retries[resource] == nil else { return }
        failedReads[resource] = attempt + 1
        let delay = retryDelays[attempt]
        retries[resource] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            retries[resource] = nil
            guard isShown(resource), stale.contains(resource) else { return }
            read(resource)
        }
    }

    private func fetch(_ resource: AgentsResource) async -> Result<AgentsValue, AgentPlatformError> {
        switch resource {
        case .spaces:
            return await fetchSpaces()
        case .agent(let agentID):
            return await fetchAgent(agentID)
        case .activity(let agentID, let filter):
            return await service.listAgentActivity(agentID: agentID, filter: filter, cursor: nil, limit: limit(for: resource)).map(AgentsValue.activity)
        case .usage(let agentID):
            return await service.fetchAgentUsage(agentID: agentID).map(AgentsValue.usage)
        case .blocks(let agentID):
            return await service.listBlockedContacts(agentID: agentID, cursor: nil, limit: limit(for: resource)).map(AgentsValue.blocks)
        case .outreach(let agentID, let status):
            return await service.listOutreachQueue(agentID: agentID, status: status, limit: Self.rereadLimit).map(AgentsValue.outreach)
        case .needsAction:
            // The whole needs-action set and the visitors' entries come with any page.
            return await service.fetchNotifications(activityCursor: nil, limit: 1).map { .needsAction($0.needsActionPart) }
        case .hubActivity:
            let generation = needsActionGeneration
            let result = await service.fetchNotifications(activityCursor: nil, limit: limit(for: resource))
            // The same answer holds the whole needs-action set: one request serves the hub and the
            // badge, unless what waits was read or changed since this request left.
            if case .success(let snapshot) = result, generation == needsActionGeneration {
                set(.needsAction(snapshot.needsActionPart), for: .needsAction)
                if !readsInFlight.contains(.needsAction) {
                    stale.remove(.needsAction)
                    failedReads[.needsAction] = nil
                    retries.removeValue(forKey: .needsAction)?.cancel()
                }
            }
            return result.map { .hubActivity(AgentActivityPage(items: $0.activity, nextCursor: $0.nextActivityCursor)) }
        case .publicProfile(let userID):
            return await service.fetchUserProfile(mxid: userID).map(AgentsValue.publicProfile)
        case .roomTools(let roomID):
            return await service.fetchRoomTools(roomID: roomID).map(AgentsValue.roomTools)
        case .toolsCatalog(let agentID, let roomID):
            return await service.fetchToolsCatalog(agentID: agentID, roomID: roomID).map(AgentsValue.toolsCatalog)
        case .aiConsent:
            let generation = aiConsentGeneration
            let result = await service.fetchAIConsent()
            if generation != aiConsentGeneration, let written = values[.aiConsent] {
                return .success(written)
            }
            return result.map(AgentsValue.aiConsent)
        case .editSchema(let agentID):
            return await service.fetchAgentEditSchema(agentID: agentID).map(AgentsValue.editSchema)
        }
    }

    /// A paged list read again reads as many rows as it holds, so a list scrolled down stays.
    private func limit(for resource: AgentsResource) -> Int {
        let pageSize = resource.pageSize ?? Self.rereadLimit
        let held = switch values[resource] {
        case .activity(let page)?, .hubActivity(let page)?: page.items.count
        case .blocks(let page)?: page.blocks.count
        default: 0
        }
        return min(Self.rereadLimit, max(pageSize, held))
    }

    /// Each space's agents, in the directory's order. Sequential: a person
    /// has a handful of spaces, and the service existential is not Sendable.
    private func fetchSpaces() async -> Result<AgentsValue, AgentPlatformError> {
        let directory: AgentSpacesDirectory
        switch await service.listMyAgentSpaces() {
        case .success(let read): directory = read.shown
        case .failure(let error): return .failure(error)
        }
        var details: [String: AgentSpaceDetail] = [:]
        var failedSpaceIDs: Set<String> = []
        for space in directory.spaces {
            switch await service.fetchAgentSpace(orgID: space.orgID) {
            case .success(let detail):
                details[space.orgID] = detail
            case .failure(let error):
                MXLog.error("Could not read agent space \(space.orgID): \(error)")
                details[space.orgID] = spaces?.details[space.orgID]
                failedSpaceIDs.insert(space.orgID)
                partlyFailedReads.insert(.spaces)
            }
        }
        return .success(.spaces(AgentsSpaces(directory: directory, details: details, failedSpaceIDs: failedSpaceIDs)))
    }

    private func fetchAgent(_ agentID: String) async -> Result<AgentsValue, AgentPlatformError> {
        let readModel = await service.fetchAgentReadModel(agentID: agentID)
        let rooms = await service.fetchAgentRooms(agentID: agentID)
        let verifications = await service.listVerificationsForAgent(agentID: agentID)
        switch (readModel, rooms) {
        case (.success(let readModel), .success(let rooms)):
            let shown: [VerificationSummary]? = if case .agent(let detail)? = values[.agent(agentID: agentID)] { detail.pendingVerifications } else { nil }
            let pending = (try? verifications.get()) ?? shown
            return .success(.agent(AgentsAgentDetail(readModel: readModel, rooms: rooms, pendingVerifications: pending)))
        case (.failure(let error), _), (_, .failure(let error)):
            return .failure(error)
        }
    }

    private func append(_ next: AgentActivityPage,
                        to resource: AgentsResource,
                        wrap: (AgentActivityPage) -> AgentsValue,
                        extract: (AgentsValue) -> AgentActivityPage?) {
        guard let current = values[resource].flatMap(extract) else { return }
        let held = Set(current.items.map(\.id))
        values[resource] = wrap(AgentActivityPage(items: current.items + next.items.filter { !held.contains($0.id) }, nextCursor: next.nextCursor))
    }

    /// Each read is kept until it ends, for tests to wait on.
    @discardableResult
    private func track(_ operation: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task { [weak self] in
            await operation()
            self?.readTasks[id] = nil
        }
        readTasks[id] = task
        return task
    }
}

private extension AgentSpaceAgentCard {
    /// The card as an edit's answer says it is now; its counts stay until the spaces are read again.
    nonisolated func edited(_ readModel: AgentReadModel) -> AgentSpaceAgentCard {
        AgentSpaceAgentCard(agentID: agentID, matrixUserID: matrixUserID, displayName: readModel.displayName, avatarMXC: readModel.avatarMXC,
                            kind: kind, visibility: readModel.visibility, lifecycleState: readModel.lifecycleState,
                            roomCount: roomCount, activeToolCount: activeToolCount, isPaused: readModel.paused)
    }
}

private extension NotificationsSnapshot {
    /// What waits and the visitors' entries only: a 100-row hub answer and a 1-row badge answer
    /// of the same moment are then the same value and re-render nobody.
    nonisolated var needsActionPart: NotificationsSnapshot {
        NotificationsSnapshot(needsAction: needsAction, activity: [], nextActivityCursor: nil, lastSeenAt: lastSeenAt, unseenCount: 0,
                              visitorMessages: visitorMessages)
    }
}
