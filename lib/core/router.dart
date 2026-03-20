import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:neomokdeul/core/model_downloader.dart';
import 'package:neomokdeul/features/auth/auth_provider.dart';
import 'package:neomokdeul/features/auth/login_screen.dart';
import 'package:neomokdeul/features/download/model_download_screen.dart';

/// 라우트 경로 상수
class AppRoutes {
  AppRoutes._();
  static const login = '/login';
  static const download = '/download';
  static const main = '/main';
}

/// 인증/모델 상태 변경을 GoRouter에 알려주는 Listenable
class _RouterRefreshListenable extends ChangeNotifier {
  _RouterRefreshListenable(Ref ref) {
    ref.listen(authProvider, (prev, next) => notifyListeners());
    ref.listen(isModelReadyProvider, (prev, next) => notifyListeners());
  }
}

/// go_router 설정 (Riverpod 연동)
final routerProvider = Provider<GoRouter>((ref) {
  final refreshListenable = _RouterRefreshListenable(ref);

  return GoRouter(
    initialLocation: AppRoutes.login,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final isAuthenticated = ref.read(isAuthenticatedProvider);
      final isModelReady = ref.read(isModelReadyProvider).valueOrNull ?? false;
      final currentPath = state.matchedLocation;

      if (!isAuthenticated) {
        return currentPath == AppRoutes.login ? null : AppRoutes.login;
      }

      // 로그인 완료 + 모델 미다운로드 → /download
      if (!isModelReady) {
        return currentPath == AppRoutes.download ? null : AppRoutes.download;
      }

      // 로그인 + 모델 준비 완료인데 login/download 페이지 → /main
      if (currentPath == AppRoutes.login ||
          currentPath == AppRoutes.download) {
        return AppRoutes.main;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.download,
        builder: (context, state) => const ModelDownloadScreen(),
      ),
      GoRoute(
        path: AppRoutes.main,
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('메인 화면')),
        ),
      ),
    ],
  );
});
