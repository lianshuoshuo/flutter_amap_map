import 'dart:async';

import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:amap_flutter_bridge_example/poi_search_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('displays both search modes and ignores responses after exit', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    final requests = <Map<Object?, Object?>>[];
    final lateReply = Completer<List<Object?>>();
    messenger.setMockMethodCallHandler(amapSdkChannel, (call) async {
      final args = call.arguments as Map<Object?, Object?>;
      requests.add(args);
      if (requests.length == 3) return lateReply.future;
      if (args.containsKey('radiusMeters')) return [];
      return [
        {
          'name': '深圳市民中心',
          'address': '福中三路',
          'category': '政府机构',
          'latitude': 22.54,
          'longitude': 114.05,
        },
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(amapSdkChannel, null));

    await tester.pumpWidget(const MaterialApp(home: PoiSearchDemo()));
    await tester.tap(find.text('按关键词搜索'));
    await tester.pumpAndSettle();
    expect(requests.single['keyword'], '深圳市民中心');
    expect(find.text('关键词搜索：1 个结果'), findsOneWidget);
    expect(find.textContaining('GCJ-02 22.540000, 114.050000'), findsOneWidget);
    expect(find.textContaining('政府机构'), findsOneWidget);

    await tester.tap(find.text('查市民中心周边'));
    await tester.pumpAndSettle();
    expect(requests.last['radiusMeters'], 1000);
    expect(requests.last['keyword'], isEmpty);
    expect(find.text('周边搜索无结果'), findsOneWidget);

    await tester.tap(find.text('查市民中心周边'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    lateReply.complete([]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'debounces and selects text-only tips, pages filtered results and retries a failed page',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      final tips = <Map>[];
      final searches = <Map>[];
      final firstTips = Completer<List<Object?>>();
      var failPageTwo = true;
      messenger.setMockMethodCallHandler(amapSdkChannel, (call) async {
        final args = call.arguments as Map;
        if (call.method == 'inputTips') {
          tips.add(args);
          if (tips.length == 1) return firstTips.future;
          return [
            {'name': '市民餐厅'},
          ];
        }
        searches.add(args);
        final page = args['page'] ?? 1;
        if (page == 2 && failPageTwo) {
          failPageTwo = false;
          throw PlatformException(code: 'poi_search_failed', details: 1002);
        }
        if (page == 3) return [];
        return [
          {'name': '餐厅第$page组', 'latitude': 22.54, 'longitude': 114.05},
        ];
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(amapSdkChannel, null),
      );
      await tester.pumpWidget(const MaterialApp(home: PoiSearchDemo()));
      final field = find.byType(TextField);
      await tester.enterText(field, '市');
      await tester.pump(const Duration(milliseconds: 299));
      expect(tips, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(tips, hasLength(1));

      await tester.enterText(field, '市民');
      await tester.tap(find.text('关键词限深圳'));
      await tester.tap(find.text('餐饮'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(tips, hasLength(2));
      expect(tips.last, {
        'keyword': '市民',
        'city': '深圳',
        'categoryCode': '050000',
      });
      expect(find.text('市民餐厅'), findsOneWidget);
      firstTips.complete([
        {'name': '旧提示'},
      ]);
      await tester.pump();
      expect(find.text('旧提示'), findsNothing);

      await tester.tap(find.text('市民餐厅'));
      await tester.pumpAndSettle();
      expect(searches.single, {
        'keyword': '市民餐厅',
        'city': '深圳',
        'categoryCode': '050000',
        'pageSize': 5,
      });
      expect(find.text('第 1 页'), findsOneWidget);
      expect(find.text('餐厅第1组'), findsOneWidget);
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(find.textContaining('poi_search_failed (1002)'), findsOneWidget);
      expect(find.text('餐厅第1组'), findsOneWidget);
      expect(find.text('第 1 页'), findsOneWidget);
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(searches.last, {...searches.first, 'page': 2});
      expect(find.text('餐厅第2组'), findsOneWidget);
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('关键词搜索无结果'), findsOneWidget);
      expect(find.text('第 3 页'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '下一页'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('上一页'));
      await tester.pumpAndSettle();
      expect(find.text('餐厅第2组'), findsOneWidget);
      await tester.tap(find.text('查市民中心周边'));
      await tester.pumpAndSettle();
      expect(searches.last['categoryCode'], '050000');
      expect(searches.last.containsKey('city'), isFalse);
      expect(find.text('第 1 页'), findsOneWidget);
      await tester.enterText(field, '');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('第 1 页'), findsNothing);
      expect(tips, hasLength(2));
      await tester.tap(find.text('查市民中心周边'));
      await tester.pumpAndSettle();
      expect(find.text('第 1 页'), findsOneWidget);
      await tester.tap(find.text('按关键词搜索'));
      await tester.pumpAndSettle();
      expect(find.text('请输入关键词'), findsOneWidget);
      expect(find.text('餐厅第1组'), findsNothing);
      expect(find.text('第 1 页'), findsNothing);
    },
  );

  testWidgets('an old search or failed tip cannot overwrite a newer query', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    final oldSearch = Completer<List<Object?>>();
    final lateTip = Completer<List<Object?>>();
    messenger.setMockMethodCallHandler(amapSdkChannel, (call) async {
      if (call.method == 'inputTips') return lateTip.future;
      final args = call.arguments as Map;
      if (args['keyword'] == '深圳市民中心') return oldSearch.future;
      return [
        {'name': '公园新结果', 'latitude': 22.54, 'longitude': 114.05},
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(amapSdkChannel, null));
    await tester.pumpWidget(const MaterialApp(home: PoiSearchDemo()));
    await tester.tap(find.text('按关键词搜索'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '公园');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('按关键词搜索'));
    await tester.pumpAndSettle();
    expect(find.text('公园新结果'), findsOneWidget);
    oldSearch.complete([
      {'name': '旧地点', 'latitude': 22, 'longitude': 114},
    ]);
    lateTip.completeError(PlatformException(code: 'poi_search_failed'));
    await tester.pump();
    expect(find.text('公园新结果'), findsOneWidget);
    expect(find.text('旧地点'), findsNothing);
    expect(find.textContaining('失败'), findsNothing);
  });
}
