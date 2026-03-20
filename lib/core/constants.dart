/// 앱 전역 상수
class AppConstants {
  AppConstants._();

  // 모델 관련
  static const String modelBucket = 'models';
  static const int modelVersion = 1;
  static const String modelDirName = 'pocket_tts_v$modelVersion';
  static const String hiveModelBox = 'model_status';
  static const String hiveModelReadyKey = 'model_ready_v$modelVersion';

  static const List<String> modelFiles = [
    'flow_lm_main_int8.onnx',
    'flow_lm_flow_int8.onnx',
    'mimi_decoder_int8.onnx',
    'mimi_encoder.onnx',
    'text_conditioner.onnx',
    'tokenizer.model',
  ];

  // 50MB 제한으로 분할 업로드된 파일 목록
  // key: 최종 파일명, value: Storage에 저장된 파트 파일명 리스트
  static const Map<String, List<String>> splitModelFiles = {
    'mimi_encoder.onnx': [
      'mimi_encoder.onnx.part_aa',
      'mimi_encoder.onnx.part_ab',
    ],
    'flow_lm_main_int8.onnx': [
      'flow_lm_main_int8.onnx.part_aa',
      'flow_lm_main_int8.onnx.part_ab',
    ],
  };

  // 대략적인 파일 크기 (bytes, 진행률 계산용)
  static const Map<String, int> modelFileSizes = {
    'flow_lm_main_int8.onnx': 76341627,
    'flow_lm_flow_int8.onnx': 9962530,
    'mimi_decoder_int8.onnx': 22684077,
    'mimi_encoder.onnx': 73165554,
    'text_conditioner.onnx': 16388363,
    'tokenizer.model': 59339,
  };

  static int get totalModelSize =>
      modelFileSizes.values.fold(0, (a, b) => a + b);

  // 음성 녹음
  static const int maxRecordingDurationSec = 20;

  // Platform Channel
  static const String ttsChannelName = 'com.devpark.neomokdeul/tts';
  static const String ttsProgressChannelName = 'com.devpark.neomokdeul/tts_progress';
}
