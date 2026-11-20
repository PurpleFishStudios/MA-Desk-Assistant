//
//  HomeSpeech.swift
//  MADeskAssistant
//

import AVFoundation
import Foundation
import Speech

@MainActor
@Observable
final class HomeSpeech {
    var isListening = false
    var status = "Voice is off."
    var liveText = ""
    var inputLevel = 0.0
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var userStopped = false

    func toggle(onText: @escaping (String) -> Void) {
        if isListening {
            stop()
            return
        }
        userStopped = false
        liveText = ""
        inputLevel = 0
        isListening = true
        status = "Microphone is starting."
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            Task { @MainActor in
                guard let self else { return }
                guard !self.userStopped else { return }
                guard auth == .authorized else {
                    self.isListening = false
                    self.status = "Speech recognition is not allowed. You can still type."
                    return
                }
                self.start(onText: onText)
            }
        }
    }

    private func start(onText: @escaping (String) -> Void) {
        stopEngine()
        guard let recognizer, recognizer.isAvailable else {
            isListening = false
            status = "Speech recognition is not available on this Mac right now."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let level = Self.level(of: buffer)
            Task { @MainActor in
                self?.inputLevel = level
                if level > 0.08, self?.liveText.isEmpty == true {
                    self?.status = "I hear sound. Keep speaking."
                }
            }
        }
        tapInstalled = true
        do {
            engine.prepare()
            try engine.start()
        } catch {
            isListening = false
            status = "The microphone did not start: \(error.localizedDescription)"
            stopEngine()
            return
        }
        isListening = true
        status = "Listening. Your words will appear here. Click the microphone again when you are done."
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, !self.userStopped else { return }
                if let result {
                    let spoken = result.bestTranscription.formattedString
                    if !spoken.isEmpty {
                        self.liveText = spoken
                        self.status = "Heard: \(spoken)"
                        onText(spoken)
                    }
                }
                if error != nil, self.liveText.isEmpty {
                    self.status = "Microphone is on. I have not heard words yet."
                }
            }
        }
    }

    func stop() {
        userStopped = true
        request?.endAudio()
        stopEngine()
        isListening = false
        inputLevel = 0
        status = liveText.isEmpty
            ? "Voice stopped. I did not catch any words."
            : "Voice stopped. Review the text, then press Ask."
    }

    private func stopEngine() {
        task?.cancel()
        task = nil
        request = nil
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    private static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))
        return min(1, Double(rms) * 14)
    }
}
