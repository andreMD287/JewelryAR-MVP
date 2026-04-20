import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry_ar_mvp/main.dart';

void main() {
  testWidgets('HomeScreen muestra los tres botones de prueba', (WidgetTester tester) async {
    await tester.pumpWidget(const JewelryARApp());

    expect(find.text('Test AR Manos (Pulseras)'), findsOneWidget);
    expect(find.text('Test AR Rostro (Aretes)'), findsOneWidget);
    expect(find.text('Test Modelo 3D + AR'), findsOneWidget);
  });
}
