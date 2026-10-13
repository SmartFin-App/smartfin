import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smart_fin/constants/app_theme.dart';
import 'package:smart_fin/features/scanner/presentation/widgets/slip_detection_sheet.dart';
import 'package:smart_fin/features/scanner/presentation/widgets/slip_folders_sheet.dart';
import 'package:smart_fin/features/scanner/services/gallery_watcher_service.dart';

Widget _host(Widget sheet) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: Align(alignment: Alignment.bottomCenter, child: sheet),
  ),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('slip detection sheet lays out its preview and actions', (
    tester,
  ) async {
    final slip = DetectedSlip(
      asset: AssetEntity(id: 'a1', typeInt: 1, width: 10, height: 10),
      // Missing on purpose: the preview falls back to an icon.
      file: File('/does/not/exist.png'),
      albumName: 'K PLUS',
      createDateTime: DateTime(2026, 9, 21, 9, 30),
    );
    await tester.pumpWidget(_host(SlipDetectionSheet(slip: slip)));
    await tester.pumpAndSettle();

    expect(find.text('New payment slip found'), findsOneWidget);
    expect(find.text('Scan and add'), findsOneWidget);
    expect(find.text('Not this one'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a queued earlier slip shows its place and a way to stop', (
    tester,
  ) async {
    final slip = DetectedSlip(
      asset: AssetEntity(id: 'a2', typeInt: 1, width: 10, height: 10),
      file: File('/does/not/exist.png'),
      albumName: 'K PLUS',
      createDateTime: DateTime(2026, 10, 3, 9, 30),
    );
    await tester.pumpWidget(
      _host(
        SlipDetectionSheet(
          slip: slip,
          progress: const SlipQueueProgress(position: 3, total: 12),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Earlier slip 3 of 12'), findsOneWidget);
    expect(find.text('Skip this one'), findsOneWidget);
    expect(find.text('Stop for now'), findsOneWidget);
    expect(find.text('Not this one'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slip folders sheet lays out while it loads', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_host(const SlipFoldersSheet()));
    // One frame, not pumpAndSettle: the photo plugin never answers in a test,
    // so the loading spinner would keep it from settling.
    await tester.pump();

    expect(find.text('Slip folders'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
