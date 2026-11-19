import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:amap_flutter_bridge_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the example bundles every locator and footprint marker', (
    _,
  ) async {
    const base = 'packages/amap_example_scenes/assets';
    final assets = [
      '$base/pet_pin.png',
      for (final kind in ['start', 'mid', 'end']) ...[
        '$base/trace/$kind.png',
        '$base/trace/${kind}_selected.png',
      ],
    ];
    for (final asset in assets) {
      final bytes = await rootBundle.load(asset);
      expect(bytes.getUint32(0), 0x89504e47, reason: asset);
    }
  });

  testWidgets('consent gates initialization and no native view is created', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.byType(AndroidView), findsNothing);
    expect(find.byType(UiKitView), findsNothing);
    expect(find.text('足迹'), findsNothing);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'one initialization opens footprint, locator and the other demos',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(amapSdkChannel, (call) async {
        calls.add(call.method);
        return call.method == 'reverseGeocode'
            ? {'formattedAddress': '演示地址'}
            : 'test';
      });
      final original = amapViewFactory;
      amapViewFactory = (_, _) => const SizedBox.expand();
      addTearDown(() {
        amapViewFactory = original;
        messenger.setMockMethodCallHandler(amapSdkChannel, null);
      });

      await tester.pumpWidget(const ExampleApp(apiKey: 'test'));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('初始化地图'));
      await tester.pumpAndSettle();
      expect(find.byType(AMapView), findsNothing);

      Future<void> open(String title, Finder content) async {
        final entry = find.widgetWithText(ListTile, title);
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(content, findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('高德地图示例'), findsOneWidget);
        expect(find.text('初始化地图'), findsNothing);
        expect(find.byType(AMapView), findsNothing);
      }

      await open('足迹', find.text('福田站东北侧'));
      await open('定位器地图', find.text('回到宠物位置'));
      await open('位置校准', find.text('程序回中'));
      await open('围栏选点', find.text('程序回中'));
      await open('不规则围栏', find.text('围栏取景'));
      await open('POI 搜索', find.text('按关键词搜索'));
      await open('查找宠物投影', find.text('回到雷达圈'));
      await open('地图设置', find.text('读取审图号'));
      await open('地图调试', find.text('双地图'));
      expect(calls, ['initialize', 'reverseGeocode', 'reverseGeocode']);
    },
  );
}
