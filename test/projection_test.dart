import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unprojects local logical pixels without converting GCJ-02', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    const channel = MethodChannel('$amapViewType/816');
    final original = amapViewFactory;
    amapViewFactory = (_, created) {
      WidgetsBinding.instance.addPostFrameCallback((_) => created(816));
      return const SizedBox();
    };
    addTearDown(() {
      amapViewFactory = original;
      messenger.setMockMethodCallHandler(channel, null);
    });
    Object? result = {'latitude': 22.54321, 'longitude': 114.05789};
    final calls = <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getStatus') return 'loaded';
      if (call.method != 'unprojectFromScreen') return null;
      calls.add(call.arguments);
      final value = result;
      if (value is PlatformException) throw value;
      return value;
    });
    late AMapController map;
    await tester.pumpWidget(AMapView(onMapCreated: (c) => map = c));
    await tester.pump();
    for (final bad in [
      const Offset(-1, 0),
      const Offset(0, double.infinity),
      const Offset(double.nan, 0),
    ]) {
      await expectLater(map.unprojectFromScreen(bad), throwsArgumentError);
    }
    expect(calls, isEmpty);
    final p = await map.unprojectFromScreen(const Offset(71.5, 96.25));
    expect((p.latitude, p.longitude), (22.54321, 114.05789));
    expect(calls.single, {'x': 71.5, 'y': 96.25});
    Future<void> expectCode(String code) => expectLater(
      map.unprojectFromScreen(Offset.zero),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
    );
    for (final bad in [
      null,
      {},
      {'latitude': double.nan, 'longitude': 0},
      {'latitude': 22, 'longitude': -181},
    ]) {
      result = bad;
      await expectCode('projection_failed');
    }
    for (final code in [
      'invalid_argument',
      'projection_failed',
      'map_not_ready',
    ]) {
      result = PlatformException(code: code);
      await expectCode(code);
    }
    await tester.pumpWidget(const SizedBox());
    await expectCode('map_disposed');
    expect(calls, hasLength(8));
  });

  testWidgets('projects map-local offsets and checks errors and disposal', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    const channel = MethodChannel('$amapViewType/807');
    const point = AMapLatLng(22.5431, 114.0579);
    final original = amapViewFactory;
    amapViewFactory = (_, created) {
      WidgetsBinding.instance.addPostFrameCallback((_) => created(807));
      return const SizedBox();
    };
    addTearDown(() {
      amapViewFactory = original;
      messenger.setMockMethodCallHandler(channel, null);
    });

    late AMapController controller;
    final requests = <Object?>[];
    Object? response = {'x': -12.5, 'y': 280};
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getStatus':
          return 'loaded';
        case 'projectToScreen':
          requests.add(call.arguments);
          final result = response;
          if (result is PlatformException) throw result;
          return result;
      }
      return null;
    });
    await tester.pumpWidget(AMapView(onMapCreated: (map) => controller = map));
    await tester.pump();

    await expectLater(
      controller.projectToScreen(const AMapLatLng(double.nan, 114)),
      throwsArgumentError,
    );
    await expectLater(
      controller.projectToScreen(const AMapLatLng(22, 181)),
      throwsArgumentError,
    );
    expect(requests, isEmpty);

    expect(await controller.projectToScreen(point), const Offset(-12.5, 280));
    expect(requests.single, {'latitude': 22.5431, 'longitude': 114.0579});

    Future<void> expectCode(String code) => expectLater(
      controller.projectToScreen(point),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
    );
    response = {'x': double.infinity, 'y': 0};
    await expectCode('projection_failed');
    response = null;
    await expectCode('projection_failed');
    response = PlatformException(code: 'map_not_ready');
    await expectCode('map_not_ready');
    await tester.pumpWidget(const SizedBox());
    await expectCode('map_disposed');
    expect(requests, hasLength(4));
  });
}
