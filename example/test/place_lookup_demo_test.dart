import 'dart:async';

import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:amap_flutter_bridge_example/poi_search_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'opens a fresh POI detail by its list ID, handles a miss and preserves the list on back',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      final ids = <String>[];
      const point = {'latitude': 22.54, 'longitude': 114.06};
      messenger.setMockMethodCallHandler(amapSdkChannel, (call) async {
        if (call.method == 'searchPoiPage') {
          return [
            {...point, 'id': 'B-test', 'name': '列表地点'},
            {...point, 'name': '无编号地点'},
          ];
        }
        expect(call.method, 'poiById');
        final id = (call.arguments as Map)['id'] as String;
        ids.add(id);
        if (id == 'missing') return [];
        return [
          {
            ...point,
            'id': id,
            'name': '详情地点',
            'district': '福田区',
            'adCode': '440304',
          },
        ];
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(amapSdkChannel, null),
      );
      await tester.pumpWidget(const MaterialApp(home: PoiSearchDemo()));
      await tester.tap(find.text('按关键词搜索'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('无编号地点'));
      expect(ids, isEmpty);
      await tester.tap(find.text('列表地点'));
      await tester.pumpAndSettle();
      expect(ids, ['B-test']);
      expect(find.text('详情地点'), findsOneWidget);
      expect(find.textContaining('行政区编码 440304'), findsOneWidget);
      expect(
        find.textContaining('GCJ-02 22.540000, 114.060000'),
        findsOneWidget,
      );
      expect(find.textContaining('电话'), findsNothing);
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pump();
      expect(find.text('详情地点'), findsNothing);
      await tester.tap(find.text('查询详情'));
      await tester.pumpAndSettle();
      expect(find.text('未找到该 POI'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('列表地点'), findsOneWidget);
      expect(find.text('第 1 页'), findsOneWidget);
    },
  );

  testWidgets(
    'edits, retries and exits an address lookup without applying stale results',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      final old = Completer<List<Object?>>();
      final afterExit = Completer<List<Object?>>();
      final calls = <Map>[];
      messenger.setMockMethodCallHandler(amapSdkChannel, (call) async {
        expect(call.method, 'forwardGeocode');
        final args = call.arguments as Map;
        calls.add(args);
        return switch (args['address']) {
          '深圳市福田区福中三路2010号' => old.future,
          '空地址' => [],
          '服务失败' => throw PlatformException(
            code: 'geocode_failed',
            details: 1002,
          ),
          '退出' => afterExit.future,
          _ => [
            {
              'formattedAddress': '新地址',
              'latitude': 22.55,
              'longitude': 114.05,
              'level': '道路',
            },
            {'latitude': 22.56, 'longitude': 114.06},
          ],
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(amapSdkChannel, null),
      );
      await tester.pumpWidget(const MaterialApp(home: PoiSearchDemo()));
      await tester.tap(find.text('地址查坐标'));
      await tester.pumpAndSettle();
      final address = find.byType(TextField).first;
      final city = find.byType(TextField).last;
      Future<void> submit(String text) async {
        await tester.enterText(address, text);
        await tester.tap(find.text('查询坐标'));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('查询坐标'));
      await tester.pump();
      expect(calls.single['city'], '深圳');
      await tester.enterText(city, '');
      await submit('新道路');
      expect(calls.last, {'address': '新道路'});
      expect(find.text('匹配到 2 个地址'), findsOneWidget);
      expect(find.textContaining('匹配级别 道路'), findsOneWidget);
      old.complete([
        {'formattedAddress': '旧地址', 'latitude': 0, 'longitude': 0},
      ]);
      await tester.pump();
      expect(find.text('新地址'), findsOneWidget);
      expect(find.text('旧地址'), findsNothing);
      await submit('服务失败');
      expect(find.textContaining('geocode_failed (1002)'), findsOneWidget);
      await submit('空地址');
      expect(find.text('没有匹配的地址'), findsOneWidget);
      await submit(' ');
      expect(find.text('请输入地址'), findsOneWidget);
      await tester.enterText(address, '退出');
      await tester.tap(find.text('查询坐标'));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      afterExit.complete([]);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('POI 搜索'), findsOneWidget);
    },
  );
}
