import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:neomokdeul/features/auth/auth_provider.dart';
import 'package:neomokdeul/features/auth/login_screen.dart';

/// 라우트 경로 상수
class AppRoutes {
  AppRoutes._();
  static const login = '/login';
  static const download = '/download';
  static const main = '/main';
}

/// 인증 상태 변경을 GoRouter에 알려주는 Listenable
class AuthNotifierListenable extends ChangeNotifier {
  AuthNotifierListenable(Ref ref) {
    ref.listen(authProvider, (prev, next) {
      notifyListeners();
    });
  }
}

/// go_router 설정 (Riverpod 연동)
final routerProvider = Provider<GoRouter>((ref) {
  final refreshListenable = AuthNotifierListenable(ref);

  return GoRouter(
    initialLocation: AppRoutes.login,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final isAuthenticated = ref.read(isAuthenticatedProvider);
      final currentPath = state.matchedLocation;
      final isLoginPage = currentPath == AppRoutes.login;

      if (!isAuthenticated) {
        return isLoginPage ? null : AppRoutes.login;
      }

      // TODO: 모델 다운로드 여부 확인 후 /download 또는 /main으로 분기
      if (isLoginPage) {
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
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('모델 다운로드 화면')),
        ),
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
