import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:neomokdeul/core/constants.dart';
import 'package:neomokdeul/core/failure.dart';

/// 다운로드 진행 상태
class DownloadProgress {
  const DownloadProgress({
    this.totalProgress = 0.0,
    this.currentFile = '',
    this.currentFileIndex = 0,
    this.totalFiles = 0,
    this.isComplete = false,
    this.failure,
  });

  final double totalProgress;
  final String currentFile;
  final int currentFileIndex;
  final int totalFiles;
  final bool isComplete;
  final Failure? failure;
}

/// Supabase Storage에서 ONNX 모델 다운로드 관리
class ModelDownloader {
  ModelDownloader(this._supabase);

  final SupabaseClient _supabase;

  /// 모델 저장 디렉토리 경로
  static Future<String> getModelDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/${AppConstants.modelDirName}');
    if (!modelDir.existsSync()) {
      modelDir.createSync(recursive: true);
    }
    return modelDir.path;
  }

  /// 모델 다운로드 완료 여부 (Hive 플래그)
  static Future<bool> isModelReady() async {
    final box = await Hive.openBox(AppConstants.hiveModelBox);
    return box.get(AppConstants.hiveModelReadyKey, defaultValue: false) as bool;
  }

  /// 전체 모델 다운로드 (이미 있는 파일은 스킵)
  Stream<DownloadProgress> downloadAll() async* {
    final modelDir = await getModelDirectory();
    const files = AppConstants.modelFiles;
    final totalSize = AppConstants.totalModelSize;
    var downloadedBytes = 0;

    for (var i = 0; i < files.length; i++) {
      final fileName = files[i];
      final filePath = '$modelDir/$fileName';
      final estimatedSize = AppConstants.modelFileSizes[fileName] ?? 0;

      yield DownloadProgress(
        totalProgress: downloadedBytes / totalSize,
        currentFile: fileName,
        currentFileIndex: i + 1,
        totalFiles: files.length,
      );

      // 이미 다운로드된 파일은 스킵
      final file = File(filePath);
      if (file.existsSync() && file.lengthSync() > 0) {
        downloadedBytes += estimatedSize;
        continue;
      }

      try {
        final parts = AppConstants.splitModelFiles[fileName];
        if (parts != null) {
          // 분할 파일: 파트별 다운로드 후 병합
          final sink = file.openWrite();
          for (final part in parts) {
            final bytes = await _supabase.storage
                .from(AppConstants.modelBucket)
                .download(part);
            sink.add(bytes);
          }
          await sink.close();
        } else {
          // 단일 파일 다운로드
          final bytes = await _supabase.storage
              .from(AppConstants.modelBucket)
              .download(fileName);
          await file.writeAsBytes(bytes);
        }
        downloadedBytes += estimatedSize;
      } catch (e) {
        yield DownloadProgress(
          totalProgress: downloadedBytes / totalSize,
          currentFile: fileName,
          currentFileIndex: i + 1,
          totalFiles: files.length,
          failure: StorageFailure('$fileName 다운로드 실패: $e'),
        );
        return;
      }
    }

    // Hive에 완료 플래그 저장
    final box = await Hive.openBox(AppConstants.hiveModelBox);
    await box.put(AppConstants.hiveModelReadyKey, true);

    yield DownloadProgress(
      totalProgress: 1.0,
      currentFile: '',
      currentFileIndex: files.length,
      totalFiles: files.length,
      isComplete: true,
    );
  }
}

/// 모델 다운로드 Provider
class ModelDownloadNotifier extends AsyncNotifier<DownloadProgress> {
  StreamSubscription<DownloadProgress>? _subscription;

  @override
  Future<DownloadProgress> build() async {
    ref.onDispose(() => _subscription?.cancel());
    return const DownloadProgress();
  }

  Future<void> startDownload() async {
    state = const AsyncData(DownloadProgress());

    final supabase = Supabase.instance.client;
    final downloader = ModelDownloader(supabase);

    _subscription = downloader.downloadAll().listen(
      (progress) {
        state = AsyncData(progress);
        if (progress.isComplete) {
          ref.invalidate(isModelReadyProvider);
        }
      },
      onError: (e) {
        state = AsyncData(DownloadProgress(
          failure: StorageFailure(e.toString()),
        ));
      },
    );
  }
}

final modelDownloadProvider =
    AsyncNotifierProvider<ModelDownloadNotifier, DownloadProgress>(
  ModelDownloadNotifier.new,
);

/// 모델 다운로드 완료 여부 Provider
final isModelReadyProvider = FutureProvider<bool>((ref) async {
  return ModelDownloader.isModelReady();
});
