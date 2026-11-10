@preconcurrency import AVFoundation

protocol AudioSampleConverting: Sendable {
    func convert(
        _ inputBuffer: AVAudioPCMBuffer,
        sink: any AudioSampleAccumulating
    )
}

protocol AudioSampleConverterBuilding: Sendable {
    func makeConverter(
        from inputFormat: AVAudioFormat,
        sampleRate: Double
    ) -> (any AudioSampleConverting)?
}
