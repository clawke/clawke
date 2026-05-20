import 'package:client/l10n/app_localizations.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/widgets/nav_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('desktop nav keeps Skills Management and adds SkillHub', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [totalUnseenCountProvider.overrideWithValue(0)],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SizedBox(width: 240, child: NavRail())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('技能管理'), findsOneWidget);
    expect(find.text('SkillHub'), findsOneWidget);
  });
}
