import 'dart:async';

import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final original = amapViewFactory;
  const channel = MethodChannel('$amapViewType/803');
  const center = AMapLatLng(22.5, 114);
  AMapCircle circle({String id = 'area', bool changed = false}) => AMapCircle(
    id: id,
    center: changed ? const AMapLatLng(22.6, 114.1) : center,
    radiusMeters: changed ? 650 : 300,
    strokeWidth: changed ? 7 : 3,
    fillColor: changed ? const Color(0x66EF6C00) : const Color(0x331565C0),
    strokeColor: changed ? const Color(0xFFD84315) : const Color(0xFF1565C0),
  );
  final updates = <Map<Object?, Object?>>[];

  void mockMap({Future<void>? firstReply}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getStatus') return 'ready';
      if (call.method == 'updateCircles') {
        updates.add(call.arguments as Map<Object?, Object?>);
        if (updates.length == 1) await firstReply;
      }
      return null;
    });
    var created = false;
    amapViewFactory = (_, callback) {
      if (!created) {
        created = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => callback(803));
      }
      return const SizedBox();
    };
  }

  tearDown(() {
    amapViewFactory = original;
    messenger.setMockMethodCallHandler(channel, null);
    updates.clear();
  });

  test('validates circle geometry and stroke', () {
    expect(() => circle(id: ''), throwsArgumentError);
    for (final radius in [0.0, -1.0, double.infinity, double.nan]) {
      expect(
        () => AMapCircle(id: 'area', center: center, radiusMeters: radius),
        throwsArgumentError,
      );
    }
    expect(
      () => AMapCircle(
        id: 'area',
        center: const AMapLatLng(0, 181),
        radiusMeters: 100,
      ),
      throwsArgumentError,
    );
    expect(
      () => AMapCircle(
        id: 'area',
        center: center,
        radiusMeters: 100,
        strokeWidth: 129,
      ),
      throwsArgumentError,
    );
  });

  testWidgets('adds, updates only the changed ID and removes it', (
    tester,
  ) async {
    mockMap();
    Future<void> show(List<AMapCircle> circles) async {
      await tester.pumpWidget(AMapView(circles: circles));
      await tester.pump();
    }

    await show([circle(), circle(id: 'other')]);
    expect(updates.single['upsert'], hasLength(2));
    await show([circle(), circle(id: 'other')]);
    expect(updates, hasLength(1));
    await show([circle(changed: true), circle(id: 'other')]);
    expect(updates.last['upsert'], [
      {
        'id': 'area',
        'latitude': 22.6,
        'longitude': 114.1,
        'radiusMeters': 650.0,
        'strokeWidth': 7.0,
        'fillColor': 0x66EF6C00.toSigned(32),
        'strokeColor': 0xFFD84315.toSigned(32),
      },
    ]);
    await show([circle(id: 'other')]);
    expect(updates.last['remove'], ['area']);
    expect(updates.last['upsert'], isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('removes an unconfirmed addition after timeout', (tester) async {
    final reply = Completer<void>();
    final errors = <String>[];
    mockMap(firstReply: reply.future);
    await tester.pumpWidget(AMapView(circles: [circle()], onError: errors.add));
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    expect(errors, ['operation_timeout']);
    await tester.pumpWidget(const AMapView());
    await tester.pump();
    expect(updates.last['remove'], ['area']);
    reply.complete();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('duplicate IDs are rejected before opening the native view', (
    tester,
  ) async {
    var opened = false;
    amapViewFactory = (_, _) {
      opened = true;
      return const SizedBox();
    };
    await tester.pumpWidget(AMapView(circles: [circle(), circle()]));
    expect(tester.takeException(), isArgumentError);
    expect(opened, false);
  });
}
