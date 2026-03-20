import AVFoundation
import Accelerate

enum AudioUtilsError: Error, LocalizedError {
    case fileNotFound(String)
    case invalidFormat(String)
    case conversionFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "오디오 파일을 찾을 수 없습니다: \(path)"
        case .invalidFormat(let msg): return "잘못된 오디오 포맷: \(msg)"
        case .conversionFailed(let msg): return "오디오 변환 실패: \(msg)"
        case .writeFailed(let msg): return "WAV 저장 실패: \(msg)"
        }
    }
}

struct AudioUtils {
    static let sampleRate: Double = 24000
    static let samplesPerFrame: Int = 1920

    /// WAV/오디오 파일 → Float32 모노 배열 (24kHz)
    static func loadAudio(from path: String) throws -> [Float] {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw AudioUtilsError.fileNotFound(path)
        }

        let file = try AVAudioFile(forReading: url)
        let sourceRate = file.processingFormat.sampleRate
        let sourceChannels = file.processingFormat.channelCount
        let frameCount = AVAudioFrameCount(file.length)

        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ) else {
            throw AudioUtilsError.invalidFormat("버퍼 생성 실패")
        }
        try file.read(into: sourceBuffer)

        // 모노 다운믹스
        var monoSamples = toMono(buffer: sourceBuffer, channels: Int(sourceChannels))

        // 리샘플링 (24kHz가 아니면)
        if abs(sourceRate - sampleRate) > 1.0 {
            monoSamples = try resample(
                samples: monoSamples,
                fromRate: sourceRate,
                toRate: sampleRate
            )
        }

        // 정규화 (|max| ≤ 1.0)
        var absValues = [Float](repeating: 0, count: monoSamples.count)
        vDSP.absolute(monoSamples, result: &absValues)
        let maxAbs = vDSP.maximum(absValues)
        if maxAbs > 1.0 {
            vDSP.divide(monoSamples, maxAbs, result: &monoSamples)
        }

        return monoSamples
    }

    /// Float32 PCM 배열 → WAV 파일 저장
    static func saveWav(samples: [Float], to path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioUtilsError.writeFailed("오디오 포맷 생성 실패")
        }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioUtilsError.writeFailed("버퍼 생성 실패")
        }
        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                channelData.update(from: src.baseAddress!, count: samples.count)
            }
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    // MARK: - Private

    private static func toMono(buffer: AVAudioPCMBuffer, channels: Int) -> [Float] {
        let frameCount = Int(buffer.frameLength)
        guard let channelData = buffer.floatChannelData else { return [] }

        if channels == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        }

        // 스테레오 → 모노 (채널 평균)
        var mono = [Float](repeating: 0, count: frameCount)
        for ch in 0..<channels {
            let chPtr = channelData[ch]
            for i in 0..<frameCount {
                mono[i] += chPtr[i]
            }
        }
        let scale = 1.0 / Float(channels)
        vDSP.multiply(scale, mono, result: &mono)
        return mono
    }

    private static func resample(
        samples: [Float],
        fromRate: Double,
        toRate: Double
    ) throws -> [Float] {
        let ratio = toRate / fromRate
        let outputCount = Int(Double(samples.count) * ratio)
        var output = [Float](repeating: 0, count: outputCount)

        // vDSP 선형 보간 리샘플링
        var control = (0..<outputCount).map { Float(Double($0) / ratio) }
        vDSP_vlint(
            samples, &control, 1,
            &output, 1,
            vDSP_Length(outputCount),
            vDSP_Length(samples.count)
        )
        return output
    }
}
