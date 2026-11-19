import 'dart:async';

import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('$amapViewType/815');
  const points = [
    AMapLatLng(22.54, 114.05),
    AMapLatLng(22.55, 114.06),
    AMapLatLng(22.53, 114.07),
  ];
  final original = amapViewFactory;
  final batches = <Map>[];

  void mock({Completer<void>? first}) {
    var created = false;
    amapViewFactory = (_, onCreated) {
      if (!created) {
        created = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => onCreated(815));
      }
      return const SizedBox();
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getStatus') return 'loaded';
      if (call.method == 'updatePolygons') {
        batches.add(call.arguments as Map);
        if (batches.length == 1 && first != null) await first.future;
      }
      return null;
    });
  }

  tearDown(() {
    batches.clear();
    amapViewFactory = original;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'requires three distinct finite GCJ-02 vertices and snapshots the ring',
    () {
      final input = [...points, points.first];
      final shape = AMapPolygon(id: 'fence', points: input);
      input.clear();
      expect(shape.points, [...points, points.first]);
      expect(shape.points.clear, throwsUnsupportedError);
      for (final invalid in [
        points.take(2),
        [points[0], points[1], points[0]],
        [...points, const AMapLatLng(double.nan, 114)],
        [...points, const AMapLatLng(22, 181)],
      ]) {
        expect(
          () => AMapPolygon(id: 'fence', points: invalid),
          throwsArgumentError,
        );
      }
      expect(() => AMapPolygon(id: '', points: points), throwsArgumentError);
      for (final width in [0.0, 129.0, double.infinity]) {
        expect(
          () => AMapPolygon(id: 'fence', points: points, strokeWidth: width),
          throwsArgumentError,
        );
      }
    },
  );

  testWidgets('adds, changes geometry and style for one ID and removes it', (
    tester,
  ) async {
    mock();
    final other = AMapPolygon(id: 'other', points: points);
    Future<void> show(List<AMapPolygon> shapes) async {
      await tester.pumpWidget(AMapView(polygons: shapes));
      await tester.pump();
    }

    await show([AMapPolygon(id: 'fence', points: points), other]);
    expect((batches.single['upsert'] as List).map((p) => p['id']), [
      'fence',
      'other',
    ]);
    await show([
      AMapPolygon(
        id: 'fence',
        points: points.map((p) => AMapLatLng(p.latitude, p.longitude)),
      ),
      other,
    ]);
    expect(batches, hasLength(1));
    final moved = [points[0], const AMapLatLng(22.56, 114.06), points[2]];
    await show([AMapPolygon(id: 'fence', points: moved), other]);
    expect(batches, hasLength(2));
    await show([
      AMapPolygon(
        id: 'fence',
        points: moved,
        fillColor: const Color(0x66223344),
        strokeColor: const Color(0xFF123456),
        strokeWidth: 7,
      ),
      other,
    ]);
    expect(batches, hasLength(3));
    expect(batches.last, {
      'upsert': [
        {
          'id': 'fence',
          'points': [
            [22.54, 114.05],
            [22.56, 114.06],
            [22.53, 114.07],
          ],
          'fillColor': 0x66223344,
          'strokeColor': 0xFF123456.toSigned(32),
          'strokeWidth': 7.0,
        },
      ],
      'remove': [],
    });
    await show([other]);
    expect(batches.last, {
      'upsert': [],
      'remove': ['fence'],
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reconciles removal after an unacknowledged native update', (
    tester,
  ) async {
    final pending = Completer<void>();
    final errors = <String>[];
    mock(first: pending);
    await tester.pumpWidget(
      AMapView(
        polygons: [AMapPolygon(id: 'fence', points: points)],
        onError: errors.add,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    expect(errors, ['operation_timeout']);
    await tester.pumpWidget(const AMapView());
    await tester.pump();
    expect(batches.last, {
      'upsert': [],
      'remove': ['fence'],
    });
    pending.complete();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rejects duplicate polygon IDs before native creation', (
    tester,
  ) async {
    var opened = false;
    amapViewFactory = (_, _) {
      opened = true;
      return const SizedBox();
    };
    final shape = AMapPolygon(id: 'fence', points: points);
    await tester.pumpWidget(AMapView(polygons: [shape, shape]));
    expect(tester.takeException(), isArgumentError);
    expect(opened, isFalse);
  });
}
