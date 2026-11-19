import 'dart:async';

import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:amap_flutter_bridge_example/polygon_fence_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('$amapViewType/817');
  testWidgets(
    'drags a vertex in map-local pixels and reprojects after pan and zoom',
    (tester) async {
      final original = amapViewFactory;
      final messenger = tester.binding.defaultBinaryMessenger;
      var created = false;
      amapViewFactory = (_, callback) {
        if (!created) {
          created = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => callback(817));
        }
        return const SizedBox.expand();
      };
      addTearDown(() {
        amapViewFactory = original;
        messenger.setMockMethodCallHandler(channel, null);
      });

      var pan = Offset.zero;
      var zoom = 1.0;
      var projectionReady = true;
      const center = Offset(240, 190);
      Offset project(double lat, double lng) =>
          center +
          pan +
          Offset((lng - 114.05785) * 40000, (22.54335 - lat) * 40000) * zoom;
      final inverseRequests = <Offset>[];
      final changes = <Map>[];
      Completer<Object?>? delayed;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments;
        switch (call.method) {
          case 'getStatus':
            return 'loaded';
          case 'projectToScreen':
            if (!projectionReady) {
              throw PlatformException(code: 'map_not_ready');
            }
            final p = project(args['latitude'], args['longitude']);
            return {'x': p.dx, 'y': p.dy};
          case 'unprojectFromScreen':
            final p = Offset(args['x'], args['y']);
            inverseRequests.add(p);
            if (delayed != null) return delayed.future;
            final v = (p - center - pan) / zoom;
            return {
              'latitude': 22.54335 - v.dy / 40000,
              'longitude': 114.05785 + v.dx / 40000,
            };
          case 'updatePolygons':
            changes.add(args as Map);
        }
        return null;
      });
      await tester.pumpWidget(const MaterialApp(home: PolygonFenceDemo()));
      await tester.pumpAndSettle();
      final mapFinder = find.byType(AMapView);
      AMapView map() => tester.widget<AMapView>(mapFinder);
      Finder handle(int i) => find.byKey(ValueKey('vertex-$i'));
      final origin = tester.getTopLeft(mapFinder);
      final initial = map().polygons.single;
      void expectAlignment() {
        for (var i = 0; i < initial.points.length; i++) {
          final p = map().polygons.single.points[i];
          expect(
            (tester.getCenter(handle(i)) -
                    origin -
                    project(p.latitude, p.longitude))
                .distance,
            lessThan(.001),
          );
        }
      }

      expectAlignment();
      final start = tester.getCenter(handle(0));
      const delta = Offset(32, 24);
      delayed = Completer<Object?>();
      final gesture = await tester.startGesture(start + const Offset(4, 3));
      await gesture.moveBy(const Offset(12, 8));
      await tester.pump();
      await gesture.moveBy(const Offset(10, 6));
      await gesture.moveBy(const Offset(10, 10));
      await gesture.up();
      expect(inverseRequests, hasLength(1));
      delayed.complete({
        'latitude': initial.points[0].latitude,
        'longitude': initial.points[0].longitude,
      });
      delayed = null;
      await tester.pumpAndSettle();
      expect(
        (inverseRequests.last - (start + delta - origin)).distance,
        lessThan(.001),
      );
      expect(map().polygons.single.id, initial.id);
      expect(
        map().polygons.single.points[0].longitude,
        isNot(initial.points[0].longitude),
      );
      expect(map().polygons.single.points.skip(1), initial.points.skip(1));
      expect((changes.last['upsert'] as List).single['id'], initial.id);
      expectAlignment();
      final event = AMapCameraEvent(
        AMapCameraPosition(latitude: 22.54, longitude: 114.05, zoom: 16),
      );
      projectionReady = false;
      map().onCameraMove!(event);
      await tester.pumpAndSettle();
      expect(find.text('map_not_ready'), findsOneWidget);
      expect(handle(0), findsNothing);
      projectionReady = true;
      pan = const Offset(45, -15);
      map().onCameraMove!(event);
      await tester.pumpAndSettle();
      expect(find.text('map_not_ready'), findsNothing);
      expect(find.textContaining('顶点 1 · '), findsOneWidget);
      expectAlignment();
      zoom = 1.5;
      map().onCameraIdle!(event);
      await tester.pumpAndSettle();
      expectAlignment();
      expect(inverseRequests, hasLength(2));
      await tester.tap(find.text('换样式'));
      await tester.pumpAndSettle();
      expect(map().polygons.single.strokeWidth, 5);

      // A late drag result must not resurrect the old fence after deleting and re-adding its ID.
      delayed = Completer<Object?>();
      final lateGesture = await tester.startGesture(
        tester.getCenter(handle(1)),
      );
      await lateGesture.moveBy(const Offset(7, 9));
      await lateGesture.up();
      await tester.pump();
      await tester.tap(find.text('删除围栏'));
      await tester.pump();
      expect(map().polygons, isEmpty);
      expect(handle(1), findsNothing);
      await tester.tap(find.text('添加围栏'));
      await tester.pump();
      delayed.complete({'latitude': 30.0, 'longitude': 120.0});
      await tester.pumpAndSettle();
      expect(map().polygons.single.points, initial.points);
      expect(
        changes.any((c) => (c['remove'] as List).contains(initial.id)),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
    },
  );
}
