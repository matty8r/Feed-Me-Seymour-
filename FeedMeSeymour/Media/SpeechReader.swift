//
//  SpeechReader.swift
//  Feed Me, Seymour!
//
//  Reads an article aloud with `AVSpeechSynthesizer`.
//
//  Each segment of the script becomes its own utterance. That costs a little
//  bookkeeping and buys a lot: pausing at a sensible place, skipping by
//  paragraph, knowing which block is being spoken so the view can scroll to it
//  and light up the current word, and honest per-segment pauses around
//  headings and pull quotes.
//

import Foundation
import AVFoundation
import Observation
import SwiftData

@MainActor
@Observable
final class SpeechReader: NSObject {

    static let shared = SpeechReader()

    // MARK: State

    private(set) var segments: [SpeechSegment] = []
    private(set) var currentIndex = 0
    private(set) var isSpeaking = false
    private(set) var isPaused = false
    private(set) var articleID: PersistentIdentifier?
    private(set) var articleTitle: String = ""

    /// The range of the current segment being spoken, as an offset into that
    /// segment's text. Only set for segments that track what is on screen.
    private(set) var spokenRange: Range<Int>?

    /// Bumped whenever an article is read to its end. Whoever wants to
    /// auto-advance watches this rather than holding a callback.
    private(set) var finishedCount = 0

    // MARK: Internals

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var enqueued: [ObjectIdentifier: (generation: Int, index: Int)] = [:]
    @ObservationIgnored private var voiceIdentifier: String?
    @ObservationIgnored private var languageCode: String?
    @ObservationIgnored private var rateMultiplier: Double = 1
    @ObservationIgnored private var pitch: Double = 1

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: Derived

    var isActive: Bool { !segments.isEmpty }

    var currentSegment: SpeechSegment? {
        segments.indices.contains(currentIndex) ? segments[currentIndex] : nil
    }

    var currentBlockID: UUID? { currentSegment?.blockID }

    /// Where we are, counted in paragraphs rather than seconds — the only
    /// honest unit when a synthesizer sets the pace.
    var progress: Double {
        guard segments.count > 1 else { return segments.isEmpty ? 0 : 1 }
        return Double(currentIndex) / Double(segments.count - 1)
    }

    func isReading(_ article: Article) -> Bool {
        articleID == article.persistentModelID && isActive
    }

    // MARK: - Transport

    func start(article: Article, rendered: RenderedArticle, settings: ReaderSettings) {
        stop()

        let script = SpeechScript.segments(
            article: article,
            rendered: rendered,
            announcesImages: settings.announcesImagesAloud
        )
        guard !script.isEmpty else { return }

        segments = script
        currentIndex = 0
        articleID = article.persistentModelID
        articleTitle = article.displayTitle
        languageCode = SpeechScript.dominantLanguage(of: script)
        applySettings(settings)

        AudioSession.activatePlayback()
        NowPlayingCenter.shared.activate(
            self,
            title: article.displayTitle,
            artist: article.feed?.displayTitle,
            artworkURL: article.bannerImageURL ?? article.feed?.effectiveIconURL
        )

        isSpeaking = true
        isPaused = false
        enqueue(from: 0)
    }

    func applySettings(_ settings: ReaderSettings) {
        voiceIdentifier = settings.voiceIdentifier
        rateMultiplier = settings.speechRate
        pitch = settings.speechPitch
    }

    /// Changing voice or rate mid-article restarts from the current paragraph,
    /// which is the only thing `AVSpeechSynthesizer` allows and, as it happens,
    /// the least jarring place to do it.
    func reapply(settings: ReaderSettings) {
        applySettings(settings)
        guard isSpeaking, !isPaused else { return }
        enqueue(from: currentIndex)
    }

    func pause() {
        guard isSpeaking, !isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
        NowPlayingCenter.shared.update(elapsed: nil, duration: nil, rate: 0, for: self)
    }

    func resume() {
        guard isActive else { return }
        AudioSession.activatePlayback()
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        } else {
            enqueue(from: currentIndex)
        }
        isSpeaking = true
        isPaused = false
        NowPlayingCenter.shared.update(elapsed: nil, duration: nil, rate: 1, for: self)
    }

    func toggle() {
        isPaused || !isSpeaking ? resume() : pause()
    }

    func stop() {
        generation += 1
        enqueued.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        segments = []
        currentIndex = 0
        spokenRange = nil
        isSpeaking = false
        isPaused = false
        articleID = nil
        articleTitle = ""
        NowPlayingCenter.shared.resign(self)
    }

    func skipForward() {
        guard currentIndex + 1 < segments.count else {
            finish()
            return
        }
        move(to: currentIndex + 1)
    }

    func skipBackward() {
        move(to: max(0, currentIndex - 1))
    }

    func jump(to index: Int) {
        guard segments.indices.contains(index) else { return }
        move(to: index)
    }

    private func move(to index: Int) {
        currentIndex = index
        spokenRange = nil
        if isPaused {
            // Stay paused, but at the new place.
            generation += 1
            enqueued.removeAll()
            synthesizer.stopSpeaking(at: .immediate)
        } else {
            enqueue(from: index)
        }
    }

    private func finish() {
        stop()
        finishedCount += 1
    }

    // MARK: - Queueing

    private func enqueue(from index: Int) {
        // A new generation invalidates every callback still in flight from the
        // utterances we are about to cancel.
        generation += 1
        let thisGeneration = generation
        enqueued.removeAll()
        synthesizer.stopSpeaking(at: .immediate)

        guard segments.indices.contains(index) else { return }
        currentIndex = index
        spokenRange = nil

        for position in index..<segments.count {
            let utterance = makeUtterance(for: segments[position])
            enqueued[ObjectIdentifier(utterance)] = (thisGeneration, position)
            synthesizer.speak(utterance)
        }
    }

    private func makeUtterance(for segment: SpeechSegment) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: segment.text)
        utterance.voice = resolvedVoice()
        utterance.rate = Self.synthesizerRate(for: rateMultiplier)
        utterance.pitchMultiplier = Float(min(max(pitch, 0.5), 2.0))
        utterance.preUtteranceDelay = segment.preDelay
        utterance.postUtteranceDelay = segment.postDelay
        return utterance
    }

    /// The reader's chosen voice, unless the article is plainly in another
    /// language — a French piece read by an English voice is unlistenable.
    private func resolvedVoice() -> AVSpeechSynthesisVoice? {
        let preferred = voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))

        guard let languageCode else {
            return preferred ?? AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        }

        if let preferred, preferred.language.lowercased().hasPrefix(languageCode.lowercased()) {
            return preferred
        }
        return AVSpeechSynthesisVoice(language: languageCode) ?? preferred
    }

    /// `AVSpeechUtterance` rates are not a multiplier, so map one onto the
    /// range either side of the system default.
    static func synthesizerRate(for multiplier: Double) -> Float {
        let base = Double(AVSpeechUtteranceDefaultSpeechRate)
        let value = multiplier >= 1
            ? base + (Double(AVSpeechUtteranceMaximumSpeechRate) - base) * min(multiplier - 1, 1) * 0.6
            : base - (base - Double(AVSpeechUtteranceMinimumSpeechRate)) * min(1 - multiplier, 1)
        return Float(min(max(value, Double(AVSpeechUtteranceMinimumSpeechRate)), Double(AVSpeechUtteranceMaximumSpeechRate)))
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechReader: AVSpeechSynthesizerDelegate {

    private func index(for utterance: AVSpeechUtterance) -> Int? {
        guard let entry = enqueued[ObjectIdentifier(utterance)], entry.generation == generation else { return nil }
        return entry.index
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard let index = index(for: utterance) else { return }
            currentIndex = index
            spokenRange = nil
            isSpeaking = true
            isPaused = false
            NowPlayingCenter.shared.update(elapsed: nil, duration: nil, rate: 1, for: self)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard let index = index(for: utterance), index == currentIndex,
                  segments.indices.contains(index), segments[index].tracksOnScreen else {
                spokenRange = nil
                return
            }
            // NSRange is in UTF-16; the view needs character offsets.
            let text = segments[index].text
            guard let range = Range(characterRange, in: text) else {
                spokenRange = nil
                return
            }
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let end = text.distance(from: text.startIndex, to: range.upperBound)
            spokenRange = start..<end
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard let index = index(for: utterance) else { return }
            spokenRange = nil
            if index >= segments.count - 1 {
                finish()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard index(for: utterance) != nil else { return }
            isPaused = true
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard index(for: utterance) != nil else { return }
            isPaused = false
            isSpeaking = true
        }
    }
}

// MARK: - Now Playing

extension SpeechReader: NowPlayingSource {
    var nowPlayingIsPlaying: Bool { isSpeaking && !isPaused }
    var nowPlayingSupportsSeeking: Bool { false }

    func nowPlayingPlay() { resume() }
    func nowPlayingPause() { pause() }
    func nowPlayingNext() { skipForward() }
    func nowPlayingPrevious() { skipBackward() }
    func nowPlayingSeek(to seconds: Double) {}
    func nowPlayingWasSuperseded() { stop() }
}

// MARK: - Voices

struct SpeechVoice: Identifiable, Hashable {
    var id: String
    var name: String
    var language: String
    var quality: String?
    var isPersonal: Bool

    var displayName: String {
        quality.map { "\(name) — \($0)" } ?? name
    }
}

enum SpeechVoiceCatalog {

    /// Voices for a language, best quality first. Passing nil uses the system
    /// language, which is what an unconfigured install should read in.
    static func voices(for languageCode: String?) -> [SpeechVoice] {
        let wanted = (languageCode ?? AVSpeechSynthesisVoice.currentLanguageCode()).lowercased()
        let prefix = String(wanted.prefix(2))

        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix(prefix) }
            .sorted { lhs, rhs in
                if rank(lhs.quality) != rank(rhs.quality) { return rank(lhs.quality) > rank(rhs.quality) }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .map { voice in
                SpeechVoice(
                    id: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    quality: label(for: voice.quality),
                    isPersonal: voice.voiceTraits.contains(.isPersonalVoice)
                )
            }
    }

    private static func rank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium: 3
        case .enhanced: 2
        default: 1
        }
    }

    private static func label(for quality: AVSpeechSynthesisVoiceQuality) -> String? {
        switch quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: nil
        }
    }

    // MARK: Personal Voice

    static var personalVoiceStatus: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus {
        AVSpeechSynthesizer.personalVoiceAuthorizationStatus
    }

    static var canRequestPersonalVoice: Bool {
        personalVoiceStatus == .notDetermined
    }

    static func requestPersonalVoiceAccess() async -> Bool {
        await AVSpeechSynthesizer.requestPersonalVoiceAuthorization() == .authorized
    }
}
