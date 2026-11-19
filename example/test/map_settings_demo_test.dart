import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:amap_flutter_bridge_example/map_settings_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows SDK readback, preserves limits on toggle and reports missing data',
    (tester) async {
      final original = amapViewFactory;
      const channel = MethodChannel('$amapViewType/809');
      final messenger = tester.binding.defaultBinaryMessenger;
      var created = false;
      amapViewFactory = (_, callback) {
        if (!created) {
          created = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => callback(809));
        }
        return const SizedBox.expand();
      };
      final options = <Map>[];
      var approvalAvailable = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getStatus':
            return 'loaded';
          case 'setOptions':
            options.add(call.arguments as Map);
          case 'getZoomRange':
            return {'minZoom': options.last['minZoom'], 'maxZoom': 19.0};
          case 'getCamera':
            return {'latitude': 22.5333, 'longitude': 114.0557, 'zoom': 19.0};
          case 'moveCamera':
            expect((call.arguments as Map)['zoom'], 20);
            throw PlatformException(code: 'invalid_argument');
          case 'getMapApprovalNumbers':
            return approvalAvailable ? {'mapContent': '矢量测试'} : {};
        }
        return null;
      });
      addTearDown(() {
        amapViewFactory = original;
        messenger.setMockMethodCallHandler(channel, null);
      });
      await tester.pumpWidget(const MaterialApp(home: MapSettingsDemo()));
      await tester.pumpAndSettle();
      expect(find.text('SDK 范围 3–19 · 当前缩放 19.00'), findsOneWidget);
      await tester.tap(find.text('17–19'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('隐藏 3D 建筑'));
      await tester.pumpAndSettle();
      expect(options.last['minZoom'], 17);
      expect(options.last['maxZoom'], 19);
      expect(options.last['buildingsEnabled'], false);
      expect(find.text('显示 3D 建筑'), findsOneWidget);
      await tester.tap(find.byTooltip('切换卫星图'));
      await tester.pumpAndSettle();
      expect(options.last['mapType'], 'satellite');
      expect(options.last['minZoom'], 17);
      expect(options.last['buildingsEnabled'], false);
      await tester.tap(find.byTooltip('放大一级'));
      await tester.pumpAndSettle();
      expect(find.text('invalid_argument'), findsOneWidget);
      await tester.tap(find.text('读取审图号'));
      await tester.pumpAndSettle();
      expect(find.text('普通地图 矢量测试'), findsOneWidget);
      expect(find.text('卫星影像 SDK 暂未提供'), findsOneWidget);
      approvalAvailable = false;
      await tester.tap(find.text('读取审图号'));
      await tester.pumpAndSettle();
      expect(find.text('approval_numbers_unavailable'), findsOneWidget);
      expect(find.text('普通地图 矢量测试'), findsNothing);
    },
  );
}
