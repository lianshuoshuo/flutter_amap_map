import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final original = amapViewFactory;
  const left = MethodChannel('$amapViewType/807');
  const right = MethodChannel('$amapViewType/808');

  tearDown(() {
    amapViewFactory = original;
    for (final channel in [left, right]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  testWidgets('coordinates stay on their map and stop after disposal', (
    tester,
  ) async {
    for (final channel in [left, right]) {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'getStatus' ? 'ready' : null,
      );
    }
    var next = 807;
    amapViewFactory = (_, created) => _FakeMap(next++, created);
    final leftPoints = <AMapLatLng>[];
    final rightPoints = <AMapLatLng>[];
    final markerTaps = <String>[];
    final marker = AMapMarker(
      id: 'sample',
      latitude: 22.5431,
      longitude: 114,
      // Only the header is needed by the mock channel; no native decode occurs.
      pngBytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
    );
    Widget maps({required bool showLeft}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          if (showLeft)
            AMapView(
              key: const ValueKey('left'),
              markers: [marker],
              onMapTap: leftPoints.add,
              onMarkerTap: markerTaps.add,
            ),
          AMapView(key: const ValueKey('right'), onMapTap: rightPoints.add),
        ],
      ),
    );
    Future<void> emit(MethodChannel channel, String method, Object? payload) =>
        messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, payload),
          ),
          (_) {},
        );

    await tester.pumpWidget(maps(showLeft: true));
    await tester.pump();
    const point = {'latitude': 22.5431, 'longitude': 114};
    await emit(right, 'mapTap', point);
    expect(leftPoints, isEmpty);
    expect(rightPoints.single.latitude, 22.5431);
    expect(rightPoints.single.longitude, 114);
    await emit(left, 'mapTap', point);
    await emit(left, 'markerTap', 'sample');
    await emit(left, 'mapTap', {'latitude': double.nan, 'longitude': 114});
    await emit(left, 'mapTap', {'latitude': 22, 'longitude': 181});
    await emit(left, 'mapTap', 'not a coordinate');
    expect(leftPoints, hasLength(1));
    expect(markerTaps, ['sample']);

    await tester.pumpWidget(maps(showLeft: false));
    await emit(left, 'mapTap', point);
    await emit(right, 'mapTap', point);
    expect(leftPoints, hasLength(1));
    expect(rightPoints, hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });
}

class _FakeMap extends StatefulWidget {
  const _FakeMap(this.id, this.created);
  final int id;
  final ValueChanged<int> created;

  @override
  State<_FakeMap> createState() => _FakeMapState();
}

class _FakeMapState extends State<_FakeMap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.created(widget.id),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
