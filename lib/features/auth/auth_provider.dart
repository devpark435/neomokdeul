import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:neomokdeul/core/failure.dart';

/// 현재 인증 상태
sealed class AuthState {
  const AuthState();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);
  final User user;
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthError extends AuthState {
  const AuthError(this.failure);
  final Failure failure;
}

/// 인증 상태 관리 Provider
class AuthNotifier extends AsyncNotifier<AuthState> {
  late final SupabaseClient _supabase;

  @override
  Future<AuthState> build() async {
    _supabase = Supabase.instance.client;

    // authStateChanges 구독
    final sub = _supabase.auth.onAuthStateChange.listen((data) {
      dev.log('[Auth] onAuthStateChange: event=${data.event}, '
          'hasSession=${data.session != null}');
      final session = data.session;
      if (session != null) {
        state = AsyncData(AuthAuthenticated(session.user));
      } else if (data.event == AuthChangeEvent.signedOut) {
        state = const AsyncData(AuthUnauthenticated());
      }
    });

    ref.onDispose(() => sub.cancel());

    // 현재 세션 확인
    final currentSession = _supabase.auth.currentSession;
    dev.log('[Auth] 초기 세션: ${currentSession != null}');
    if (currentSession != null) {
      return AuthAuthenticated(currentSession.user);
    }
    return const AuthUnauthenticated();
  }

  /// Google 네이티브 로그인
  Future<void> signInWithGoogle() async {
    try {
      dev.log('[Auth] Google 네이티브 로그인 시작');

      final webClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID']!;
      final iosClientId = dotenv.env['GOOGLE_IOS_CLIENT_ID']!;

      final googleSignIn = GoogleSignIn(
        clientId: Platform.isIOS ? iosClientId : null,
        serverClientId: webClientId,
      );

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        dev.log('[Auth] Google 로그인 취소됨');
        return;
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null || accessToken == null) {
        throw const AuthFailure('Google 토큰을 가져올 수 없습니다.');
      }

      dev.log('[Auth] Google 토큰 획득, Supabase 인증 시작');

      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      dev.log('[Auth] Supabase 인증 완료');
    } catch (e) {
      dev.log('[Auth] Google 로그인 에러: $e');
      state = AsyncData(AuthError(AuthFailure(e.toString())));
    }
  }

  /// Apple 소셜 로그인 (iOS 전용) — 추후 구현
  Future<void> signInWithApple() async {
    if (!Platform.isIOS) return;
    // TODO: sign_in_with_apple 패키지로 구현 예정
    dev.log('[Auth] Apple 로그인은 아직 미구현');
  }

  /// 로그아웃
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
      state = const AsyncData(AuthUnauthenticated());
    } catch (e) {
      state = AsyncData(AuthError(AuthFailure(e.toString())));
    }
  }
}

/// 인증 상태 Provider
final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

/// 현재 로그인 여부 (라우터 가드용)
final isAuthenticatedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authProvider);
  return authState.valueOrNull is AuthAuthenticated;
});
