import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('$amapViewType/804');
  final original = amapViewFactory;
  tearDown(() {
    amapViewFactory = original;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('bounds include every vertex regardless of input order', () {
    final bounds = AMapBounds.fromPoints(const [
      AMapLatLng(22.6, 114.05),
      AMapLatLng(22.5, 114.08),
      AMapLatLng(22.9, 114.01),
    ]);
    expect(bounds.southWest.latitude, 22.5);
    expect(bounds.southWest.longitude, 114.01);
    expect(bounds.northEast.latitude, 22.9);
    expect(bounds.northEast.longitude, 114.08);
  });

  test('circle bounds use meters and latitude-adjusted longitude', () {
    final bounds = AMapBounds.fromCircle(
      AMapCircle(
        id: 'fence',
        center: const AMapLatLng(60, 110),
        radiusMeters: 1000,
      ),
    );
    expect(bounds.northEast.latitude - 60, closeTo(.0089932, .0000001));
    expect(bounds.northEast.longitude - 110, closeTo(.0179864, .0000001));
    expect(60 - bounds.southWest.latitude, closeTo(.0089932, .0000001));
    expect(110 - bounds.southWest.longitude, closeTo(.0179864, .0000001));
  });

  test('rejects empty, non-finite, polar and wrapped ranges', () {
    for (final points in <List<AMapLatLng>>[
      [],
      [const AMapLatLng(0, 100), const AMapLatLng(double.nan, 100)],
      [const AMapLatLng(86, 110)],
      [const AMapLatLng(15, 179), const AMapLatLng(16, -179)],
    ]) {
      expect(() => AMapBounds.fromPoints(points), throwsArgumentError);
    }
    expect(
      () => AMapBounds.fromCircle(
        AMapCircle(
          id: 'wrapped',
          center: const AMapLatLng(10, 179.999),
          radiusMeters: 2000,
        ),
      ),
      throwsArgumentError,
    );
  });

  testWidgets(
    'sends four logical insets, propagates native errors and guards disposal',
    (tester) async {
      late AMapController controller;
      final calls = <Map<Object?, Object?>>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getStatus') return 'ready';
        if (call.method == 'fitBounds') {
          final args = call.arguments as Map<Object?, Object?>;
          calls.add(args);
          if (args['bottom'] == 10000) {
            throw PlatformException(code: 'invalid_argument');
          }
        }
        return null;
      });
      amapViewFactory = (_, created) {
        WidgetsBinding.instance.addPostFrameCallback((_) => created(804));
        return const SizedBox();
      };
      await tester.pumpWidget(
        AMapView(onMapCreated: (value) => controller = value),
      );
      await tester.pump();
      final bounds = AMapBounds.fromPoints(const [AMapLatLng(22.5, 114)]);
      await expectLater(
        controller.fitBounds(bounds, padding: const EdgeInsets.only(right: -1)),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
      await controller.fitBounds(
        bounds,
        padding: const EdgeInsets.fromLTRB(40, 36, 28, 100),
        animated: true,
      );
      final sent = calls.single;
      expect(sent, containsPair('left', 40.0));
      expect(sent, containsPair('top', 36.0));
      expect(sent, containsPair('right', 28.0));
      expect(sent, containsPair('bottom', 100.0));
      expect(sent, containsPair('animated', true));
      expect(sent['south'], lessThan(22.5));
      expect(sent['north'], greaterThan(22.5));
      expect(sent['west'], lessThan(114));
      expect(sent['east'], greaterThan(114));
      await expectLater(
        controller.fitBounds(
          bounds,
          padding: const EdgeInsets.only(bottom: 10000),
        ),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'invalid_argument',
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      await expectLater(
        controller.fitBounds(bounds),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'map_disposed',
          ),
        ),
      );
      expect(calls, hasLength(2));
    },
  );
}
