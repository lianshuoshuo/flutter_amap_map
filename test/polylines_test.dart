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
  const channel = MethodChannel('$amapViewType/802');
  const points = [AMapLatLng(22.5, 114), AMapLatLng(22.6, 114.1)];
  AMapPolyline line({String id = 'route', double width = 6}) =>
      AMapPolyline(id: id, points: points, width: width);
  final updates = <Map<Object?, Object?>>[];

  void mockMap({Future<void>? firstReply}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getStatus') return 'ready';
      if (call.method == 'updatePolylines') {
        updates.add(call.arguments as Map<Object?, Object?>);
        if (updates.length == 1) await firstReply;
      }
      return null;
    });
    var created = false;
    amapViewFactory = (_, callback) {
      if (!created) {
        created = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => callback(802));
      }
      return const SizedBox();
    };
  }

  tearDown(() {
    amapViewFactory = original;
    messenger.setMockMethodCallHandler(channel, null);
    updates.clear();
  });

  test('validates line geometry and takes an immutable snapshot', () {
    final input = points.toList();
    final value = AMapPolyline(id: 'route', points: input);
    input.clear();
    expect(value.points, points);
    expect(() => value.points.clear(), throwsUnsupportedError);
    expect(() => line(id: ''), throwsArgumentError);
    expect(() => line(width: double.nan), throwsArgumentError);
    expect(
      () => AMapPolyline(id: 'route', points: points.take(1)),
      throwsArgumentError,
    );
    expect(
      () => AMapPolyline(
        id: 'route',
        points: [points.first, const AMapLatLng(0, 181)],
      ),
      throwsArgumentError,
    );
  });

  testWidgets('adds, updates only the changed ID and removes it', (
    tester,
  ) async {
    mockMap();
    Future<void> show(List<AMapPolyline> lines) async {
      await tester.pumpWidget(AMapView(polylines: lines));
      await tester.pump();
    }

    await show([line(), line(id: 'other')]);
    expect(updates.single['upsert'], hasLength(2));
    await show([line(), line(id: 'other')]);
    expect(updates, hasLength(1));
    await show([line(width: 9), line(id: 'other')]);
    expect(updates.last['upsert'], [
      {
        'id': 'route',
        'points': [
          [22.5, 114.0],
          [22.6, 114.1],
        ],
        'width': 9.0,
        'color': 0xFF1565C0.toSigned(32),
      },
    ]);
    await show([line(id: 'other')]);
    expect(updates.last['remove'], ['route']);
    expect(updates.last['upsert'], isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('removes an unconfirmed addition after timeout', (tester) async {
    final reply = Completer<void>();
    final errors = <String>[];
    mockMap(firstReply: reply.future);
    await tester.pumpWidget(AMapView(polylines: [line()], onError: errors.add));
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    expect(errors, ['operation_timeout']);
    await tester.pumpWidget(const AMapView());
    await tester.pump();
    expect(updates.last['remove'], ['route']);
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
    await tester.pumpWidget(AMapView(polylines: [line(), line()]));
    expect(tester.takeException(), isArgumentError);
    expect(opened, false);
  });
}
