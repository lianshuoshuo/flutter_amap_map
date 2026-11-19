import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final originalFactory = amapViewFactory;
  tearDown(() {
    amapViewFactory = originalFactory;
    messenger.setMockMethodCallHandler(amapSdkChannel, null);
  });
  test('refused consent or empty Key never reaches native SDK', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(amapSdkChannel, (_) async {
      calls++;
      return 'test';
    });
    await expectLater(
      AMapSdk.initialize(apiKey: 'test', privacyAgreed: false),
      throwsA(isA<PlatformException>()),
    );
    await expectLater(
      AMapSdk.initialize(apiKey: '', privacyAgreed: true),
      throwsArgumentError,
    );
    expect(calls, 0);
  });
  testWidgets('instances use separate channels and dispose independently', (
    tester,
  ) async {
    final calls = <int, List<String>>{};
    var nextId = 0;
    amapViewFactory = (params, onCreated) {
      final id = nextId++;
      calls[id] = [];
      messenger.setMockMethodCallHandler(MethodChannel('$amapViewType/$id'), (
        call,
      ) async {
        calls[id]!.add(call.method);
        return call.method == 'getStatus' ? 'loaded' : null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => onCreated(id));
      return const SizedBox();
    };
    final statuses = <AMapStatus>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            AMapView(onStatusChanged: statuses.add),
            AMapView(onStatusChanged: statuses.add),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(statuses, [AMapStatus.loaded, AMapStatus.loaded]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(calls[0], ['setActive', 'getStatus', 'dispose']);
    expect(calls[1], ['setActive', 'getStatus', 'dispose']);
    for (final id in calls.keys) {
      messenger.setMockMethodCallHandler(
        MethodChannel('$amapViewType/$id'),
        null,
      );
    }
  });
  testWidgets('invalid coordinates are rejected before native view creation', (
    tester,
  ) async {
    var created = false;
    amapViewFactory = (_, _) {
      created = true;
      return const SizedBox();
    };
    await tester.pumpWidget(const AMapView(latitude: 100));
    expect(tester.takeException(), isArgumentError);
    expect(created, false);
  });
  testWidgets(
    'native failure after loaded is reported and events stop after dispose',
    (tester) async {
      const channel = MethodChannel('$amapViewType/99');
      final statuses = <AMapStatus>[];
      final errors = <String>[];
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'getStatus' ? 'loaded' : null,
      );
      amapViewFactory = (_, created) {
        WidgetsBinding.instance.addPostFrameCallback((_) => created(99));
        return const SizedBox();
      };
      await tester.pumpWidget(
        AMapView(onStatusChanged: statuses.add, onError: errors.add),
      );
      await tester.pump();
      Future<void> emit(String value) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('status', value),
          ),
          (_) {},
        );
      }

      await emit('failed');
      expect(statuses, [AMapStatus.loaded, AMapStatus.failed]);
      expect(errors, ['native_map_error']);
      await tester.pumpWidget(const SizedBox());
      await emit('loaded');
      expect(statuses.length, 2);
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
}
