import AVFoundation
import Combine
import UIKit

/// One recording saved in a notebook's audio folder.
struct Recording: Codable, Equatable, Identifiable {
    var id: UUID
    var file: String
    var started: Date
    var duration: Double

    var title: String {
        started.formatted(date: .abbreviated, time: .shortened) + " · " + Recording.clock(duration)
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// The recording running at `date`, and how far into it that moment is.
    static func match(_ date: Date, in recordings: [Recording]) -> (Recording, TimeInterval)? {
        for recording in recordings {
            let offset = date.timeIntervalSince(recording.started)
            if offset >= 0 && offset <= recording.duration { return (recording, offset) }
        }
        return nil
    }
}

/// Notability-style lecture recording: ink written while recording remembers the moment,
/// so tapping it later plays the audio from there.
final class AudioController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var current: Recording?
    @Published private(set) var isPlaying = false
    @Published var position: TimeInterval = 0
    @Published var errorMessage: String?

    weak var document: NotebookDocument?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var startedAt: Date?
    private var fileName: String?

    var recordings: [Recording] { document?.meta.recordings ?? [] }

    // MARK: Recording

    func startRecording() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.beginRecording()
                } else {
                    self?.errorMessage = "Slate needs the microphone to record. Turn it on in Settings › Privacy & Security › Microphone."
                }
            }
        }
    }

    private func beginRecording() {
        guard let document, !isRecording else { return }
        stopPlayback()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            try FileManager.default.createDirectory(at: document.paths.audioDir, withIntermediateDirectories: true)
            let name = UUID().uuidString + ".m4a"
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 22_050,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
            ]
            let recorder = try AVAudioRecorder(url: document.paths.audioDir.appendingPathComponent(name), settings: settings)
            guard recorder.record() else { throw SlateError.writeFailed("the recording") }
            self.recorder = recorder
            fileName = name
            startedAt = Date()
            elapsed = 0
            isRecording = true
            startTimer()
        } catch {
            errorMessage = "Could not start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        guard let recorder, let startedAt, let fileName else { return }
        recorder.stop()
        self.recorder = nil
        isRecording = false
        let recording = Recording(id: UUID(), file: fileName, started: startedAt, duration: Date().timeIntervalSince(startedAt))
        document?.meta.recordings.append(recording)
        try? document?.saveMeta()
        self.startedAt = nil
        self.fileName = nil
        stopTimerIfIdle()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Playback

    func play(_ recording: Recording, from offset: TimeInterval = 0) {
        guard let document, !isRecording else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            if current?.id != recording.id || player == nil {
                let player = try AVAudioPlayer(contentsOf: document.paths.audioDir.appendingPathComponent(recording.file))
                player.delegate = self
                player.prepareToPlay()
                self.player = player
                current = recording
            }
            guard let player else { return }
            player.currentTime = min(max(0, offset), max(player.duration - 0.1, 0))
            player.play()
            position = player.currentTime
            isPlaying = true
            startTimer()
        } catch {
            errorMessage = "Could not play the recording: \(error.localizedDescription)"
        }
    }

    func togglePlay() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        position = time
    }

    var duration: TimeInterval { player?.duration ?? current?.duration ?? 0 }

    func stopPlayback() {
        player?.stop()
        player = nil
        current = nil
        isPlaying = false
        stopTimerIfIdle()
    }

    /// Plays whatever was being recorded when ink was written at `date`, from a moment before.
    @discardableResult
    func jump(to date: Date) -> Bool {
        guard let match = Recording.match(date, in: recordings) else { return false }
        play(match.0, from: match.1 - 2)
        return true
    }

    func delete(_ recording: Recording) {
        if current?.id == recording.id { stopPlayback() }
        guard let document else { return }
        document.meta.recordings.removeAll { $0.id == recording.id }
        try? document.saveMeta()
        try? FileManager.default.removeItem(at: document.paths.audioDir.appendingPathComponent(recording.file))
        objectWillChange.send()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }

    // MARK: Timer

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func stopTimerIfIdle() {
        guard !isRecording && !isPlaying else { return }
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if isRecording, let startedAt { elapsed = Date().timeIntervalSince(startedAt) }
        if let player { position = player.currentTime }
        if !isRecording && !isPlaying { stopTimerIfIdle() }
    }
}
