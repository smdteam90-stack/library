import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:content_library/main.dart';

void main() {
  testWidgets('App launches and shows the empty state', (WidgetTester tester) async {
    await tester.pumpWidget(const ContentLibraryApp());
    await tester.pumpAndSettle();

    expect(find.text('کتابخانه من'), findsOneWidget);
    expect(find.text('هنوز لینکی ذخیره نشده است.'), findsOneWidget);
  });
}
