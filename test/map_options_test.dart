import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('$amapViewType/805');
  final original = amapViewFactory;
  tearDown(() {
    amapViewFactory = original;
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<AMapController> mount(WidgetTester tester) async {
    late AMapController controller;
    amapViewFactory = (_, created) {
      WidgetsBinding.instance.addPostFrameCallback((_) => created(805));
      return const SizedBox();
    };
    await tester.pumpWidget(
      AMapView(onMapCreated: (value) => controller = value),
    );
    await tester.pump();
    return controller;
  }

  testWidgets('applies the full configuration on the existing map instance', (
    tester,
  ) async {
    late AMapController controller;
    final calls = <Map<Object?, Object?>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getStatus') return 'ready';
      if (call.method == 'setOptions') {
        final args = call.arguments as Map<Object?, Object?>;
        calls.add(args);
        if (args['zoomControlsEnabled'] == true) {
          throw PlatformException(code: 'unsupported_option');
        }
      }
      return null;
    });
    var creations = 0;
    amapViewFactory = (_, created) {
      creations++;
      WidgetsBinding.instance.addPostFrameCallback((_) => created(805));
      return const SizedBox();
    };
    await tester.pumpWidget(
      AMapView(onMapCreated: (value) => controller = value),
    );
    await tester.pump();
    await controller.setOptions(
      const AMapOptions(
        mapType: AMapType.satellite,
        minZoom: 12.5,
        maxZoom: 18,
        buildingsEnabled: false,
        zoomEnabled: false,
        rotateEnabled: false,
        tiltEnabled: false,
        inertiaEnabled: false,
        compassEnabled: false,
        scaleEnabled: false,
      ),
    );
    expect(calls.single, {
      'mapType': 'satellite',
      'minZoom': 12.5,
      'maxZoom': 18.0,
      'buildingsEnabled': false,
      'scrollEnabled': true,
      'zoomEnabled': false,
      'rotateEnabled': false,
      'tiltEnabled': false,
      'inertiaEnabled': false,
      'compassEnabled': false,
      'scaleEnabled': false,
      'zoomControlsEnabled': false,
    });
    await controller.setOptions(const AMapOptions());
    expect(calls.last['mapType'], 'standard');
    expect(calls.last['minZoom'], 3.0);
    expect(calls.last['maxZoom'], 20.0);
    expect(calls.last['buildingsEnabled'], true);
    expect(calls.last['zoomEnabled'], true);
    expect(calls.last['inertiaEnabled'], true);
    expect(creations, 1);
    await expectLater(
      controller.setOptions(const AMapOptions(zoomControlsEnabled: true)),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'unsupported_option',
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await expectLater(
      controller.setOptions(const AMapOptions()),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'map_disposed',
        ),
      ),
    );
    expect(calls, hasLength(3));
  });

  testWidgets(
    'rejects invalid intervals before sending and reads native limits',
    (tester) async {
      final sent = <Object?>[];
      Object? range = {'minZoom': 12.5, 'maxZoom': 19};
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getStatus') return 'loaded';
        if (call.method == 'getZoomRange') return range;
        if (call.method == 'setOptions') sent.add(call.arguments);
        return null;
      });
      final controller = await mount(tester);
      for (final invalid in const [
        AMapOptions(minZoom: 2.9),
        AMapOptions(maxZoom: 21),
        AMapOptions(minZoom: 16, maxZoom: 15),
        AMapOptions(minZoom: double.nan),
        AMapOptions(maxZoom: double.infinity),
      ]) {
        await expectLater(controller.setOptions(invalid), throwsArgumentError);
      }
      expect(sent, isEmpty);
      await controller.setOptions(const AMapOptions(minZoom: 17, maxZoom: 17));
      expect((sent.single as Map)['maxZoom'], 17);
      expect(await controller.getZoomRange(), (minZoom: 12.5, maxZoom: 19.0));
      for (final invalid in [
        null,
        {'minZoom': 14, 'maxZoom': 13},
        {'minZoom': double.nan, 'maxZoom': 19},
      ]) {
        range = invalid;
        await expectLater(
          controller.getZoomRange(),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'zoom_range_unavailable',
            ),
          ),
        );
      }
    },
  );

  testWidgets(
    'returns SDK approval numbers, partial availability and native errors',
    (tester) async {
      Object? numbers = {
        'mapContent': '  vector test  ',
        'satelliteImage': 'image test',
      };
      String? error;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getStatus') return 'loaded';
        if (call.method != 'getMapApprovalNumbers') return null;
        if (error != null) throw PlatformException(code: error);
        return numbers;
      });
      final controller = await mount(tester);
      final both = await controller.getMapApprovalNumbers();
      expect(both.mapContent, 'vector test');
      expect(both.satelliteImage, 'image test');
      numbers = {'satelliteImage': 'only image', 'mapContent': '  '};
      final satellite = await controller.getMapApprovalNumbers();
      expect(satellite.mapContent, isNull);
      expect(satellite.satelliteImage, 'only image');
      numbers = {'mapContent': 'only vector'};
      expect((await controller.getMapApprovalNumbers()).satelliteImage, isNull);
      for (final missing in [
        null,
        {},
        {'satelliteImage': '  ', 'mapContent': null},
      ]) {
        numbers = missing;
        await expectLater(
          controller.getMapApprovalNumbers(),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'approval_numbers_unavailable',
            ),
          ),
        );
      }
      error = 'map_not_ready';
      await expectLater(
        controller.getMapApprovalNumbers(),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'map_not_ready',
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      for (final read in [
        controller.getMapApprovalNumbers,
        controller.getZoomRange,
      ]) {
        await expectLater(
          read(),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'map_disposed',
            ),
          ),
        );
      }
    },
  );

  testWidgets('two controllers read and configure their own map', (
    tester,
  ) async {
    final controllers = <AMapController>[];
    for (final id in [811, 812]) {
      final native = MethodChannel('$amapViewType/$id');
      var min = 3.0;
      messenger.setMockMethodCallHandler(native, (call) async {
        switch (call.method) {
          case 'getStatus':
            return 'loaded';
          case 'setOptions':
            min = (call.arguments as Map)['minZoom'] as double;
          case 'getZoomRange':
            return {'minZoom': min, 'maxZoom': 20};
          case 'getMapApprovalNumbers':
            return {'mapContent': 'map $id'};
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(native, null));
    }
    var next = 811;
    amapViewFactory = (_, onCreated) {
      final id = next++;
      WidgetsBinding.instance.addPostFrameCallback((_) => onCreated(id));
      return const SizedBox();
    };
    await tester.pumpWidget(
      Column(
        children: [
          AMapView(onMapCreated: controllers.add),
          AMapView(onMapCreated: controllers.add),
        ],
      ),
    );
    await tester.pump();
    await controllers.first.setOptions(const AMapOptions(minZoom: 15));
    expect((await controllers.first.getZoomRange()).minZoom, 15);
    expect((await controllers.last.getZoomRange()).minZoom, 3);
    expect(
      (await controllers.first.getMapApprovalNumbers()).mapContent,
      'map 811',
    );
    expect(
      (await controllers.last.getMapApprovalNumbers()).mapContent,
      'map 812',
    );
  });
}
