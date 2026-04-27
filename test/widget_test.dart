import 'package:flutter_test/flutter_test.dart';
import 'package:balance_wheel_android/main.dart';

void main() {
  testWidgets('App renders open-video button', (WidgetTester tester) async {
    await tester.pumpWidget(const BalanceWheelApp());
    expect(find.text('Open Video'), findsOneWidget);
  });
}
