import 'package:flutter_test/flutter_test.dart';
import 'package:neomokdeul/app.dart';

void main() {
  testWidgets('앱 빌드 스모크 테스트', (WidgetTester tester) async {
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();
  });
}
