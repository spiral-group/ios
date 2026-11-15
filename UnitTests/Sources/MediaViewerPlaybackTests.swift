//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import AVFoundation
@testable import Spiral
import Testing

struct MediaViewerPlaybackTests {
    @Test
    func videoPlaysOnceItsPageSettles() {
        var playback = MediaViewerPlayback(autoplays: true, hasFile: true)
        #expect(playback.showsPlayButton, "The big play button stands over the video before its first frame.")
        
        #expect(playback.pageSettled(isThisPage: true) == .play)
        #expect(playback.phase == .playing)
        #expect(!playback.showsPlayButton)
        
        // Settling on it again while it plays changes nothing.
        #expect(playback.pageSettled(isThisPage: true) == .none)
    }
    
    @Test
    func videoPausesWhenItsPageLeaves() {
        var playback = MediaViewerPlayback(autoplays: true, hasFile: true)
        _ = playback.pageSettled(isThisPage: true)
        
        #expect(playback.pageSettled(isThisPage: false) == .pause)
        #expect(playback.phase == .paused)
        // A page that wasn't playing has nothing to pause.
        #expect(playback.pageSettled(isThisPage: false) == .none)
        
        // Coming back carries on.
        #expect(playback.pageSettled(isThisPage: true) == .play)
    }
    
    @Test
    func videoWaitsForItsFile() {
        var playback = MediaViewerPlayback(autoplays: true, hasFile: false)
        
        #expect(playback.pageSettled(isThisPage: true) == .none)
        #expect(playback.playTapped() == .none, "Nothing to play until the file is there.")
        #expect(playback.showsPlayButton)
        
        #expect(playback.fileArrived() == .play)
        #expect(playback.phase == .playing)
    }
    
    @Test
    func fileArrivingOffScreenDoesNotPlay() {
        var playback = MediaViewerPlayback(autoplays: true, hasFile: false)
        _ = playback.pageSettled(isThisPage: false)
        
        #expect(playback.fileArrived() == .none)
        #expect(playback.pageSettled(isThisPage: true) == .play)
    }
    
    @Test
    func endedVideoShowsThePlayButtonAndRestarts() {
        var playback = MediaViewerPlayback(autoplays: true, hasFile: true)
        _ = playback.pageSettled(isThisPage: true)
        
        playback.didEnd()
        #expect(playback.showsPlayButton)
        #expect(playback.playTapped() == .restart)
        #expect(playback.phase == .playing)
        
        // Leaving after the end and coming back starts it again from the beginning.
        playback.didEnd()
        _ = playback.pageSettled(isThisPage: false)
        #expect(playback.pageSettled(isThisPage: true) == .restart)
    }
    
    @Test
    func systemControlsAreFollowed() {
        var playback = MediaViewerPlayback(autoplays: true, hasFile: true)
        _ = playback.pageSettled(isThisPage: true)
        
        playback.didPause()
        #expect(playback.phase == .paused)
        #expect(!playback.showsPlayButton, "A pause from the system's controls keeps those controls, not the big button.")
        playback.didPlay()
        #expect(playback.phase == .playing)
    }
    
    @Test
    func audioWaitsForATap() {
        var playback = MediaViewerPlayback(autoplays: false, hasFile: true)
        
        #expect(playback.pageSettled(isThisPage: true) == .none)
        #expect(playback.fileArrived() == .none)
        #expect(playback.showsPlayButton)
        #expect(playback.playTapped() == .play)
    }

    @Test
    func aNeighboursDownloadLeavesAPausedVideoPaused() {
        // A video the user paused, then watched to the end.
        var playback = MediaViewerPlayback(autoplays: true, hasFile: false)
        #expect(playback.settledPageUpdated(isNewSettle: true, hasFile: true) == .play)
        playback.didPause()
        
        // A neighbour's file arriving refreshes the settled page without the pager moving.
        #expect(playback.settledPageUpdated(isNewSettle: false, hasFile: true) == .none)
        #expect(playback.phase == .paused)
        
        playback.didEnd()
        #expect(playback.settledPageUpdated(isNewSettle: false, hasFile: true) == .none)
        #expect(playback.phase == .ended)
        
        // Only the pager coming to rest on it again starts it.
        _ = playback.pageSettled(isThisPage: false)
        #expect(playback.settledPageUpdated(isNewSettle: true, hasFile: true) == .restart)
    }
    
    @Test
    func theSettledVideosOwnFileStartsIt() {
        var playback = MediaViewerPlayback(autoplays: true, hasFile: false)
        #expect(playback.settledPageUpdated(isNewSettle: true, hasFile: false) == .none)
        #expect(playback.settledPageUpdated(isNewSettle: false, hasFile: false) == .none)
        #expect(playback.settledPageUpdated(isNewSettle: false, hasFile: true) == .play)
        #expect(playback.settledPageUpdated(isNewSettle: false, hasFile: true) == .none)
    }
    
    /// AGENT-PLATFORM (1.0.2, Fable review of ee42fd8a4): a call coming up closes the viewer as CallKit activates the
    /// session for it. Handing the audio back after a video then deactivated the call's session or put the
    /// pre-video category back: the viewer leaves a session a call has taken alone.
    @Test
    func theAudioAfterAVideoStaysWithACall() {
        #expect(MediaViewerAudioSession.callOwnsTheAudio(isHeldByCall: true, category: .playback), "a call claimed it")
        #expect(MediaViewerAudioSession.callOwnsTheAudio(isHeldByCall: false, category: .playAndRecord), "configured for a call")
        #expect(!MediaViewerAudioSession.callOwnsTheAudio(isHeldByCall: false, category: .playback), "the video's own, handed back")
    }
}
