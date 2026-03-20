import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neomokdeul/core/constants.dart';
import 'package:neomokdeul/core/failure.dart';

/// TTS 엔진 인터페이스
abstract class TtsEngine {
  Future<bool> initModel(String modelDir);
  Future<bool> isModelLoaded();

  /// WAV 경로 → embedding 파일 경로 반환
  Future<String> encodeVoice(String audioPath);

  /// 텍스트 + 임베딩 → 생성된 WAV 경로 반환
  Future<String> generateSpeech({
    required String text,
    required String embeddingPath,
    double temperature = 0.7,
  });

  Stream<double> get progressStream;
  Future<void> dispose();
}

/// MethodChannel 기반 TTS 엔진 구현체
class PlatformTtsEngine implements TtsEngine {
  PlatformTtsEngine()
      : _method = const MethodChannel(AppConstants.ttsChannelName),
        _event = const EventChannel(AppConstants.ttsProgressChannelName);

  final MethodChannel _method;
  final EventChannel _event;
  Stream<double>? _progressStreamCache;

  @override
  Future<bool> initModel(String modelDir) async {
    try {
      final result = await _method.invokeMethod<bool>(
        'initModel',
        {'modelDir': modelDir},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      throw ModelFailure(e.message ?? '모델 초기화 실패');
    }
  }

  @override
  Future<bool> isModelLoaded() async {
    try {
      final result = await _method.invokeMethod<bool>('isModelLoaded');
      return result ?? false;
    } on PlatformException catch (e) {
      throw ModelFailure(e.message ?? '모델 상태 확인 실패');
    }
  }

  @override
  Future<String> encodeVoice(String audioPath) async {
    try {
      final result = await _method.invokeMethod<String>(
        'encodeVoice',
        {'audioPath': audioPath},
      );
      if (result == null) throw const TtsFailure('임베딩 결과가 없습니다.');
      return result;
    } on PlatformException catch (e) {
      throw TtsFailure(e.message ?? '음성 인코딩 실패');
    }
  }

  @override
  Future<String> generateSpeech({
    required String text,
    required String embeddingPath,
    double temperature = 0.7,
  }) async {
    try {
      final result = await _method.invokeMethod<String>(
        'generateSpeech',
        {
          'text': text,
          'embeddingPath': embeddingPath,
          'temperature': temperature,
        },
      );
      if (result == null) throw const TtsFailure('음성 생성 결과가 없습니다.');
      return result;
    } on PlatformException catch (e) {
      throw TtsFailure(e.message ?? '음성 생성 실패');
    }
  }

  @override
  Stream<double> get progressStream {
    _progressStreamCache ??= _event
        .receiveBroadcastStream()
        .map((event) => (event as num).toDouble());
    return _progressStreamCache!;
  }

  @override
  Future<void> dispose() async {
    try {
      await _method.invokeMethod<void>('dispose');
    } on PlatformException {
      // 해제 실패는 무시
    }
  }
}

/// 모델 로드 상태
enum ModelStatus { initial, loading, loaded, error }

class ModelStatusState {
  const ModelStatusState({
    this.status = ModelStatus.initial,
    this.failure,
  });

  final ModelStatus status;
  final Failure? failure;
}

/// TTS 엔진 Provider
final ttsEngineProvider = Provider<TtsEngine>((ref) {
  final engine = PlatformTtsEngine();
  ref.onDispose(() => engine.dispose());
  return engine;
});

/// 모델 로드 상태 Provider
class ModelStatusNotifier extends Notifier<ModelStatusState> {
  @override
  ModelStatusState build() => const ModelStatusState();

  Future<void> loadModel(String modelDir) async {
    state = const ModelStatusState(status: ModelStatus.loading);
    try {
      final engine = ref.read(ttsEngineProvider);
      final success = await engine.initModel(modelDir);
      state = ModelStatusState(
        status: success ? ModelStatus.loaded : ModelStatus.error,
        failure: success ? null : const ModelFailure(),
      );
    } on Failure catch (e) {
      state = ModelStatusState(status: ModelStatus.error, failure: e);
    }
  }
}

final modelStatusProvider =
    NotifierProvider<ModelStatusNotifier, ModelStatusState>(
  ModelStatusNotifier.new,
);
