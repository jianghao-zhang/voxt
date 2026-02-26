import Foundation
import AVFoundation
import Combine
@preconcurrency import MLX
import MLXAudioCore
import MLXAudioSTT

@MainActor
class MLXTranscriber: ObservableObject, TranscriberProtocol {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText = ""
    @Published var isEnhancing = false

    var onTranscriptionFinished: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private var inputSampleRate: Double = 16000
    private let modelManager: MLXModelManager
    private let targetSampleRate = 16000

    init(modelManager: MLXModelManager) {
        self.modelManager = modelManager
    }

    func requestPermissions() async -> Bool {
        let micStatus = await AVCaptureDevice.requestAccess(for: .audio)
        return micStatus
    }

    func startRecording() {
        guard !isRecording else { return }

        resetTransientState()

        do {
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputSampleRate = recordingFormat.sampleRate

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                guard let self else { return }

                if let channelData = buffer.floatChannelData?[0] {
                    let frameLength = Int(buffer.frameLength)
                    let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
                    self.audioBuffer.append(contentsOf: samples)

                    if frameLength > 0 {
                        var rms: Float = 0
                        for i in 0..<frameLength {
                            rms += channelData[i] * channelData[i]
                        }
                        rms = sqrt(rms / Float(frameLength))
                        let normalized = min(rms * 20, 1.0)
                        Task { @MainActor [weak self] in
                            self?.audioLevel = normalized
                        }
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            VoxtLog.error("MLXTranscriber start recording failed: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        stopAudioEngine()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false

        let capturedAudio = audioBuffer
        audioBuffer = []

        guard !capturedAudio.isEmpty else {
            onTranscriptionFinished?("")
            return
        }

        Task {
            await transcribeAudio(capturedAudio, sampleRate: inputSampleRate)
        }
    }

    private func transcribeAudio(_ samples: [Float], sampleRate: Double) async {
        do {
            let model = try await modelManager.loadModel()
            let audioSamples = try prepareInputSamples(samples, sampleRate: sampleRate)
            let (streamedText, finalOutput) = try await runStreamingInference(model: model, audioSamples: audioSamples)

            let text = (finalOutput?.text ?? streamedText).trimmingCharacters(in: .whitespacesAndNewlines)
            transcribedText = text
            onTranscriptionFinished?(text)
        } catch {
            VoxtLog.error("MLXTranscriber transcription failed: \(error)")
            onTranscriptionFinished?("")
        }
    }

    private func resetTransientState() {
        audioBuffer = []
        transcribedText = ""
        audioLevel = 0
    }

    private func stopAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    private func prepareInputSamples(_ samples: [Float], sampleRate: Double) throws -> [Float] {
        if abs(sampleRate - Double(targetSampleRate)) > 1.0 {
            return try resampleAudio(samples, from: Int(sampleRate), to: targetSampleRate)
        }

        return samples
    }

    private func runStreamingInference(
        model: any STTGenerationModel,
        audioSamples: [Float]
    ) async throws -> (streamedText: String, finalOutput: STTOutput?) {
        let audioArray = MLXArray(audioSamples)
        var streamedText = ""
        var finalOutput: STTOutput?

        for try await event in model.generateStream(audio: audioArray) {
            switch event {
            case .token(let token):
                streamedText += token
                transcribedText = streamedText.trimmingCharacters(in: .whitespacesAndNewlines)
                await Task.yield()
            case .info:
                break
            case .result(let output):
                finalOutput = output
            }
        }

        return (streamedText, finalOutput)
    }
}
