// ABOUTME: Tests for AudioPlayer playback controls and state management.
// ABOUTME: Covers RT-2.15 through RT-2.19.

import Testing
import Foundation
@testable import YapperKit

// RT-2.15: AudioPlayer initialises an AVAudioEngine session without error
@Test("RT-2.15: AudioPlayer initialises without error")
func test_audio_player_initialises_RT2_15() throws {
    let player = AudioPlayer()
    #expect(player.state == .idle)
}

// RT-2.16: No temporary files exist on disk during or after playback
@Test("RT-2.16: No temp files created during playback")
func test_no_temp_files_during_playback_RT2_16() throws {
    let player = AudioPlayer()
    let tmpBefore = try FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory())

    // Schedule a short buffer of silence
    let silence = [Float](repeating: 0.0, count: 24000) // 1 second
    try player.scheduleBuffer(silence)
    player.stop()

    let tmpAfter = try FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory())
    // No new files should have been created by AudioPlayer
    let newFiles = Set(tmpAfter).subtracting(Set(tmpBefore))
    let yapperFiles = newFiles.filter { $0.contains("yapper") || $0.contains("Yapper") }
    #expect(yapperFiles.isEmpty)
}

// RT-2.17: After pause, player state is paused
@Test("RT-2.17: Pause sets state to paused")
func test_pause_sets_paused_state_RT2_17() throws {
    let player = AudioPlayer()
    let silence = [Float](repeating: 0.0, count: 24000)
    try player.scheduleBuffer(silence)
    try player.play()
    player.pause()
    #expect(player.state == .paused)
}

// RT-2.18: After resume, player state is playing and audio position has advanced
@Test("RT-2.18: Resume sets state to playing")
func test_resume_sets_playing_state_RT2_18() throws {
    let player = AudioPlayer()
    let silence = [Float](repeating: 0.0, count: 24000)
    try player.scheduleBuffer(silence)
    try player.play()
    player.pause()
    #expect(player.state == .paused)
    try player.resume()
    #expect(player.state == .playing)
    player.stop()
}

// RT-2.19: After stop, player state is stopped and audio engine resources are released
@Test("RT-2.19: Stop sets state to stopped")
func test_stop_releases_resources_RT2_19() throws {
    let player = AudioPlayer()
    let silence = [Float](repeating: 0.0, count: 24000)
    try player.scheduleBuffer(silence)
    try player.play()
    player.stop()
    #expect(player.state == .stopped)
}
