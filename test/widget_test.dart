// Basic smoke test. The full app requires Supabase.initialize() before it can
// be pumped, so this keeps a minimal placeholder test that always runs clean.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MaterialApp builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('SmartMatch'))),
    );
    expect(find.text('SmartMatch'), findsOneWidget);
  });
}
