import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('$amapViewType/806');
  final original = amapViewFactory;
  tearDown(() {
    amapViewFactory = original;
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('only confirmed drag commits after release', (tester) async {
    final idle = <AMapCameraReason>[];
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'getStatus' ? 'ready' : null,
    );
    amapViewFactory = (_, created) {
      WidgetsBinding.instance.addPostFrameCallback((_) => created(806));
      return const SizedBox();
    };
    await tester.pumpWidget(
      AMapView(onCameraIdle: (event) => idle.add(event.reason)),
    );
    await tester.pump();

    Map<String, Object> sample({
      double lat = 22.5,
      double zoom = 16,
      double bearing = 0,
    }) => {
      'latitude': lat,
      'longitude': 114.0,
      'zoom': zoom,
      'bearing': bearing,
      'tilt': 0.0,
    };
    Future<void> send(String name, Map<String, Object> data) =>
        messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall(name, data)),
          (_) {},
        );
    Future<void> signal(String kind) => send('cameraEvidence', {'kind': kind});
    Future<void> start() =>
        send('cameraEvidence', {'kind': 'start', ...sample()});
    Future<void> settle() => tester.pump(const Duration(milliseconds: 130));

    await start();
    await signal('drag');
    await send('cameraIdle', sample(lat: 22.51));
    await settle();
    expect(idle, isEmpty);
    await signal('end');
    await settle();
    expect(idle.last, AMapCameraReason.userDrag);

    // Pinch may move the target, even with a preceding one-finger drag.
    await start();
    await signal('drag');
    await signal('multi');
    await signal('end');
    await send('cameraIdle', sample(lat: 22.52, zoom: 17));
    await settle();
    expect(idle.last, AMapCameraReason.userZoom);

    await signal('program');
    await send('cameraIdle', sample(lat: 22.54, zoom: 14));
    expect(idle.last, AMapCameraReason.programmatic);

    await start();
    await signal('drag');
    await send('cameraIdle', sample(lat: 22.55, bearing: 20));
    await signal('end');
    await settle();
    expect(idle.last, AMapCameraReason.unknown);

    // A camera command overlaps a finger still on the map.
    await start();
    await signal('drag');
    await signal('program');
    await send('cameraIdle', sample(lat: 22.56));
    await signal('end');
    await settle();
    expect(idle.last, AMapCameraReason.unknown);

    // A cancelled gesture must not commit a pending drag.
    await start();
    await signal('drag');
    await send('cameraIdle', sample(lat: 22.56));
    await signal('cancel');
    await settle();
    expect(idle, hasLength(5));

    // App interruption clears the pending gesture, including the deferred idle.
    await start();
    await signal('drag');
    await send('cameraIdle', sample(lat: 22.57));
    await signal('end');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await settle();
    expect(idle, hasLength(5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await start();
    await signal('drag');
    await send('cameraIdle', sample(lat: 22.57));
    await signal('end');
    await settle();
    expect(idle.last, AMapCameraReason.userDrag);
    expect(idle, hasLength(6));

    await start();
    await signal('drag');
    await send('cameraIdle', sample(lat: 22.57));
    await signal('end');
    await tester.pumpWidget(const SizedBox());
    await settle();
    expect(idle, hasLength(6));
  });
}
