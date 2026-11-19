import 'dart:async';
import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final factory = amapViewFactory;
  const channel = MethodChannel('$amapViewType/701');
  tearDown(() {
    amapViewFactory = factory;
    messenger.setMockMethodCallHandler(channel, null);
  });
  test('camera rejects invalid and nonfinite numbers', () {
    for (final values in [
      [91.0, 0.0, 12.0],
      [0.0, double.nan, 12.0],
      [0.0, 0.0, 21.0],
    ]) {
      expect(
        () => AMapCameraPosition(
          latitude: values[0],
          longitude: values[1],
          zoom: values[2],
        ),
        throwsArgumentError,
      );
    }
  });
  testWidgets('sends a map-local camera anchor when explicitly requested', (
    tester,
  ) async {
    late AMapController controller;
    final requests = <Map<Object?, Object?>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getStatus') return 'ready';
      if (call.method == 'moveCamera') {
        final args = call.arguments as Map<Object?, Object?>;
        requests.add(args);
        if ((args['targetScreenPoint'] as Map?)?['x'] == 10000) {
          throw PlatformException(code: 'invalid_argument');
        }
      }
      return null;
    });
    amapViewFactory = (_, created) {
      WidgetsBinding.instance.addPostFrameCallback((_) => created(701));
      return const SizedBox();
    };
    await tester.pumpWidget(
      AMapView(onMapCreated: (value) => controller = value),
    );
    await tester.pump();
    final camera = AMapCameraPosition(latitude: 22.5, longitude: 114, zoom: 16);
    for (final invalid in [
      const Offset(-1, 8),
      const Offset(8, double.infinity),
    ]) {
      await expectLater(
        controller.moveCamera(camera, targetScreenPoint: invalid),
        throwsArgumentError,
      );
    }
    expect(requests, isEmpty);
    await controller.moveCamera(
      camera,
      animated: true,
      targetScreenPoint: const Offset(120.5, 96),
    );
    expect(requests.single, {
      'latitude': 22.5,
      'longitude': 114.0,
      'zoom': 16.0,
      'animated': true,
      'targetScreenPoint': {'x': 120.5, 'y': 96.0},
    });
    await expectLater(
      controller.moveCamera(camera, targetScreenPoint: const Offset(10000, 30)),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'invalid_argument',
        ),
      ),
    );
    await controller.moveCamera(camera);
    expect(requests.last, isNot(contains('targetScreenPoint')));
  });
  testWidgets('timeout terminates a command without retrying it', (
    tester,
  ) async {
    late AMapController controller;
    var moves = 0;
    final gate = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getStatus') return 'ready';
      if (call.method == 'moveCamera') {
        moves++;
        await gate.future;
      }
      return null;
    });
    amapViewFactory = (_, created) {
      WidgetsBinding.instance.addPostFrameCallback((_) => created(701));
      return const SizedBox();
    };
    await tester.pumpWidget(
      AMapView(onMapCreated: (value) => controller = value),
    );
    await tester.pump();
    final command = controller.moveCamera(
      AMapCameraPosition(latitude: 0, longitude: 0, zoom: 3),
    );
    final failure = expectLater(
      command,
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'operation_timeout',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    await failure;
    expect(moves, 1);
    gate.complete();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'camera commands serialize, events route, disposal cancels pending and queued commands',
    (tester) async {
      late AMapController controller;
      final gate = Completer<void>();
      final commands = <String>[];
      final events = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getStatus') return 'ready';
        if (call.method == 'moveCamera') {
          commands.add(call.method);
          expectSync((call.arguments as Map)['animated'], true);
          await gate.future;
        }
        if (call.method == 'getCamera') {
          commands.add(call.method);
          return {'latitude': 22.5, 'longitude': 114.0, 'zoom': 14.0};
        }
        return null;
      });
      amapViewFactory = (_, created) {
        WidgetsBinding.instance.addPostFrameCallback((_) => created(701));
        return const SizedBox();
      };
      await tester.pumpWidget(
        AMapView(
          onMapCreated: (value) => controller = value,
          onCameraMove: (event) => events.add('move/${event.source}'),
          onCameraIdle: (event) => events.add('idle/${event.position.zoom}'),
        ),
      );
      await tester.pump();
      final move = controller.moveCamera(
        AMapCameraPosition(latitude: 22.5, longitude: 114, zoom: 14),
        animated: true,
      );
      final read = controller.getCamera();
      await tester.pump();
      expect(commands, ['moveCamera']);
      gate.complete();
      await tester.pump();
      await move;
      expect((await read).zoom, 14);
      expect(commands, ['moveCamera', 'getCamera']);
      Future<void> emit(String method) =>
          tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, {
                'latitude': 22.5,
                'longitude': 114.0,
                'zoom': 14.0,
              }),
            ),
            (_) {},
          );
      await emit('cameraMove');
      await emit('cameraIdle');
      expect(events, ['move/unknown', 'idle/14.0']);
      final pendingGate = Completer<void>();
      final disposalCalls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        disposalCalls.add(call.method);
        if (call.method == 'moveCamera') await pendingGate.future;
        return null;
      });
      final pending = controller.moveCamera(
        AMapCameraPosition(latitude: 0, longitude: 0, zoom: 3),
      );
      final queued = controller.getCamera();
      final fails = Future.wait([
        expectLater(
          pending,
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'map_disposed',
            ),
          ),
        ),
        expectLater(
          queued,
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'map_disposed',
            ),
          ),
        ),
      ]);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await fails;
      pendingGate.complete();
      await tester.pump();
      expect(disposalCalls, ['moveCamera', 'dispose']);
      await expectLater(
        controller.getCamera(),
        throwsA(isA<PlatformException>()),
      );
      await emit('cameraIdle');
      expect(events.length, 2);
    },
  );
}
