import 'dart:async';

import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:amap_flutter_bridge_example/calibration_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final fence in [false, true]) {
    testWidgets(
      'only the latest selected point gets an address (fence: $fence)',
      (tester) async {
        final messenger = tester.binding.defaultBinaryMessenger;
        final requests = <double, Completer<Map<String, Object>>>{};
        messenger.setMockMethodCallHandler(amapSdkChannel, (call) {
          expect(call.method, 'reverseGeocode');
          final args = call.arguments as Map;
          return (requests[args['latitude'] as double] = Completer()).future;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(amapSdkChannel, null),
        );
        final original = amapViewFactory;
        amapViewFactory = (_, _) => const SizedBox();
        addTearDown(() => amapViewFactory = original);

        await tester.pumpWidget(
          MaterialApp(home: CalibrationDemo(fence: fence)),
        );
        await tester.pump();
        final initial = requests.keys.single;

        Future<void> idle(AMapCameraReason reason, double latitude) async {
          final view = tester.widget<AMapView>(find.byType(AMapView));
          view.onCameraIdle!(
            AMapCameraEvent(
              AMapCameraPosition(
                latitude: latitude,
                longitude: 114.05,
                zoom: 16,
              ),
              reason: reason,
            ),
          );
          await tester.pump();
        }

        await idle(AMapCameraReason.programmatic, 22.51);
        await idle(AMapCameraReason.userZoom, 22.52);
        await idle(AMapCameraReason.unknown, 22.53);
        expect(requests.keys, [initial]);

        await idle(AMapCameraReason.userDrag, 22.55);
        await idle(AMapCameraReason.userDrag, 22.56);
        requests[22.56]!.complete({
          'formattedAddress': '新地址',
          'adCode': '440304',
        });
        await tester.pumpAndSettle();
        requests[22.55]!.complete({'formattedAddress': '旧地址'});
        requests[initial]!.complete({'formattedAddress': '默认地址'});
        await tester.pumpAndSettle();
        expect(find.text('地址：新地址'), findsOneWidget);
        expect(find.text('地址：旧地址'), findsNothing);
        expect(find.text('地址：默认地址'), findsNothing);
        if (fence) {
          final view = tester.widget<AMapView>(find.byType(AMapView));
          expect(view.circles.single.center.latitude, 22.56);
        }

        await idle(AMapCameraReason.userDrag, 22.57);
        await tester.pumpWidget(const SizedBox());
        requests[22.57]!.complete({'formattedAddress': '退出后返回'});
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
