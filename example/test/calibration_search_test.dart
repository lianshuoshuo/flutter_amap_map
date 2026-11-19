import 'dart:async';

import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:amap_flutter_bridge_example/calibration_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _home = {'latitude': 22.5431, 'longitude': 114.0579};
const _park = {'latitude': 22.5501, 'longitude': 114.054};
const _door = {'latitude': 22.5417, 'longitude': 114.062};
const _channel = MethodChannel('$amapViewType/815');

Future<void> _openMap(
  WidgetTester tester, {
  bool fence = false,
  required Future<Object?> Function(MethodCall) search,
  required Future<Object?> Function(MethodCall) map,
}) async {
  final messenger = tester.binding.defaultBinaryMessenger;
  final original = amapViewFactory;
  var registered = false;
  amapViewFactory = (_, created) {
    if (!registered) {
      registered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => created(815));
    }
    return const SizedBox.expand();
  };
  messenger.setMockMethodCallHandler(amapSdkChannel, search);
  messenger.setMockMethodCallHandler(_channel, (call) async {
    if (call.method == 'getStatus') return 'loaded';
    return map(call);
  });
  addTearDown(() {
    amapViewFactory = original;
    messenger.setMockMethodCallHandler(_channel, null);
    messenger.setMockMethodCallHandler(amapSdkChannel, null);
  });
  await tester.pumpWidget(MaterialApp(home: CalibrationDemo(fence: fence)));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _idle(
  WidgetTester tester,
  AMapCameraReason reason,
  Map<String, double> point,
) async {
  final map = tester.widget<AMapView>(find.byType(AMapView));
  map.onCameraIdle!(
    AMapCameraEvent(
      AMapCameraPosition.fromMap({...point, 'zoom': 16.0}),
      reason: reason,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final fence in [false, true]) {
    testWidgets(
      'POI and address picks move the map and update the card (fence: $fence)',
      (tester) async {
        final oldReverse = Completer<Object?>();
        final reversePoints = <Map>[];
        final moves = <Map>[];
        final circles = <Map>[];
        await _openMap(
          tester,
          fence: fence,
          search: (call) async {
            final args = call.arguments as Map;
            switch (call.method) {
              case 'searchPoiPage':
                if (args.containsKey('radiusMeters')) {
                  expect(args, containsPair('latitude', _door['latitude']));
                  expect(args, containsPair('longitude', _door['longitude']));
                  return [];
                }
                return [
                  {..._park, 'name': '公园南门', 'address': '红荔路入口'},
                ];
              case 'forwardGeocode':
                return [
                  {..._home, 'formattedAddress': '一号门'},
                  {..._door, 'formattedAddress': '二号门', 'level': '门牌号'},
                ];
              case 'reverseGeocode':
                reversePoints.add({
                  'latitude': args['latitude'],
                  'longitude': args['longitude'],
                });
                if (args['latitude'] == _park['latitude']) {
                  return oldReverse.future;
                }
                return {'formattedAddress': '坐标附近的地址', 'adCode': '440304'};
              default:
                fail('Unexpected search method ${call.method}');
            }
          },
          map: (call) async {
            switch (call.method) {
              case 'getCamera':
                return {..._home, 'zoom': 17.25};
              case 'moveCamera':
                moves.add(call.arguments as Map);
              case 'updateCircles':
                final args = call.arguments as Map;
                expect(args['remove'], isEmpty);
                circles.add((args['upsert'] as List).single as Map);
            }
            return null;
          },
        );
        await _tap(tester, '搜地点');
        await _tap(tester, '按关键词搜索');
        await _tap(tester, '公园南门'); // A mappable result does not need a POI ID.
        expect(moves.single, {..._park, 'zoom': 17.25, 'animated': false});
        expect(find.text('选点 22.550100, 114.054000'), findsOneWidget);
        expect(find.text('公园南门'), findsOneWidget);
        expect(find.text('地址：红荔路入口'), findsOneWidget);

        await _tap(tester, '地址查坐标');
        await _tap(tester, '查询坐标');
        await _tap(tester, '二号门');
        expect(moves.last, {..._door, 'zoom': 17.25, 'animated': false});
        expect(find.text('公园南门'), findsNothing);
        oldReverse.complete({'formattedAddress': '上一个选点', 'adCode': 'stale'});
        await tester.pumpAndSettle();
        expect(find.text('地址：二号门'), findsOneWidget);
        expect(find.textContaining('行政区 440304'), findsOneWidget);
        expect(find.textContaining('stale'), findsNothing);

        await _tap(tester, '搜地点');
        await _tap(tester, '查选点周边');
        expect(find.text('周边搜索无结果'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(moves, hasLength(2));
        await _idle(tester, AMapCameraReason.userZoom, _park);
        await _tap(tester, '程序回中');
        await _idle(tester, AMapCameraReason.programmatic, _home);
        expect(find.text('地图中心 22.543100, 114.057900'), findsOneWidget);
        expect(find.text('选点 22.541700, 114.062000'), findsOneWidget);
        expect(find.text('地址：二号门'), findsOneWidget);
        expect(moves.last, {..._home, 'zoom': 16.0, 'animated': true});
        expect(reversePoints, [_home, _park, _door]);
        expect(
          circles.map((c) => c['latitude']),
          fence
              ? [_home['latitude'], _park['latitude'], _door['latitude']]
              : isEmpty,
        );
        if (fence) {
          expect(
            circles.every(
              (c) => c['id'] == 'fence' && c['radiusMeters'] == 150,
            ),
            isTrue,
          );
          expect(circles.last['longitude'], _door['longitude']);
        }
      },
    );
  }

  testWidgets(
    'selecting the same coordinate updates the card without an idle event',
    (tester) async {
      var moveCount = 0;
      var reverseCount = 0;
      await _openMap(
        tester,
        search: (call) async {
          if (call.method == 'forwardGeocode') {
            return [
              {..._home, 'formattedAddress': '同坐标的门牌'},
              _home,
            ];
          }
          expect(call.method, 'reverseGeocode');
          reverseCount++;
          return {'formattedAddress': '逆查地址 $reverseCount'};
        },
        map: (call) async {
          if (call.method == 'getCamera') return {..._home, 'zoom': 16.0};
          if (call.method == 'moveCamera') moveCount++;
          return null;
        },
      );
      for (final candidate in ['同坐标的门牌', '未提供格式化地址']) {
        await _tap(tester, '地址查坐标');
        await _tap(tester, '查询坐标');
        await _tap(tester, candidate);
        expect(find.text('选点 22.543100, 114.057900'), findsOneWidget);
        final expected = candidate == '同坐标的门牌' ? candidate : '逆查地址 3';
        expect(find.text('地址：$expected'), findsOneWidget);
      }
      expect(moveCount, 2);
      expect(reverseCount, 3);
    },
  );

  testWidgets(
    'text-only hints need a result, mappable hints fill a missing address and a rejected move preserves the point',
    (tester) async {
      final reverse = <double>[];
      var rejectMove = false;
      var moves = 0;
      await _openMap(
        tester,
        search: (call) async {
          final args = call.arguments as Map;
          switch (call.method) {
            case 'inputTips':
              return [
                {'name': '文字建议'},
                {..._park, 'name': '有坐标的提示'},
              ];
            case 'searchPoiPage':
              expect(args['keyword'], '文字建议');
              return [
                {..._door, 'name': '搜索结果', 'address': '另一处'},
              ];
            case 'reverseGeocode':
              reverse.add(args['latitude'] as double);
              return {'formattedAddress': '反查到的街道'};
            default:
              fail('Unexpected search method ${call.method}');
          }
        },
        map: (call) async {
          if (call.method == 'getCamera') return {..._home, 'zoom': 16.5};
          if (call.method == 'moveCamera') {
            moves++;
            if (rejectMove) throw PlatformException(code: 'map_not_ready');
          }
          return null;
        },
      );
      Future<void> hints() async {
        await _tap(tester, '搜地点');
        await tester.enterText(find.byType(TextField), '地点');
        await tester.pump(const Duration(milliseconds: 310));
        await tester.pumpAndSettle();
      }

      await hints();
      await _tap(tester, '有坐标的提示');
      expect(moves, 1);
      expect(find.text('地址：反查到的街道'), findsOneWidget);
      expect(find.text('有坐标的提示'), findsOneWidget);
      rejectMove = true;
      await hints();
      await _tap(tester, '文字建议');
      expect(moves, 1);
      await _tap(tester, '搜索结果');
      expect(moves, 2);
      expect(find.text('地图移动失败：map_not_ready'), findsOneWidget);
      expect(find.text('选点 22.550100, 114.054000'), findsOneWidget);
      expect(find.text('有坐标的提示'), findsOneWidget);
      expect(reverse, [_home['latitude'], _park['latitude']]);
    },
  );

  testWidgets(
    'a later drag wins over a pending camera read and reverse failure keeps the chosen address',
    (tester) async {
      final read = Completer<Map>();
      var waitForRead = true;
      var reads = 0;
      var moves = 0;
      await _openMap(
        tester,
        search: (call) async {
          if (call.method == 'forwardGeocode') {
            return [
              {..._door, 'formattedAddress': '选中的门牌'},
            ];
          }
          expect(call.method, 'reverseGeocode');
          if ((call.arguments as Map)['latitude'] == _door['latitude']) {
            throw PlatformException(code: 'geocode_failed');
          }
          return {'formattedAddress': '拖动后地址'};
        },
        map: (call) async {
          if (call.method == 'getCamera') {
            reads++;
            return waitForRead ? read.future : {..._home, 'zoom': 16.0};
          }
          if (call.method == 'moveCamera') moves++;
          return null;
        },
      );
      Future<void> pick() async {
        await _tap(tester, '地址查坐标');
        await _tap(tester, '查询坐标');
        await _tap(tester, '选中的门牌');
      }

      await pick();
      expect(reads, 1);
      await _idle(tester, AMapCameraReason.userDrag, _park);
      read.complete({..._home, 'zoom': 16.0});
      await tester.pumpAndSettle();
      expect(moves, 0);
      expect(find.text('选点 22.550100, 114.054000'), findsOneWidget);
      waitForRead = false;
      await pick();
      expect(find.text('地址：选中的门牌'), findsOneWidget);
      expect(find.text('附近信息查询失败：geocode_failed'), findsOneWidget);
      expect(moves, 1);
      await _idle(tester, AMapCameraReason.userDrag, _home);
      expect(find.text('地址：拖动后地址'), findsOneWidget);
      expect(find.text('地址：选中的门牌'), findsNothing);
    },
  );
}
