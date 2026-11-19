import 'dart:convert';

import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:amap_flutter_bridge_example/pet_label_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('positions the Flutter label above the projected marker', (
    tester,
  ) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQAAAABJRU5ErkJggg==',
    );
    final messenger = tester.binding.defaultBinaryMessenger;
    const channel = MethodChannel('$amapViewType/808');
    final original = amapViewFactory;
    var registered = false;
    amapViewFactory = (_, created) {
      if (!registered) {
        registered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => created(808));
      }
      return const SizedBox.expand();
    };
    addTearDown(() {
      amapViewFactory = original;
      messenger.setMockMethodCallHandler(channel, null);
    });
    var offset = const Offset(210, 240);
    final requests = <Object?>[];
    final moves = <Map<Object?, Object?>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getStatus') return 'loaded';
      if (call.method == 'moveCamera') {
        moves.add(call.arguments as Map<Object?, Object?>);
      }
      if (call.method == 'projectToScreen') {
        requests.add(call.arguments);
        return {'x': offset.dx, 'y': offset.dy};
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(home: PetLabelDemo(markerPng: png)));
    await tester.pumpAndSettle();

    final label = find.text('演示宠物');
    final origin = tester.getTopLeft(find.byType(AMapView));
    expect(tester.getCenter(label), origin + const Offset(210, 175));

    final size = tester.getSize(find.byType(AMapView));
    await tester.tap(find.text('回到雷达圈'));
    await tester.pumpAndSettle();
    expect(moves.single, {
      'latitude': 22.54365,
      'longitude': 114.0585,
      'zoom': 16.0,
      'animated': true,
      'targetScreenPoint': {'x': size.width * .40, 'y': size.height * .32},
    });
    offset = const Offset(300, 245);
    await tester.tap(find.text('地图居中'));
    await tester.pumpAndSettle();
    expect(tester.getCenter(label), origin + const Offset(300, 180));
    expect(moves.last, isNot(contains('targetScreenPoint')));

    final view = tester.widget<AMapView>(find.byType(AMapView));
    final camera = AMapCameraEvent(
      AMapCameraPosition(latitude: 22.5431, longitude: 114.0579, zoom: 17),
    );
    offset = const Offset(290, 260);
    view.onCameraMove!(camera);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.getCenter(label), origin + const Offset(290, 195));

    offset = const Offset(-20, 260);
    view.onCameraIdle!(camera);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(label, findsNothing);

    addTearDown(tester.view.resetPhysicalSize);
    tester.view.physicalSize =
        const Size(720, 440) * tester.view.devicePixelRatio;
    await tester.pump();
    await tester.pump();
    expect(label, findsNothing);
    // The native snapshot is valid only after its surface catches up.
    offset = const Offset(260, 240);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(label, findsOneWidget);
    expect(
      requests,
      everyElement({'latitude': 22.54365, 'longitude': 114.0585}),
    );
  });
}
