//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 step 5.1): the shared-state harness.
//
// The spike proved an app can run without reaching anything it should not.
// This proves the other half: that two phones looking at the same post
// compute the same state. It posts a real `com.spiral.app` event into a real
// room, mounts a throwaway counter against it, and routes the counter's reads
// and writes through `SpiralAppPostSession`.
//
// Deliberately NOT in the timeline. Where the web view lives is a separate
// question (step 7); this one is only about whether the data path works, and
// answering both at once would leave neither answered cleanly.
//
// Deleted with the rest of the harness once the walkthrough is signed off.
//

#if DEBUG

import Combine
import Compound
import CryptoKit
import MatrixRustSDK
import SpiralAppShell
import SwiftUI

struct SpiralAppSliceScreen: View {
    let clientProxy: ClientProxyProtocol?

    @AppStorage("spiralSliceRoomID") private var roomID = ""
    @AppStorage("spiralSliceArtifact") private var artifact = SliceArtifact.counter.rawValue
    @State private var model: SliceModel?
    @State private var status = "Paste a room ID, then Connect."

    var body: some View {
        Form {
            connectionSection

            if let model {
                postsSection(model)

                // Gated on the HOST, not the session: the row captures the
                // container view once, in `makeUIView`, so publishing the
                // section before the host exists leaves an empty row that
                // nothing can later fill.
                if model.instance != nil {
                    liveSection(model)
                }
            }
        }
        .compoundList()
        .navigationTitle("Shared state slice")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model = nil }
    }

    // MARK: - Sections

    private var connectionSection: some View {
        Section {
            TextField("!room:server", text: $roomID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.compound.bodyMDSemibold)

            Picker("App", selection: $artifact) {
                ForEach(SliceArtifact.allCases, id: \.rawValue) { choice in
                    Text(choice.title).tag(choice.rawValue)
                }
            }

            Button("Connect") {
                Task { await connect() }
            }
            .disabled(roomID.isEmpty || clientProxy == nil)

            Text(status)
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
        } header: {
            Text("Room").compoundListSectionHeader()
        } footer: {
            Text("Use the same room on both phones. The room must be one this account has joined.")
                .compoundListSectionFooter()
        }
    }

    private func postsSection(_ model: SliceModel) -> some View {
        Section {
            Button("Post \(model.artifact.title)") {
                Task { await model.createPost() }
            }

            // The owner publishes, so an artifact has to run before it is a
            // post. This is that path with nothing behind it.
            Button(model.isPreviewing ? "Stop the preview" : "Preview without posting") {
                Task { await model.togglePreview() }
            }

            if model.posts.isEmpty {
                Text("No posts yet. One appears here as soon as either phone creates it.")
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
            }

            ForEach(model.posts, id: \.self) { eventID in
                Button {
                    Task { await model.open(eventID) }
                } label: {
                    HStack {
                        Text(eventID)
                            .font(.compound.bodySM)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if model.openedPostID == eventID {
                            Text("open").font(.compound.bodyXS).foregroundStyle(.compound.textSecondary)
                        }
                    }
                }
            }
        } header: {
            Text("Posts").compoundListSectionHeader()
        } footer: {
            Text("The list is live: a post created on the other phone arrives through the event-cache subscription, not by polling.")
                .compoundListSectionFooter()
        }
    }

    private func liveSection(_ model: SliceModel) -> some View {
        Section {
            SpiralAppSliceRow(model: model)
                .frame(height: 200)
                .listRowInsets(EdgeInsets())
                // Opening a different post builds a different host, and a
                // representable is reused unless its identity changes.
                .id(model.openedPostID ?? (model.isPreviewing ? "preview" : nil))

            LabeledContent("Readiness", value: model.readiness)
            LabeledContent("seq", value: "\(model.seq)")
            LabeledContent("State", value: model.stateDescription)
        } header: {
            Text("Live").compoundListSectionHeader()
        } footer: {
            Text("Tap on one phone; the number must change on both. Readiness must read ready — partial means actions could not be read and names which.")
                .compoundListSectionFooter()
        }
    }

    // MARK: - Actions

    private func connect() async {
        guard let clientProxy else { return }

        status = "Resolving…"
        guard case .joined(let roomProxy)? = await clientProxy.roomForIdentifier(roomID) else {
            status = "Not a joined room: \(roomID)"
            model = nil
            return
        }

        let model = SliceModel(roomProxy: roomProxy,
                               clientProxy: clientProxy,
                               artifact: SliceArtifact(rawValue: artifact) ?? .counter)
        self.model = model
        await model.start()

        // Stated rather than assumed. The claim this harness exists to support
        // is that actions arrive DECRYPTED from Swift, and that claim is empty
        // if the room turns out to be unencrypted.
        let encrypted = roomProxy.infoPublisher.value.isEncrypted
        status = "Connected to \(roomProxy.id) — \(encrypted ? "ENCRYPTED" : "not encrypted")."
    }
}

// MARK: - Model

/// Which first-party artifact the harness mounts.
///
/// The counter is the throwaway that proved the data path; the conformance
/// harness is app 0 and outlives it. Both are DEBUG-only — one is scaffolding
/// and the other writes to whatever post it is pointed at.
enum SliceArtifact: String, CaseIterable {
    case counter
    case conformance
    case motion

    var title: String {
        switch self {
        case .counter: "a counter"
        case .conformance: "the conformance harness"
        case .motion: "the motion probe"
        }
    }

    var packed: SpiralAppShell.PackedArtifact? {
        switch self {
        case .counter: SpiralAppShell.sliceCounterArtifact
        case .conformance: SpiralAppShell.conformanceArtifact
        case .motion: SpiralAppShell.motionArtifact
        }
    }

    /// `app_id` for the post event, so the two are told apart in a room.
    var appID: String {
        rawValue
    }
}

@MainActor
@Observable
final class SliceModel {
    let artifact: SliceArtifact
    private let roomProxy: JoinedRoomProxyProtocol
    private let clientProxy: ClientProxyProtocol

    /// Posts seen in this room, newest last.
    private(set) var posts: [String] = []
    private(set) var openedPostID: String?
    private(set) var readiness = "—"
    private(set) var seq = 0
    private(set) var stateDescription = "—"

    /// Observed, because the live section's existence depends on it.
    private(set) var instance: SpiralAppInstance?
    /// One app at a time here, so the pool only ever holds the one warm host
    /// that opening the next post reuses.
    private let hostPool = SpiralAppHostPool { SpiralAppWebViewHost() }
    private(set) var isPreviewing = false
    @ObservationIgnored private var postSubscription: TaskHandle?
    @ObservationIgnored private var snapshotCancellable: AnyCancellable?

    init(roomProxy: JoinedRoomProxyProtocol, clientProxy: ClientProxyProtocol, artifact: SliceArtifact) {
        self.roomProxy = roomProxy
        self.clientProxy = clientProxy
        self.artifact = artifact
    }

    deinit {
        postSubscription?.cancel()
    }

    /// Watch for posts. Uses the same subscription the state reader uses, so
    /// a post created on the other phone lands here without polling.
    func start() async {
        let listener = SDKListener<[SpiralObservedEvent]>.onMainActor { [weak self] events in
            self?.ingestPosts(events)
        }

        if case .success(let handle) = await roomProxy.subscribeToSpiralEvents(types: ["m.room.message"],
                                                                               listener: listener) {
            postSubscription = handle
        }
    }

    func createPost() async {
        guard let packed = artifact.packed else {
            MXLog.error("[SpiralApp] \(artifact.rawValue) is not in the bundle")
            return
        }

        // The artifact is really uploaded, so the post references bytes that
        // exist. A post with no source is not a degraded post — it is one no
        // client could ever run, and the parser refuses it. Finding that out
        // by building the row is the reason this is here.
        //
        // PLAINTEXT, and only because this is a harness: the agent uploads an
        // `EncryptedFile` (step 6), which is what an encrypted room requires.
        // Wiring encrypted upload into a DEBUG screen would be inventing a
        // second implementation of the thing step 6 exists to build.
        guard let mxc = await upload(packed.bytes) else { return }

        let digest = packed.digest

        // Sent as a MESSAGE, through the same call an image goes through.
        // `body` is not decoration: it is what a client that does not know this
        // type will show, so a post is never an empty row in Element Web.
        let post = InteractivePostContent(body: artifact.title,
                                          appId: artifact.appID,
                                          runtime: "1",
                                          title: artifact.title,
                                          aspect: artifact == .motion ? "3:4" : "4:3",
                                          stateChannel: "room",
                                          sha256: digest,
                                          url: mxc,
                                          fileJson: nil)

        guard let content = try? contentWithoutRelationFromMessage(message: .init(msgType: .interactivePost(content: post),
                                                                                  body: artifact.title,
                                                                                  isEdited: false,
                                                                                  mentions: nil)) else {
            MXLog.error("[SpiralApp] could not build the post's message content")
            return
        }

        _ = await roomProxy.timeline.sendMessageEventContent(content)

        await proveTheRoundTrip(mxc: mxc, digest: digest)
    }

    /// Fetch back what we just uploaded, through the same path a receiving
    /// phone uses.
    ///
    /// The store's unit tests use a mock loader, so they say nothing about
    /// `mxc://` — whether the media repository hands back the same bytes, and
    /// whether the digest still matches after a real round trip. This is the
    /// only place that asks.
    private func proveTheRoundTrip(mxc: String, digest: String) async {
        let store = SpiralAppArtifactStore(mediaLoader: clientProxy.mediaLoader)
        let probe = SpiralAppPost(InteractivePostContent(body: artifact.title,
                                                         appId: artifact.appID,
                                                         runtime: "1",
                                                         title: artifact.title,
                                                         aspect: artifact == .motion ? "3:4" : "4:3",
                                                         stateChannel: "default",
                                                         sha256: digest,
                                                         url: mxc,
                                                         fileJson: nil))

        switch await store.artifact(for: probe) {
        case .success(let fetched):
            MXLog.info("[SpiralApp] round trip OK: \(fetched.manifest.appID), \(fetched.source.count) bytes of source, digest \(fetched.digest)")
        case .failure(let error):
            MXLog.error("[SpiralApp] round trip FAILED: \(error)")
        }
    }

    func open(_ postEventID: String) async {
        await instance?.stop()
        instance = nil

        // The same binding the timeline uses. It was two copies of a five-step
        // recipe until one of them skipped forwarding state into the running
        // app, so it is one type now and this screen cannot drift from the
        // timeline by leaving a step out.
        let instance = SpiralAppInstance(session: SpiralAppPostSession(postEventID: postEventID,
                                                                       roomProxy: roomProxy,
                                                                       feed: SpiralAppActionFeed(roomProxy: roomProxy)),
                                         pool: hostPool)
        self.instance = instance
        openedPostID = postEventID

        // What is left for this screen: show the numbers. Telling the app is
        // the instance's job.
        snapshotCancellable = instance.snapshots.sink { [weak self] snapshot in
            self?.render(snapshot)
        }

        guard let packed = artifact.packed,
              let verified = SpiralAppArtifact.verified(packed: packed.bytes, claimedDigest: packed.digest) else {
            MXLog.error("[SpiralApp] \(artifact.rawValue) bytes do not match their digest")
            return
        }

        guard await instance.start(verified, instanceID: postEventID) == .started else {
            MXLog.error("[SpiralApp] the harness could not mount \(postEventID)")
            return
        }
    }

    /// Run the artifact with no post behind it.
    ///
    /// The claim worth checking on a device is a NEGATIVE one: tapping inside a
    /// preview must produce no `/send/` request at all. A preview that quietly
    /// published would put an author's rehearsal in the room.
    func togglePreview() async {
        if isPreviewing {
            await instance?.stop()
            instance = nil
            isPreviewing = false
            return
        }

        guard let packed = artifact.packed,
              let verified = SpiralAppArtifact.verified(packed: packed.bytes, claimedDigest: packed.digest) else {
            MXLog.error("[SpiralApp] \(artifact.rawValue) is not in the bundle")
            return
        }

        await instance?.stop()

        // The same binding as a post, over a session with nothing behind it.
        // That is the entire difference between rehearsing and publishing, and
        // it is what lets an author trust what they see.
        let instance = SpiralAppInstance(session: SpiralAppPreviewSession(userID: roomProxy.ownUserID,
                                                                          members: ["members": [], "count": 1]),
                                         pool: hostPool)
        self.instance = instance
        openedPostID = nil

        guard await instance.start(verified, instanceID: "preview") == .started else {
            MXLog.error("[SpiralApp] the preview refused to start")
            self.instance = nil
            return
        }

        isPreviewing = true
        MXLog.info("[SpiralApp] previewing \(artifact.rawValue) with nothing behind it")
    }

    /// Put the packed bytes in Matrix media and return their `mxc://`.
    private func upload(_ bytes: Data) async -> String? {
        let file = URL.temporaryDirectory.appending(path: "\(artifact.rawValue).spiralapp")
        guard (try? bytes.write(to: file)) != nil else {
            MXLog.error("[SpiralApp] could not stage the artifact for upload")
            return nil
        }
        defer { try? FileManager.default.removeItem(at: file) }

        let info = FileInfo(mimetype: "application/octet-stream",
                            size: UInt64(bytes.count),
                            thumbnailInfo: nil,
                            thumbnailSource: nil)

        switch await clientProxy.uploadMedia(.file(fileURL: file, fileInfo: info)) {
        case .success(let mxc):
            return mxc
        case .failure(let error):
            MXLog.error("[SpiralApp] could not upload the artifact: \(error)")
            return nil
        }
    }

    private func ingestPosts(_ events: [SpiralObservedEvent]) {
        for event in events where !event.isUtd && SpiralAppPost.isPost(rawEventJSON: event.eventJson) {
            if !posts.contains(event.eventId) {
                posts.append(event.eventId)
            }
        }
    }

    /// Walk the room to its start, then redact every `com.spiral.app` that
    /// names no artifact.
    ///
    /// Reads the TIMELINE, not the event-cache subscription. Measured: back
    /// pagination fills the cache but does not wake the spiral listener, so the
    /// subscription only ever reported the one post that arrived live — while
    /// the timeline held every one of them.
    private func render(_ snapshot: SpiralAppStateReader.Snapshot) {
        seq = snapshot.seq
        readiness = switch snapshot.readiness {
        case .loading: "loading"
        case .ready: "ready"
        case .partial(let missing): "partial, missing \(missing)"
        }
        stateDescription = (snapshot.state.encoded().map { String(decoding: $0, as: UTF8.self) }) ?? "—"
    }
}

// MARK: - Host view

private struct SpiralAppSliceRow: UIViewRepresentable {
    let model: SliceModel

    func makeUIView(context: Context) -> UIView {
        model.instance?.containerView ?? UIView()
    }

    func updateUIView(_ uiView: UIView, context: Context) { }
}

#endif
