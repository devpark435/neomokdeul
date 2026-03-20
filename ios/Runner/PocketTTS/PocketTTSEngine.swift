import Foundation
import onnxruntime_objc

enum TTSEngineError: Error, LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(String)
    case encodingFailed(String)
    case generationFailed(String)
    case tokenizerFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "모델이 로드되지 않았습니다."
        case .modelLoadFailed(let msg): return "모델 로드 실패: \(msg)"
        case .encodingFailed(let msg): return "음성 인코딩 실패: \(msg)"
        case .generationFailed(let msg): return "음성 생성 실패: \(msg)"
        case .tokenizerFailed(let msg): return "토크나이저 실패: \(msg)"
        }
    }
}

/// Pocket TTS ONNX 추론 엔진
class PocketTTSEngine {

    // MARK: - 상수 (ONNX_PIPELINE.md 기준)

    static let sampleRate: Int = 24000
    static let samplesPerFrame: Int = 1920
    static let latentDim: Int = 32
    static let dModel: Int = 1024
    static let defaultTemperature: Float = 0.7
    static let lsdDecodeSteps: Int = 10
    static let eosThreshold: Float = -4.0
    static let framesAfterEos: Int = 3
    static let maxFrames: Int = 500
    static let decoderChunkSize: Int = 15

    // MARK: - ONNX 세션

    private var mimiEncoder: ORTSession?
    private var textConditioner: ORTSession?
    private var flowLmMain: ORTSession?
    private var flowLmFlow: ORTSession?
    private var mimiDecoder: ORTSession?

    private var env: ORTEnv?
    private var modelDirectory: String?

    private(set) var isLoaded = false
    var onProgress: ((Double) -> Void)?

    // MARK: - 모델 로드

    func loadModels(directory: String) throws {
        modelDirectory = directory
        env = try ORTEnv(loggingLevel: .warning)

        let sessionOptions = try createSessionOptions()

        let models: [(String, String?)] = [
            ("mimi_encoder.onnx", nil),
            ("text_conditioner.onnx", nil),
            ("flow_lm_main_int8.onnx", "flow_lm_main.onnx"),
            ("flow_lm_flow_int8.onnx", "flow_lm_flow.onnx"),
            ("mimi_decoder_int8.onnx", "mimi_decoder.onnx"),
        ]

        for (i, (name, fallback)) in models.enumerated() {
            let path = (directory as NSString).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: path) {
                try loadSession(name: name, path: path, options: sessionOptions)
            } else if let fb = fallback {
                let fbPath = (directory as NSString).appendingPathComponent(fb)
                guard FileManager.default.fileExists(atPath: fbPath) else {
                    throw TTSEngineError.modelLoadFailed("\(name) 또는 \(fb) 파일 없음")
                }
                try loadSession(name: fb, path: fbPath, options: sessionOptions)
            } else {
                throw TTSEngineError.modelLoadFailed("\(name) 파일 없음")
            }
            onProgress?(Double(i + 1) / Double(models.count) * 0.5)
        }

        isLoaded = true
        onProgress?(0.5)
    }

    // MARK: - Voice Encoding

    func encodeVoice(audioPath: String) throws -> String {
        guard isLoaded, let encoder = mimiEncoder else {
            throw TTSEngineError.modelNotLoaded
        }

        let samples = try AudioUtils.loadAudio(from: audioPath)

        // 텐서: [1, 1, T]
        let audioTensor = try createFloatTensor(
            from: samples,
            shape: [1, 1, NSNumber(value: samples.count)]
        )

        let outputNames = try encoder.outputNames()
        let outputs = try encoder.run(
            withInputs: ["audio": audioTensor],
            outputNames: Set(outputNames),
            runOptions: nil
        )

        guard let embeddingValue = outputs[outputNames[0]] else {
            throw TTSEngineError.encodingFailed("임베딩 출력 없음")
        }

        let embeddingData = try embeddingValue.tensorData() as Data
        let shape = try embeddingValue.tensorTypeAndShapeInfo().shape

        // 헤더: [N(int32), dim(int32)] + float32 데이터
        let outputPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("voice_embedding_\(UUID().uuidString).bin")
        var header = Data()
        var n = Int32(shape[1].intValue)
        var dim = Int32(shape[2].intValue)
        header.append(Data(bytes: &n, count: 4))
        header.append(Data(bytes: &dim, count: 4))
        header.append(embeddingData)
        try header.write(to: URL(fileURLWithPath: outputPath))

        return outputPath
    }

    // MARK: - Speech Generation

    func generateSpeech(text: String, embeddingPath: String, temperature: Float = 0.7) throws -> String {
        guard isLoaded,
              let conditioner = textConditioner,
              let lmMain = flowLmMain,
              let lmFlow = flowLmFlow,
              let decoder = mimiDecoder else {
            throw TTSEngineError.modelNotLoaded
        }

        onProgress?(0.0)

        // 1. 임베딩 로드
        let (voiceEmb, voiceN) = try loadEmbedding(from: embeddingPath)

        // 2. 텍스트 전처리 + 토큰화
        let processedText = preprocessText(text)
        let tokenIds = try tokenize(processedText)

        // 3. text_conditioner
        let textEmb = try runTextConditioner(session: conditioner, tokenIds: tokenIds)
        onProgress?(0.1)

        // 4. flow_lm_main state 초기화
        var mainState = try initState(session: lmMain)

        // 5. Voice conditioning pass
        let emptySeq = try createFloatTensor(from: [], shape: [1, 0, NSNumber(value: Self.latentDim)])
        let voiceTensor = try createFloatTensor(
            fromData: voiceEmb,
            shape: [1, NSNumber(value: voiceN), NSNumber(value: Self.dModel)]
        )
        mainState = try runFlowLmMain(session: lmMain, sequence: emptySeq, textEmbeddings: voiceTensor, state: &mainState).state

        // 6. Text conditioning pass
        let textTensor = try createFloatTensor(
            fromData: textEmb,
            shape: [1, NSNumber(value: tokenIds.count), NSNumber(value: Self.dModel)]
        )
        mainState = try runFlowLmMain(session: lmMain, sequence: emptySeq, textEmbeddings: textTensor, state: &mainState).state
        onProgress?(0.15)

        // 7. Autoregressive loop
        var latents: [[Float]] = []
        var curr = createBosLatent()
        var eosDetected = false
        var framesAfterEosCount = 0

        for frame in 0..<Self.maxFrames {
            let currTensor = try createFloatTensor(from: curr, shape: [1, 1, NSNumber(value: Self.latentDim)])
            let emptyEmb = try createFloatTensor(from: [], shape: [1, 0, NSNumber(value: Self.dModel)])

            let mainResult = try runFlowLmMain(session: lmMain, sequence: currTensor, textEmbeddings: emptyEmb, state: &mainState)
            mainState = mainResult.state

            if mainResult.eosLogit > Self.eosThreshold {
                eosDetected = true
            }
            if eosDetected {
                framesAfterEosCount += 1
                if framesAfterEosCount > Self.framesAfterEos { break }
            }

            let latent = try flowMatch(session: lmFlow, conditioning: mainResult.conditioning, temperature: temperature)
            latents.append(latent)
            curr = latent

            onProgress?(min(0.15 + 0.7 * Double(frame + 1) / Double(Self.maxFrames), 0.85))
        }

        // 8. 디코딩
        let pcmSamples = try decodeLatents(session: decoder, latents: latents)
        onProgress?(0.95)

        // 9. WAV 저장
        let outputPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("tts_output_\(UUID().uuidString).wav")
        try AudioUtils.saveWav(samples: pcmSamples, to: outputPath)
        onProgress?(1.0)

        return outputPath
    }

    // MARK: - 리소스 해제

    func dispose() {
        mimiEncoder = nil
        textConditioner = nil
        flowLmMain = nil
        flowLmFlow = nil
        mimiDecoder = nil
        env = nil
        isLoaded = false
    }

    // MARK: - Private: 세션 설정

    private func createSessionOptions() throws -> ORTSessionOptions {
        let options = try ORTSessionOptions()
        let threadCount = min(ProcessInfo.processInfo.processorCount, 4)
        try options.setIntraOpNumThreads(Int32(threadCount))
        try options.setGraphOptimizationLevel(.all)

        if ORTIsCoreMLExecutionProviderAvailable() {
            let coremlOptions = ORTCoreMLExecutionProviderOptions()
            try? options.appendCoreMLExecutionProvider(with: coremlOptions)
        }

        return options
    }

    private func loadSession(name: String, path: String, options: ORTSessionOptions) throws {
        guard let env = env else { throw TTSEngineError.modelLoadFailed("env 없음") }
        let session = try ORTSession(env: env, modelPath: path, sessionOptions: options)

        if name.contains("mimi_encoder") { mimiEncoder = session }
        else if name.contains("text_conditioner") { textConditioner = session }
        else if name.contains("flow_lm_main") { flowLmMain = session }
        else if name.contains("flow_lm_flow") { flowLmFlow = session }
        else if name.contains("mimi_decoder") { mimiDecoder = session }
    }

    // MARK: - Private: 텍스트 전처리

    private func preprocessText(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = result.last, last.isLetter || last.isNumber {
            result.append(".")
        }
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }
        return result
    }

    // TODO: SentencePiece C 라이브러리 연동 (현재 UTF-8 바이트 폴백)
    private func tokenize(_ text: String) throws -> [Int64] {
        guard let modelDir = modelDirectory else {
            throw TTSEngineError.tokenizerFailed("모델 디렉토리 없음")
        }
        let tokenizerPath = (modelDir as NSString).appendingPathComponent("tokenizer.model")
        guard FileManager.default.fileExists(atPath: tokenizerPath) else {
            throw TTSEngineError.tokenizerFailed("tokenizer.model 파일 없음")
        }
        return Array(text.utf8).map { Int64($0) }
    }

    // MARK: - Private: 모델 실행

    private func runTextConditioner(session: ORTSession, tokenIds: [Int64]) throws -> Data {
        var ids = tokenIds
        let tokenData = NSMutableData(bytes: &ids, length: ids.count * MemoryLayout<Int64>.size)
        let inputTensor = try ORTValue(
            tensorData: tokenData,
            elementType: .int64,
            shape: [1, NSNumber(value: tokenIds.count)]
        )

        let outputNames = try session.outputNames()
        let outputs = try session.run(
            withInputs: ["token_ids": inputTensor],
            outputNames: Set(outputNames),
            runOptions: nil
        )

        guard let output = outputs[outputNames[0]] else {
            throw TTSEngineError.generationFailed("text_conditioner 출력 없음")
        }
        return try output.tensorData() as Data
    }

    private struct FlowLmMainResult {
        let conditioning: Data
        let eosLogit: Float
        let state: [String: ORTValue]
    }

    private func runFlowLmMain(
        session: ORTSession,
        sequence: ORTValue,
        textEmbeddings: ORTValue,
        state: inout [String: ORTValue]
    ) throws -> FlowLmMainResult {
        var inputs: [String: ORTValue] = [
            "sequence": sequence,
            "text_embeddings": textEmbeddings,
        ]
        for (key, value) in state {
            inputs[key] = value
        }

        let outputNames = try session.outputNames()
        let outputs = try session.run(
            withInputs: inputs,
            outputNames: Set(outputNames),
            runOptions: nil
        )

        var conditioning: Data?
        var eosLogit: Float = -Float.infinity
        var newState: [String: ORTValue] = [:]

        for name in outputNames {
            guard let value = outputs[name] else { continue }

            if name.hasPrefix("out_state_") {
                let stateKey = name.replacingOccurrences(of: "out_", with: "")
                newState[stateKey] = value
            } else if conditioning == nil {
                conditioning = try value.tensorData() as Data
            } else {
                let eosData = try value.tensorData() as Data
                eosLogit = eosData.withUnsafeBytes { $0.load(as: Float.self) }
            }
        }

        guard let cond = conditioning else {
            throw TTSEngineError.generationFailed("conditioning 출력 없음")
        }

        return FlowLmMainResult(conditioning: cond, eosLogit: eosLogit, state: newState)
    }

    private func flowMatch(
        session: ORTSession,
        conditioning: Data,
        temperature: Float
    ) throws -> [Float] {
        let steps = Self.lsdDecodeSteps
        var x = (0..<Self.latentDim).map { _ in Float.random(in: -1...1) * sqrtf(temperature) }

        let condTensor = try createFloatTensor(
            fromData: conditioning,
            shape: [1, 1, NSNumber(value: Self.dModel)]
        )

        let outputNames = try session.outputNames()

        for j in 0..<steps {
            var sVal = Float(j) / Float(steps)
            var tVal = Float(j + 1) / Float(steps)

            let sTensor = try ORTValue(
                tensorData: NSMutableData(bytes: &sVal, length: MemoryLayout<Float>.size),
                elementType: .float,
                shape: [1, 1]
            )
            let tTensor = try ORTValue(
                tensorData: NSMutableData(bytes: &tVal, length: MemoryLayout<Float>.size),
                elementType: .float,
                shape: [1, 1]
            )
            let xTensor = try createFloatTensor(from: x, shape: [1, NSNumber(value: Self.latentDim)])

            let outputs = try session.run(
                withInputs: ["c": condTensor, "s": sTensor, "t": tTensor, "x": xTensor],
                outputNames: Set(outputNames),
                runOptions: nil
            )

            guard let flowOut = outputs[outputNames[0]] else {
                throw TTSEngineError.generationFailed("flow 출력 없음")
            }

            let flowData = try flowOut.tensorData() as Data
            let flowArray: [Float] = flowData.withUnsafeBytes {
                Array(UnsafeBufferPointer(
                    start: $0.baseAddress!.assumingMemoryBound(to: Float.self),
                    count: Self.latentDim
                ))
            }

            let dt = 1.0 / Float(steps)
            for i in 0..<Self.latentDim {
                x[i] += flowArray[i] * dt
            }
        }
        return x
    }

    private func decodeLatents(session: ORTSession, latents: [[Float]]) throws -> [Float] {
        var decoderState = try initState(session: session)
        var allSamples: [Float] = []

        var offset = 0
        while offset < latents.count {
            let end = min(offset + Self.decoderChunkSize, latents.count)
            let chunk = Array(latents[offset..<end])
            let flatData = chunk.flatMap { $0 }

            let latentTensor = try createFloatTensor(
                from: flatData,
                shape: [1, NSNumber(value: chunk.count), NSNumber(value: Self.latentDim)]
            )

            var inputs: [String: ORTValue] = ["latent": latentTensor]
            for (key, value) in decoderState {
                inputs[key] = value
            }

            let outputNames = try session.outputNames()
            let outputs = try session.run(
                withInputs: inputs,
                outputNames: Set(outputNames),
                runOptions: nil
            )

            var newState: [String: ORTValue] = [:]
            for name in outputNames {
                guard let value = outputs[name] else { continue }
                if name.hasPrefix("out_state_") {
                    let stateKey = name.replacingOccurrences(of: "out_", with: "")
                    newState[stateKey] = value
                } else {
                    let pcmData = try value.tensorData() as Data
                    let pcmSamples: [Float] = pcmData.withUnsafeBytes {
                        Array(UnsafeBufferPointer(
                            start: $0.baseAddress!.assumingMemoryBound(to: Float.self),
                            count: pcmData.count / MemoryLayout<Float>.size
                        ))
                    }
                    allSamples.append(contentsOf: pcmSamples)
                }
            }
            decoderState = newState
            offset = end
        }
        return allSamples
    }

    // MARK: - Private: State / Tensor 유틸

    private func initState(session: ORTSession) throws -> [String: ORTValue] {
        var state: [String: ORTValue] = [:]
        let inputNames = try session.inputNames()

        for name in inputNames {
            guard name.hasPrefix("state_") else { continue }

            // state 텐서는 빈(0차원) 텐서로 초기화
            // 동적 shape은 0으로 처리
            // 실제 shape/dtype은 첫 실행 시 모델이 결정
            let zeroData = NSMutableData()
            let tensor = try ORTValue(
                tensorData: zeroData,
                elementType: .float,
                shape: [0]
            )
            state[name] = tensor
        }

        return state
    }

    private func createBosLatent() -> [Float] {
        return [Float](repeating: Float.nan, count: Self.latentDim)
    }

    private func createFloatTensor(from array: [Float], shape: [NSNumber]) throws -> ORTValue {
        var data = array
        let mutableData = NSMutableData(bytes: &data, length: data.count * MemoryLayout<Float>.size)
        return try ORTValue(tensorData: mutableData, elementType: .float, shape: shape)
    }

    private func createFloatTensor(fromData data: Data, shape: [NSNumber]) throws -> ORTValue {
        let mutableData = NSMutableData(data: data)
        return try ORTValue(tensorData: mutableData, elementType: .float, shape: shape)
    }

    private func loadEmbedding(from path: String) throws -> (Data, Int) {
        guard FileManager.default.fileExists(atPath: path) else {
            throw TTSEngineError.encodingFailed("임베딩 파일 없음: \(path)")
        }
        let fileData = try Data(contentsOf: URL(fileURLWithPath: path))
        guard fileData.count >= 8 else {
            throw TTSEngineError.encodingFailed("임베딩 파일이 너무 작습니다")
        }
        let n = fileData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Int32.self) }
        let embeddingData = fileData.subdata(in: 8..<fileData.count)
        return (embeddingData, Int(n))
    }
}
