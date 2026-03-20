/// 앱 전역 상수
class AppConstants {
  AppConstants._();

  // 모델 관련
  static const String modelBucket = 'models';
  static const String modelFileName = 'pocket_tts_int8.onnx';
  static const int modelVersion = 1;

  // 음성 녹음
  static const int maxRecordingDurationSec = 20;

  // Platform Channel
  static const String ttsChannelName = 'com.devpark.neomokdeul/tts';
}
