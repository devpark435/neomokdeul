import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neomokdeul/core/model_downloader.dart';

class ModelDownloadScreen extends ConsumerStatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  ConsumerState<ModelDownloadScreen> createState() =>
      _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends ConsumerState<ModelDownloadScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(modelDownloadProvider.notifier).startDownload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final downloadState = ref.watch(modelDownloadProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: downloadState.when(
              data: (progress) => _buildContent(context, progress),
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => _buildError(context, e.toString()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, DownloadProgress progress) {
    if (progress.failure != null) {
      return _buildError(context, progress.failure!.message);
    }

    final percent = (progress.totalProgress * 100).toInt();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: CircularProgressIndicator(
                  value: progress.totalProgress,
                  strokeWidth: 6,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
              Text(
                '$percent%',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'AI 모델을 다운로드하고 있어요',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          '약 200MB, Wi-Fi 환경을 권장합니다',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
        const SizedBox(height: 24),
        if (progress.currentFile.isNotEmpty)
          Text(
            '${progress.currentFileIndex}/${progress.totalFiles}  ${progress.currentFile}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
          ),
      ],
    );
  }

  Widget _buildError(BuildContext context, String message) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.error_outline,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 16),
        Text(
          '다운로드 실패',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            ref.read(modelDownloadProvider.notifier).startDownload();
          },
          child: const Text('다시 시도'),
        ),
      ],
    );
  }
}
