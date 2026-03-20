import Flutter
import UIKit

/// Flutter Platform Channel 플러그인
class PocketTTSPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private let engine = PocketTTSEngine()
    private var eventSink: FlutterEventSink?
    private let backgroundQueue = DispatchQueue(label: "com.devpark.neomokdeul.tts", qos: .userInitiated)

    // MARK: - FlutterPlugin 등록

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.devpark.neomokdeul/tts",
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: "com.devpark.neomokdeul/tts_progress",
            binaryMessenger: registrar.messenger()
        )

        let instance = PocketTTSPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - MethodChannel 핸들러

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initModel":
            handleInitModel(call: call, result: result)
        case "isModelLoaded":
            result(engine.isLoaded)
        case "encodeVoice":
            handleEncodeVoice(call: call, result: result)
        case "generateSpeech":
            handleGenerateSpeech(call: call, result: result)
        case "dispose":
            engine.dispose()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - EventChannel (진행률)

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        engine.onProgress = { [weak self] progress in
            DispatchQueue.main.async {
                self?.eventSink?(progress)
            }
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        engine.onProgress = nil
        return nil
    }

    // MARK: - 메서드 구현

    private func handleInitModel(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let modelDir = args["modelDir"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "modelDir가 필요합니다.", details: nil))
            return
        }

        backgroundQueue.async { [weak self] in
            do {
                try self?.engine.loadModels(directory: modelDir)
                DispatchQueue.main.async { result(true) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "MODEL_LOAD_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }

    private func handleEncodeVoice(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let audioPath = args["audioPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "audioPath가 필요합니다.", details: nil))
            return
        }

        backgroundQueue.async { [weak self] in
            do {
                let embeddingPath = try self?.engine.encodeVoice(audioPath: audioPath)
                DispatchQueue.main.async { result(embeddingPath) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "ENCODE_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }

    private func handleGenerateSpeech(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let text = args["text"] as? String,
              let embeddingPath = args["embeddingPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "text, embeddingPath가 필요합니다.", details: nil))
            return
        }

        let temperature = Float(args["temperature"] as? Double ?? 0.7)

        backgroundQueue.async { [weak self] in
            do {
                let wavPath = try self?.engine.generateSpeech(
                    text: text,
                    embeddingPath: embeddingPath,
                    temperature: temperature
                )
                DispatchQueue.main.async { result(wavPath) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "GENERATE_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }
}
