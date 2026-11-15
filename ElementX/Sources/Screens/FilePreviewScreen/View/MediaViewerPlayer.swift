//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 413): video and audio in Spiral's own viewer. A video plays on its own once
// its page settles and pauses when the page leaves; a big ▶ stands over it before the first frame and after the
// end. One system player, with its own controls, moves to whichever page is playing.
//

import AVKit
import SwiftUI

/// When a video or audio page plays, pauses and shows its big ▶.
struct MediaViewerPlayback: Equatable {
    enum Phase: Equatable {
        /// Never played since the viewer opened.
        case waiting
        case playing
        case paused
        case ended
    }

    /// What the player should do now.
    enum Command: Equatable {
        case none
        case play
        /// Play from the start, after the end was reached.
        case restart
        case pause
    }

    /// Videos play on their own; audio waits for a tap.
    let autoplays: Bool
    private(set) var phase: Phase = .waiting
    private(set) var isSettledPage = false
    private(set) var hasFile = false

    /// The big ▶ stands over the page before the first frame and after the end.
    var showsPlayButton: Bool {
        phase == .waiting || phase == .ended
    }

    init(autoplays: Bool, hasFile: Bool) {
        self.autoplays = autoplays
        self.hasFile = hasFile
    }

    /// The pager came to rest, on this page or another one.
    mutating func pageSettled(isThisPage: Bool) -> Command {
        isSettledPage = isThisPage
        guard isThisPage else {
            return pause()
        }
        guard hasFile, autoplays, phase != .playing else { return .none }
        return play()
    }

    /// News for the page the pager rests on: it has just come to rest there (`isNewSettle`), or only its file, or
    /// a neighbour's, has arrived. Only a new settle plays a paused or ended video again.
    mutating func settledPageUpdated(isNewSettle: Bool, hasFile: Bool) -> Command {
        var command = isNewSettle ? pageSettled(isThisPage: true) : .none
        if hasFile, !self.hasFile {
            command = fileArrived()
        }
        return command
    }

    /// The file finished downloading.
    mutating func fileArrived() -> Command {
        hasFile = true
        guard isSettledPage, autoplays, phase == .waiting else { return .none }
        return play()
    }

    /// The big ▶ was tapped.
    mutating func playTapped() -> Command {
        guard hasFile else { return .none }
        return play()
    }

    /// The system's controls started playing.
    mutating func didPlay() {
        phase = .playing
    }

    /// The system's controls paused.
    mutating func didPause() {
        if phase == .playing {
            phase = .paused
        }
    }

    mutating func didEnd() {
        phase = .ended
    }

    private mutating func play() -> Command {
        let command: Command = phase == .ended ? .restart : .play
        phase = .playing
        return command
    }

    private mutating func pause() -> Command {
        guard phase == .playing else { return .none }
        phase = .paused
        return .pause
    }
}

/// The one system player of the viewer, moved to the page that plays.
@MainActor
final class MediaViewerPlayer: NSObject {
    enum Event {
        case played, paused, ended
        /// The first frame is on screen, so the poster under it can stop showing.
        case readyForDisplay
    }

    /// The system's player with its controls: play/pause, the scrubber and AirPlay.
    let controller = AVPlayerViewController()
    var onEvent: (MediaPreviewItemID, Event) -> Void = { _, _ in }
    private(set) var mediaID: MediaPreviewItemID?

    private var player: AVPlayer?
    /// The latest play waiting on the audio session.
    private var playRequest: UUID?
    private var observations: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?
    /// Where each video was left, to carry on from there when its page comes back.
    private var positions: [MediaPreviewItemID: CMTime] = [:]
    private let audioSession: MediaViewerAudioSession

    /// The audio session belongs to the viewer: players come and go with their pages, the session stays until it closes.
    init(audioSession: MediaViewerAudioSession) {
        self.audioSession = audioSession
        super.init()
        controller.showsPlaybackControls = true
        // The player goes with its page and with the viewer, so Picture in Picture would only ever break off.
        controller.allowsPictureInPicturePlayback = false
        controller.entersFullScreenWhenPlaybackBegins = false
        // Inside a full-screen presentation the player takes the end of a video for its own full screen ending,
        // and would close the viewer.
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .clear
        controller.view.alpha = 0
        controller.updatesNowPlayingInfoCenter = true
    }

    /// Puts the media's file in the player, keeping the player if it already holds it.
    func load(_ url: URL, for id: MediaPreviewItemID) {
        guard mediaID != id else { return }
        unload()
        mediaID = id

        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        if let position = positions[id] {
            player.seek(to: position)
        }
        self.player = player
        controller.player = player
        controller.view.alpha = 0

        observations = [
            player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                let status = player.timeControlStatus
                Task { @MainActor in self?.timeControlStatusChanged(status, for: id) }
            },
            controller.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.readyForDisplayChanged(for: id) }
            }
        ]
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: player.currentItem,
                                                             queue: .main) { [weak self] _ in
            Task { @MainActor in self?.didPlayToEnd(id) }
        }
    }

    func perform(_ command: MediaViewerPlayback.Command) {
        guard let player else { return }
        switch command {
        case .none:
            break
        case .play, .restart:
            controller.showsPlaybackControls = true
            if command == .restart {
                player.seek(to: .zero)
            }
            // The audio session switches off the main thread, then the video starts, unless it was paused meanwhile.
            let request = UUID()
            playRequest = request
            Task {
                await audioSession.activatePlayback()
                guard playRequest == request, self.player === player else { return }
                player.play()
            }
        case .pause:
            playRequest = nil
            player.pause()
        }
    }

    /// Empties the player, remembering where its video was.
    func unload() {
        if let mediaID, let player {
            player.pause()
            positions[mediaID] = player.currentTime()
        }
        observations = []
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        controller.player = nil
        player = nil
        mediaID = nil
    }

    // MARK: Private

    private func timeControlStatusChanged(_ status: AVPlayer.TimeControlStatus, for id: MediaPreviewItemID) {
        guard id == mediaID else { return }
        switch status {
        case .playing:
            Task { await audioSession.activatePlayback() } // Played from the system's controls.
            onEvent(id, .played)
        case .paused:
            onEvent(id, .paused)
        default:
            break
        }
    }

    private func readyForDisplayChanged(for id: MediaPreviewItemID) {
        guard id == mediaID, controller.isReadyForDisplay else { return }
        controller.view.alpha = 1
        onEvent(id, .readyForDisplay)
    }

    private func didPlayToEnd(_ id: MediaPreviewItemID) {
        guard id == mediaID else { return }
        // The big ▶ takes over from the system's controls until it's tapped.
        controller.showsPlaybackControls = false
        positions[id] = nil
        onEvent(id, .ended)
    }
}

/// Plays a video's sound through the silent switch while the viewer is open, then hands the audio back.
@MainActor
final class MediaViewerAudioSession {
    private nonisolated struct Setting {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
    }

    private var previous: Setting?

    func activatePlayback() async {
        let session = AVAudioSession.sharedInstance()
        // A call owns the audio; leave it alone.
        guard previous == nil, !Self.callOwnsTheAudio(isHeldByCall: NativeCallAudioSession.isHeldByCall, category: session.category) else { return }
        previous = Setting(category: session.category, mode: session.mode, options: session.categoryOptions)
        await Task.detached(priority: .userInitiated) {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                MXLog.error("Failed setting the audio session for a video: \(error)")
            }
        }.value
    }

    func restore() {
        guard let previous else { return }
        self.previous = nil
        Task.detached(priority: .utility) {
            do {
                let session = AVAudioSession.sharedInstance()
                // AGENT-PLATFORM (1.0.2, Fable review of ee42fd8a4): a call coming up closes the viewer, as CallKit
                // activates the session for it. Deactivating it then, or putting the pre-video category back, left
                // the call without sound or a microphone: a call that has taken the audio keeps it. Asked here, as
                // late as possible, since the call claims the audio around the time the viewer closes.
                guard !Self.callOwnsTheAudio(isHeldByCall: NativeCallAudioSession.isHeldByCall, category: session.category) else {
                    MXLog.info("Leaving the audio session to the call after a video")
                    return
                }
                try session.setActive(false, options: .notifyOthersOnDeactivation)
                try session.setCategory(previous.category, mode: previous.mode, options: previous.options)
            } catch {
                MXLog.error("Failed restoring the audio session after a video: \(error)")
            }
        }
    }

    /// Whether a call has the shared session: it claimed it, or it is already configured for one.
    nonisolated static func callOwnsTheAudio(isHeldByCall: Bool, category: AVAudioSession.Category) -> Bool {
        isHeldByCall || category == .playAndRecord
    }
}
