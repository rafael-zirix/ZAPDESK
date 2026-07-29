import 'package:flutter_test/flutter_test.dart';
import 'package:zapdesk_app/main.dart';

void main() {
  testWidgets('App sobe e mostra a tela de login', (tester) async {
    await tester.pumpWidget(const ZapdeskApp());
    await tester.pump(); // deixa o bootstrap resolver para loggedOut
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Zapdesk'), findsWidgets);
  });
}
