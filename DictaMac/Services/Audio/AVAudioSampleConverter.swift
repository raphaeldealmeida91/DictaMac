@preconcurrency import AVFoundation

final class AVAudioSampleConverter: AudioSampleConverting, @unchecked Sendable {
    private static let capacityPadding: AVAudioFrameCount = 32
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter

    init?(
        inputFormat: AVAudioFormat,
        sampleRate: Double
    ) {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return nil
        }
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.converter = converter
    }

    func convert(
        _ inputBuffer: AVAudioPCMBuffer,
        sink: any AudioSampleAccumulating
    ) {
        guard let outputBuffer = makeOutputBuffer(for: inputBuffer) else { return }
        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) {
            _, inputStatus in
            guard !suppliedInput else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }
        guard conversionError == nil,
              status != .error,
              outputBuffer.frameLength > 0,
              let channel = outputBuffer.floatChannelData?[0] else { return }
        sink.append(channel, count: Int(outputBuffer.frameLength))
    }

    private func makeOutputBuffer(for inputBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let convertedFrames = ceil(Double(inputBuffer.frameLength) * ratio)
        let capacity = max(1, AVAudioFrameCount(convertedFrames) + Self.capacityPadding)
        return AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
    }
}

struct AVAudioSampleConverterBuilder: AudioSampleConverterBuilding {
    func makeConverter(
        from inputFormat: AVAudioFormat,
        sampleRate: Double
    ) -> (any AudioSampleConverting)? {
        AVAudioSampleConverter(inputFormat: inputFormat, sampleRate: sampleRate)
    }
}
