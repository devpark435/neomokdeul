/// 에러 타입 통일을 위한 sealed class
sealed class Failure {
  const Failure(this.message);
  final String message;
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = '네트워크 오류가 발생했습니다.']);
}

class StorageFailure extends Failure {
  const StorageFailure([super.message = '저장소 오류가 발생했습니다.']);
}

class AuthFailure extends Failure {
  const AuthFailure([super.message = '인증 오류가 발생했습니다.']);
}

class TtsFailure extends Failure {
  const TtsFailure([super.message = 'TTS 처리 중 오류가 발생했습니다.']);
}

class ModelFailure extends Failure {
  const ModelFailure([super.message = '모델 로드 중 오류가 발생했습니다.']);
}
