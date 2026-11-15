//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359 item 16): the app the timeline benchmark launches. The real room screen and its
// real table, on the real background, fed by a mock timeline, so nothing but the screen's own work is measured.
// Compiled only with SPIRAL_TIMELINE_BENCH, which Tools/Scripts/run-timeline-bench.sh passes and no project file sets.
//

#if SPIRAL_TIMELINE_BENCH

import Combine
import Kingfisher
import SwiftUI

final class TimelineBenchAppCoordinator: AppCoordinatorProtocol, SecureWindowManagerDelegate {
    let windowManager: SecureWindowManagerProtocol
    
    private let navigationRootCoordinator = NavigationRootCoordinator()
    private let stack = NavigationStackCoordinator()
    private let analytics = AnalyticsServiceMock(.init())
    private let userIndicatorController = UserIndicatorController()
    private var runner: TimelineBenchRunner?
    
    init(appDelegate: AppDelegate) {
        windowManager = WindowManager(appDelegate: appDelegate)
        MXLog.configure(currentTarget: "timeline-bench")
        windowManager.delegate = self
    }
    
    func start() {
        stack.setRootCoordinator(BlankFormCoordinator(), animated: false)
        navigationRootCoordinator.setRootCoordinator(stack)
        
        let runner = TimelineBenchRunner(stack: stack, analytics: analytics)
        self.runner = runner
        Task { await runner.run() }
    }
    
    func toPresentable() -> AnyView {
        AnyView(navigationRootCoordinator.toPresentable()
            .environment(\.analyticsService, analytics)
            .overlay(alignment: .top) {
                // Question 383: `TIMELINE_BENCH_CALL_BAR=1` measures the scroll with a call's bar talking over it.
                if let callBar {
                    NativeCallBar(context: callBar.context)
                        .environment(\.nativeCallVoiceLevels, TimelineBenchVoice())
                }
            })
    }

    private lazy var callBar: NativeCallScreenViewModel? = ProcessInfo.processInfo.environment["TIMELINE_BENCH_CALL_BAR"] == "1"
        ? NativeCallScreen_Previews.makeNoAgentViewModel()
        : nil
    
    func windowManagerDidConfigureWindows(_ windowManager: SecureWindowManagerProtocol) {
        userIndicatorController.window = windowManager.overlayWindow
    }
    
    func handlePotentialPhishingAttempt(url: URL, openURLAction: @escaping (URL) -> Void) -> Bool {
        fatalError("Not implemented.")
    }
    
    func handleDeepLink(_ url: URL, isExternalURL: Bool, windowType: SecondaryWindowType?) -> Bool {
        fatalError("Not implemented.")
    }
    
    func handleAppRoute(_ appRoute: AppRoute, windowType: SecondaryWindowType?) {
        fatalError("Not implemented.")
    }
    
    func handleUserActivity(_ activity: NSUserActivity) {
        fatalError("Not implemented.")
    }
}

/// Serves the fixture's pictures from memory, as the SDK's media store would from disk, a moment after they're asked for.
nonisolated struct TimelineBenchMediaLoader: MediaLoaderProtocol {
    let thumbnail: Data
    let avatar: Data
    let artifact: Data
    
    func loadMediaContentForSource(_ source: MediaSourceProxy) async throws -> Data {
        if source.url.absoluteString.contains("post-artifact") {
            return artifact
        }
        return try await loadMediaThumbnailForSource(source, width: 0, height: 0)
    }
    
    func loadMediaThumbnailForSource(_ source: MediaSourceProxy, width: UInt, height: UInt) async throws -> Data {
        try await Task.sleep(for: .milliseconds(15))
        return source.url.absoluteString.contains("avatar") ? avatar : thumbnail
    }
    
    func loadMediaFileForSource(_ source: MediaSourceProxy, filename: String?) async throws -> MediaFileHandleProxy {
        throw MediaLoaderError.notSupported
    }
}

/// What every room of a run shares, as a session does: the real media provider, and with it the image cache.
@MainActor
final class TimelineBenchSession {
    let userSession: UserSessionMock
    let fixture: TimelineBenchFixture
    let mediaPlayerProvider = MediaPlayerProvider()
    private let reachability = CurrentValueSubject<HomeserverReachability, Never>(.reachable)
    
    init() {
        let artifact = TimelineBenchPostArtifact.make()
        fixture = TimelineBenchFixture(postDigest: artifact.digest)
        
        let loader = TimelineBenchMediaLoader(thumbnail: Self.jpeg(named: "preview_image", width: 800),
                                              avatar: Self.jpeg(named: "preview_avatar_user", width: 160),
                                              artifact: artifact.data)
        let clientProxy = ClientProxyMock(.init(userID: RoomMemberProxyMock.mockMe.userID))
        clientProxy.mediaLoader = loader
        
        let userSettings = UserSettings.mock()
        userSettings.app.threadsEnabled = true
        userSession = UserSessionMock(.init(clientProxy: clientProxy, userSettings: userSettings))
        userSession.mediaProvider = MediaProvider(mediaLoader: loader,
                                                  imageCache: .onlyInMemory,
                                                  homeserverReachabilityPublisher: reachability.asCurrentValuePublisher())
    }
    
    /// A bundled picture at the size a timeline thumbnail is, encoded once before anything is measured.
    private static func jpeg(named name: String, width: CGFloat) -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            fatalError("Missing \(name).jpg")
        }
        
        let size = CGSize(width: width, height: width * image.size.height / image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else {
            fatalError("Couldn't encode \(name).jpg")
        }
        return jpeg
    }
}

/// A real post: a container with a digest the store accepts, which the room runs in a real web view.
enum TimelineBenchPostArtifact {
    static func make() -> (data: Data, digest: String) {
        let manifest = #"{"app_id":"bench-card","runtime":"1","entry":"app.jsx","aspect":"16:9","state_channel":"matrix","capabilities":[]}"#
        let source = """
        import { Scene, Text, Stack, Meta } from "@spiral/ui";
        
        export default function App() {
          return (
            <Scene theme="sky">
              <Stack>
                <Text variant="title">Where do we eat?</Text>
                <Meta>Three places left</Meta>
              </Stack>
            </Scene>
          );
        }
        """
        let data = SpiralAppContainer.pack(manifestJSON: manifest, entry: "app.jsx", source: source)
        return (data, SpiralAppArtifact.digest(of: data))
    }
}

/// One open room: the screen's real coordinator over a mock timeline.
@MainActor
final class TimelineBenchRoom {
    private let controller: TimelineControllerMock
    private let parameters: RoomScreenCoordinatorParameters
    private(set) var items: [RoomTimelineItemProtocol]
    /// What the server still holds, oldest first, for the table to ask for.
    private var olderItems: [RoomTimelineItemProtocol]
    private(set) var pagesLoaded = 0
    
    var hasOlderItems: Bool {
        !olderItems.isEmpty
    }
    
    init(items: [RoomTimelineItemProtocol], olderItems: [RoomTimelineItemProtocol], hasUnread: Bool, session: TimelineBenchSession, analytics: AnalyticsServiceProtocol) {
        self.items = items
        self.olderItems = olderItems
        
        let members: [RoomMemberProxyMock] = [.mockMe] + TimelineBenchFixture.people.map {
            RoomMemberProxyMock(with: .init(userID: $0.id, displayName: $0.displayName, avatarURL: $0.avatarURL, membership: .join))
        }
        let roomProxy = JoinedRoomProxyMock(.init(id: "!weekend-trip:spiral.md",
                                                  name: "Weekend trip",
                                                  avatarURL: URL(string: "mxc://spiral.md/avatar-room"),
                                                  hasOngoingCall: false,
                                                  unreadMessagesCount: hasUnread ? 27 : 0,
                                                  members: members))
        // A post reads its state from these. It has none, and live updates aren't what's being measured.
        // Instant and whole unless a run asks: `TIMELINE_BENCH_READ_MS` stands for the network, and `TIMELINE_BENCH_HOLE` for
        // an action that never decrypted, which is what the read used to spend seconds on.
        let environment = ProcessInfo.processInfo.environment
        let readDelay = Int(environment["TIMELINE_BENCH_READ_MS"] ?? "") ?? 0
        let hasHole = environment["TIMELINE_BENCH_HOLE"] != nil
        roomProxy.loadSpiralAppRelationsForClosure = { eventID in
            try? await Task.sleep(for: .milliseconds(readDelay))
            guard hasHole else { return .success([]) }
            return .success([1, 3].map { seq in
                #"{"type":"com.spiral.app.action","event_id":"$a\#(seq)\#(eventID)","sender":"@a:spiral.md","origin_server_ts":\#(seq),"content":{"m.relates_to":{"rel_type":"m.reference","event_id":"\#(eventID)"},"op":{"set":{"path":"n","value":\#(seq)}},"seq":\#(seq)}}"#
            })
        }
        roomProxy.subscribeToSpiralEventsTypesListenerReturnValue = .failure(.eventNotFound)
        
        controller = TimelineControllerMock(.init(roomProxy: roomProxy,
                                                  timelineItems: items,
                                                  paginationState: TimelinePaginationState(backward: olderItems.isEmpty ? .endReached : .idle, forward: .endReached)))
        
        let userSession = session.userSession
        parameters = RoomScreenCoordinatorParameters(userSession: userSession,
                                                     roomProxy: roomProxy,
                                                     timelineController: controller,
                                                     mediaPlayerProvider: session.mediaPlayerProvider,
                                                     emojiProvider: EmojiProvider(userSettings: userSession.userSettings),
                                                     linkMetadataProvider: LinkMetadataProvider(),
                                                     completionSuggestionService: CompletionSuggestionServiceMock(configuration: .init()),
                                                     ongoingCallRoomIDPublisher: .init(.init(nil)),
                                                     appMediator: AppMediatorMock(.init()),
                                                     analytics: analytics,
                                                     composerDraftService: ComposerDraftServiceMock(.init()),
                                                     timelineControllerFactory: TimelineControllerFactoryMock(.init()),
                                                     userIndicatorController: UserIndicatorControllerMock())
    }
    
    /// The screen itself, which opening the room makes. Everything above stands for what a session already holds.
    func makeCoordinator() -> RoomScreenCoordinator {
        controller.paginateBackwardsRequestSizeClosure = { [weak self] requestSize in
            await self?.loadOlderItems(count: Int(requestSize))
            return .success(())
        }
        return RoomScreenCoordinator(parameters: parameters)
    }
    
    /// A page from the server, a moment after it's asked for.
    private func loadOlderItems(count: Int) async {
        controller.callbacks.send(.paginationState(.init(backward: .paginating, forward: .endReached)))
        try? await Task.sleep(for: .milliseconds(50))
        
        let page = olderItems.suffix(count)
        olderItems.removeLast(page.count)
        pagesLoaded += 1
        update(page + items)
        controller.callbacks.send(.paginationState(.init(backward: olderItems.isEmpty ? .endReached : .idle, forward: .endReached)))
    }
    
    /// Hands the screen a new timeline, as `TimelineController` does after every change. The view model takes it through
    /// the main queue, so it runs after whatever is already queued.
    func update(_ items: [RoomTimelineItemProtocol]) {
        self.items = items
        controller.timelineItems = items
        controller.readProgress = .init(timelineItems: items, ownUserID: RoomMemberProxyMock.mockMe.userID)
        controller.callbacks.send(.updatedTimelineItems(timelineItems: items, isSwitchingTimelines: false))
    }
}

/// A voice as the SFU reports it: a level every 400 ms, phrases of a few seconds at ordinary talk (-34…-20 dBov)
/// with short pauses. Deterministic, so runs compare.
final class TimelineBenchVoice: NativeCallVoiceLevelReading {
    private static let pattern: [Double] = [0.03, 0.06, 0.1, 0.05, 0.08, 0.04, 0.09, 0.07, 0, 0, 0.05, 0.1, 0.06, 0.04, 0, 0.08]

    func voiceLevel(forUserID userID: String) -> Double {
        loudestVoiceLevel
    }

    var loudestVoiceLevel: Double {
        let step = Int(CACurrentMediaTime() / 0.4)
        return Self.pattern[step % Self.pattern.count]
    }
}

#endif
