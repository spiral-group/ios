//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (questions 373, 412): the catalogue's one running post, on the post page.
//
// Each running template is a WebContent process (§ 5.25), so the screen owns
// exactly one, and it moves from page to page as the page is swiped: the post it
// leaves keeps a picture of itself, taken as it leaves and never on a state change
// (§ 5.33). Only one post can run because there is only one preview to run it in.
//

import Combine
import SwiftUI

@MainActor
final class InteractivePostCatalogLiveCard {
    struct Request {
        let templateID: String
        let artifact: SpiralAppArtifact
    }

    /// The side a picture is kept at, in pixels: a card on a 3× phone, and
    /// about a megabyte, so a catalogue's worth stays a small fixed cost.
    private static let stillSide: CGFloat = 480

    /// How many cards one web view serves before the next gets a new one. Kept
    /// for ever, its process grew about 85 MB with every lap of the catalogue
    /// (638, 718, 807 MB); every six cards it stays near 400 MB, and the card
    /// that pays for the new one waits 0.8 s behind its still.
    private static let cardsPerHost = 6

    /// The card holding the preview. It keeps its surface until its picture
    /// is taken: a web view out of its window has nothing to take.
    @Published private(set) var runningTemplateID: String?
    /// What each card that has run last looked like. In memory and gone with
    /// the screen: it can show the people of the room (ADR-0089).
    @Published private(set) var stills: [String: UIImage] = [:]

    let preview: DraftPreview

    private let viewerID: String
    private let loadMembers: () async -> [String: Any]
    private var request: Request?
    private var isSettling = false
    private var handOvers = 0
    /// `preview.failures` when this card was asked for, so its retries are
    /// its own. Not reset by a retry, or a card that never starts never stops.
    private var failuresAtStart = 0
    private var cancellables = Set<AnyCancellable>()

    init(preview: DraftPreview, viewerID: String, loadMembers: @escaping () async -> [String: Any]) {
        self.preview = preview
        self.viewerID = viewerID
        self.loadMembers = loadMembers

        // A start that failed, or a content process the system killed, leaves
        // the card a picture; a card still wanted tries again, a few times.
        preview.$failures
            .dropFirst()
            .sink { [weak self] failures in
                DispatchQueue.main.async { self?.startAgain(after: failures) }
            }
            .store(in: &cancellables)
    }

    /// Run this card, or none. The newest request wins: taps faster than the
    /// hand-over skip the cards in between rather than queueing them.
    func run(_ request: Request?) {
        if request?.templateID != self.request?.templateID {
            failuresAtStart = preview.failures
        }
        self.request = request
        settle()
    }

    /// Take the running card's picture now, for when it is about to lose its
    /// window to a push: moving on from there would have nothing to take.
    func freezeRunningCard() {
        guard let runningTemplateID else { return }
        Task { await freeze(runningTemplateID) }
    }

    // MARK: - Private

    private func settle() {
        guard !isSettling else { return }
        isSettling = true
        Task {
            await handOver()
            isSettling = false
        }
    }

    private func handOver() async {
        while runningTemplateID != request?.templateID {
            if let leaving = runningTemplateID {
                await freeze(leaving)
                handOvers += 1
                await preview.stopAndWait(keepingHost: true)
                runningTemplateID = nil
                // Kept while another card waits: the same web view, shell warm.
                // Asked after the stop, which a dismissal may have come during.
                if request == nil || handOvers.isMultiple(of: Self.cardsPerHost) {
                    preview.dropKeptHost()
                }
            }
            if let next = request {
                MXLog.info("[SpiralApp] catalogue: run \(next.templateID)")
                preview.start(next.artifact, viewerID: viewerID, members: loadMembers)
                runningTemplateID = next.templateID
            }
        }
    }

    private func freeze(_ templateID: String) async {
        // The picture was taken on the way out; WebKit has stopped drawing by now.
        guard UIApplication.shared.applicationState != .background else { return }
        guard let image = await preview.takeSnapshot() else { return }
        stills[templateID] = image.preparingThumbnail(of: CGSize(width: Self.stillSide, height: Self.stillSide)) ?? image
    }

    private func startAgain(after failures: Int) {
        guard runningTemplateID != nil, preview.instance == nil else { return }
        runningTemplateID = nil
        guard failures - failuresAtStart > DraftPreview.retries else {
            settle()
            return
        }
        MXLog.error("[SpiralApp] catalogue: a card would not start")
        request = nil
    }
}
