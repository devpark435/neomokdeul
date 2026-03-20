import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neomokdeul/features/auth/auth_provider.dart';

/// 소셜 로그인 화면
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 3),

                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.record_voice_over_rounded,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  '너목들',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),

                Text(
                  '너의 목소리가 들려',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),

                const Spacer(flex: 2),

                if (authState.valueOrNull is AuthError) ...[
                  Text(
                    (authState.valueOrNull as AuthError).failure.message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: authState.isLoading
                        ? null
                        : () => ref.read(authProvider.notifier).signInWithGoogle(),
                    icon: const Icon(Icons.g_mobiledata, size: 28),
                    label: const Text('Google로 시작하기'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                if (Platform.isIOS) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: authState.isLoading
                          ? null
                          : () => ref.read(authProvider.notifier).signInWithApple(),
                      icon: const Icon(Icons.apple, size: 24),
                      label: const Text('Apple로 시작하기'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                if (authState.isLoading) ...[
                  const SizedBox(height: 8),
                  const CircularProgressIndicator(),
                ],

                const Spacer(),

                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    '계속하면 이용약관에 동의하는 것으로 간주합니다',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
