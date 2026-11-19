import 'dart:convert';
import 'dart:async';
import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final original = amapViewFactory;
  const channel = MethodChannel('$amapViewType/801');
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQAAAABJRU5ErkJggg==',
  );
  AMapMarker marker({String id = 'a', double lat = 22.5}) =>
      AMapMarker(id: id, latitude: lat, longitude: 114, pngBytes: png);
  tearDown(() {
    amapViewFactory = original;
    messenger.setMockMethodCallHandler(channel, null);
  });
  test('validates parameters and copies PNG into immutable bytes', () {
    final bytes = Uint8List.fromList(png);
    final value = AMapMarker(
      id: 'a',
      latitude: 0,
      longitude: 0,
      pngBytes: bytes,
    );
    bytes[0] = 0;
    expect(value.pngBytes[0], 137);
    expect(() => value.pngBytes[0] = 0, throwsUnsupportedError);
    expect(() => marker(id: ''), throwsArgumentError);
    expect(() => marker(lat: double.nan), throwsArgumentError);
    expect(
      () => AMapMarker(
        id: 'a',
        latitude: 0,
        longitude: 0,
        pngBytes: png,
        anchorU: 2,
      ),
      throwsArgumentError,
    );
  });
  testWidgets(
    'diffs by stable ID, ignores unchanged collections and routes taps only while present',
    (tester) async {
      final updates = <Map>[];
      final taps = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getStatus') return 'ready';
        if (call.method == 'updateMarkers') updates.add(call.arguments as Map);
        return null;
      });
      var created = false;
      amapViewFactory = (_, callback) {
        if (!created) {
          created = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => callback(801));
        }
        return const SizedBox();
      };
      Future<void> show(List<AMapMarker> markers) async {
        await tester.pumpWidget(
          AMapView(markers: markers, onMarkerTap: taps.add),
        );
        await tester.pump();
      }

      Future<void> tap(String id) =>
          tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('markerTap', id),
            ),
            (_) {},
          );
      await show([marker()]);
      expect(updates.length, 1);
      await show([marker()]);
      expect(updates.length, 1);
      await tap('a');
      expect(taps, ['a']);
      await show([marker(lat: 23), marker(id: 'b')]);
      expect((updates.last['upsert'] as List).length, 2);
      await show([marker(id: 'b')]);
      expect(updates.last['remove'], ['a']);
      expect(updates.last['upsert'], isEmpty);
      await tap('a');
      expect(taps.length, 1);
      await tester.pumpWidget(const SizedBox());
      await tap('b');
      expect(taps.length, 1);
    },
  );
  testWidgets(
    'native failure is reported once without rebuild retry; later change resends unconfirmed markers',
    (tester) async {
      var requests = 0;
      final errors = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getStatus') return 'ready';
        if (call.method == 'updateMarkers') {
          requests++;
          throw PlatformException(code: 'invalid_argument');
        }
        return null;
      });
      var created = false;
      amapViewFactory = (_, callback) {
        if (!created) {
          created = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => callback(801));
        }
        return const SizedBox();
      };
      await tester.pumpWidget(
        AMapView(markers: [marker()], onError: errors.add),
      );
      await tester.pump();
      expect(errors, ['invalid_argument']);
      await tester.pumpWidget(
        AMapView(markers: [marker()], onError: errors.add),
      );
      await tester.pump();
      expect(requests, 1);
      await tester.pumpWidget(
        AMapView(markers: [marker(lat: 23)], onError: errors.add),
      );
      await tester.pump();
      expect(requests, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('timed-out additions are removed by the next collection', (
    tester,
  ) async {
    final gate = Completer<void>();
    final updates = <Map>[];
    final errors = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getStatus') return 'ready';
      if (call.method == 'updateMarkers') {
        updates.add(call.arguments as Map);
        if (updates.length == 1) await gate.future;
      }
      return null;
    });
    var created = false;
    amapViewFactory = (_, callback) {
      if (!created) {
        created = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => callback(801));
      }
      return const SizedBox();
    };
    await tester.pumpWidget(AMapView(markers: [marker()], onError: errors.add));
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    expect(errors, ['operation_timeout']);
    await tester.pumpWidget(AMapView(onError: errors.add));
    await tester.pump();
    expect(updates.length, 2);
    expect(updates.last['remove'], ['a']);
    gate.complete();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('duplicate IDs fail before native creation', (tester) async {
    var created = false;
    amapViewFactory = (_, _) {
      created = true;
      return const SizedBox();
    };
    await tester.pumpWidget(AMapView(markers: [marker(), marker()]));
    expect(tester.takeException(), isArgumentError);
    expect(created, false);
  });
}
