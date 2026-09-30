// ContactActions: the shared phone/WhatsApp/email/website button row used by
// the Office/Head Office dialog (and, separately, a vendor's own contact
// details). Confirms the new email/website buttons appear only when
// configured, alongside the pre-existing phone/WhatsApp buttons.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/ui/responsive_header.dart';

void main() {
  testWidgets('shows only the buttons for the contact methods that are configured', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ContactActions(phone: '9876500001'))),
    );
    expect(find.widgetWithText(OutlinedButton, 'Call'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'WhatsApp'), findsOneWidget); // WhatsApp falls back to phone
    expect(find.widgetWithText(OutlinedButton, 'Email'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Website'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows email and website buttons when the business configures them', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ContactActions(
            phone: '9876500001',
            email: 'info@locamarket.in',
            website: 'https://locamarket.in',
          ),
        ),
      ),
    );
    expect(find.widgetWithText(OutlinedButton, 'Email'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Website'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no contact methods configured at all, nothing renders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ContactActions(phone: ''))),
    );
    expect(find.byType(OutlinedButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
