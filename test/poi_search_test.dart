import 'dart:async';

import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const center = AMapLatLng(22.5431, 114.0579);

  tearDown(() => messenger.setMockMethodCallHandler(amapSdkChannel, null));

  test(
    'trims keywords and decodes mappable POIs with optional metadata',
    () async {
      messenger.setMockMethodCallHandler(amapSdkChannel, (call) async {
        expect(call.method, 'searchPoi');
        expect(call.arguments, {'keyword': '市民中心'});
        return [
          {
            'id': 'poi-1',
            'name': ' 深圳市民中心 ',
            'address': '福中三路',
            'category': '政府机构',
            'categoryCode': '130100',
            'latitude': 22.5431,
            'longitude': 114.0579,
          },
          {'name': '缺少坐标的地点'},
          {'name': '错误坐标', 'latitude': 22.54, 'longitude': 181},
          {'name': ' ', 'latitude': 22.54, 'longitude': 114.05},
          {'name': '街心公园', 'latitude': 22, 'longitude': 114},
        ];
      });
      final places = await AMapPoiSearch.searchKeyword(' 市民中心 ');
      expect(places.map((poi) => poi.name), ['深圳市民中心', '街心公园']);
      final first = places.first;
      expect(first.id, 'poi-1');
      expect(first.address, '福中三路');
      expect(first.category, '政府机构');
      expect(first.categoryCode, '130100');
      expect(first.coordinate.latitude, center.latitude);
      expect(first.coordinate.longitude, center.longitude);
      expect(places.last.address, isNull);
      expect(places.last.category, isNull);
      expect(places.clear, throwsUnsupportedError);
    },
  );

  test('sends the GCJ-02 center and allows nearby without a keyword', () async {
    final args = <Object?>[];
    messenger.setMockMethodCallHandler(amapSdkChannel, (call) async {
      expect(call.method, 'searchPoi');
      args.add(call.arguments);
      return [];
    });
    expect(await AMapPoiSearch.searchNearby(center), isEmpty);
    expect(
      await AMapPoiSearch.searchNearby(
        center,
        radiusMeters: 500,
        keyword: ' 公园 ',
      ),
      isEmpty,
    );
    expect(args, [
      {
        'keyword': '',
        'latitude': 22.5431,
        'longitude': 114.0579,
        'radiusMeters': 1000,
      },
      {
        'keyword': '公园',
        'latitude': 22.5431,
        'longitude': 114.0579,
        'radiusMeters': 500,
      },
    ]);
  });

  test('rejects bad inputs before invoking native search', () async {
    messenger.setMockMethodCallHandler(amapSdkChannel, (_) async {
      fail('Invalid input reached the native search');
    });
    await expectLater(AMapPoiSearch.searchKeyword(' '), throwsArgumentError);
    await expectLater(
      AMapPoiSearch.searchNearby(const AMapLatLng(double.nan, 114)),
      throwsArgumentError,
    );
    await expectLater(
      AMapPoiSearch.searchNearby(const AMapLatLng(22, -181)),
      throwsArgumentError,
    );
    for (final radius in [0, 50001]) {
      await expectLater(
        AMapPoiSearch.searchNearby(center, radiusMeters: radius),
        throwsArgumentError,
      );
    }
    for (final page in [0, 101]) {
      await expectLater(
        AMapPoiSearch.searchKeyword('公园', page: page),
        throwsRangeError,
      );
    }
    for (final size in [0, 26]) {
      await expectLater(
        AMapPoiSearch.searchNearby(center, pageSize: size),
        throwsRangeError,
      );
    }
    for (final code in ['餐饮', '50', '050000|060000']) {
      await expectLater(
        AMapPoiSearch.searchKeyword('餐厅', categoryCode: code),
        throwsArgumentError,
      );
      await expectLater(
        AMapPoiSearch.inputTips('餐厅', categoryCode: code),
        throwsArgumentError,
      );
    }
    await expectLater(AMapPoiSearch.inputTips(' '), throwsArgumentError);
  });

  test(
    'sends one-based pages, city restriction and six-digit category to native search',
    () async {
      final calls = <Object?>[];
      messenger.setMockMethodCallHandler(amapSdkChannel, (call) async {
        expect(call.method, 'searchPoiPage');
        calls.add(call.arguments);
        return [];
      });
      await AMapPoiSearch.searchKeyword(
        ' 公园 ',
        city: ' 深圳 ',
        categoryCode: ' 110000 ',
        page: 2,
        pageSize: 5,
      );
      await AMapPoiSearch.searchNearby(
        center,
        page: 100,
        pageSize: 25,
        categoryCode: '050000',
      );
      await AMapPoiSearch.searchKeyword(
        '公园',
        city: ' ',
        categoryCode: ' ',
        pageSize: 1,
      );
      expect(calls, [
        {
          'keyword': '公园',
          'city': '深圳',
          'categoryCode': '110000',
          'page': 2,
          'pageSize': 5,
        },
        {
          'keyword': '',
          'latitude': 22.5431,
          'longitude': 114.0579,
          'radiusMeters': 1000,
          'categoryCode': '050000',
          'page': 100,
          'pageSize': 25,
        },
        {'keyword': '公园', 'pageSize': 1},
      ]);
    },
  );

  test(
    'reports unsupported advanced search when the native bridge only knows the default first page',
    () async {
      messenger.setMockMethodCallHandler(amapSdkChannel, (call) async {
        if (call.method == 'searchPoi') return [];
        throw MissingPluginException();
      });
      expect(await AMapPoiSearch.searchKeyword('公园'), isEmpty);
      for (final request in [
        () => AMapPoiSearch.searchKeyword('公园', city: '深圳'),
        () => AMapPoiSearch.searchNearby(center, page: 2),
      ]) {
        await expectLater(
          request(),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'unsupported_feature',
            ),
          ),
        );
      }
    },
  );

  test(
    'keeps named text-only tips and preserves the GCJ-02 coordinates and order from the SDK',
    () async {
      messenger.setMockMethodCallHandler(amapSdkChannel, (call) async {
        expect(call.method, 'inputTips');
        expect(call.arguments, {
          'keyword': '市民',
          'city': '深圳',
          'categoryCode': '130000',
        });
        return [
          {'name': ' 市民 ', 'id': ' '},
          {
            'name': '市民中心',
            'id': 'id-1',
            'district': '深圳市福田区',
            'adCode': '440304',
            'address': '福中三路',
            'categoryCode': '130100',
            'latitude': 22.5431,
            'longitude': 114.0579,
          },
          {'name': '无法定位的建议', 'latitude': 91.0, 'longitude': 114.0},
          {'name': ' '},
        ];
      });
      final tips = await AMapPoiSearch.inputTips(
        ' 市民 ',
        city: ' 深圳 ',
        categoryCode: '130000',
      );
      expect(tips.map((t) => t.name), ['市民', '市民中心', '无法定位的建议']);
      expect(tips.first.coordinate, isNull);
      expect(tips.first.id, isNull);
      expect(tips.last.coordinate, isNull);
      final tip = tips[1];
      expect(
        [tip.id, tip.district, tip.adCode, tip.address, tip.categoryCode],
        ['id-1', '深圳市福田区', '440304', '福中三路', '130100'],
      );
      expect(
        [tip.coordinate!.latitude, tip.coordinate!.longitude],
        [center.latitude, center.longitude],
      );
      expect(tips.clear, throwsUnsupportedError);
    },
  );

  test(
    'distinguishes empty input tips from a missing native result and service failure',
    () async {
      messenger.setMockMethodCallHandler(amapSdkChannel, (_) async => []);
      expect(await AMapPoiSearch.inputTips('空'), isEmpty);
      messenger.setMockMethodCallHandler(amapSdkChannel, (_) async => null);
      await expectLater(
        AMapPoiSearch.inputTips('空'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'poi_search_failed',
          ),
        ),
      );
      messenger.setMockMethodCallHandler(amapSdkChannel, (_) async {
        throw PlatformException(code: 'poi_search_failed', details: 1002);
      });
      await expectLater(
        AMapPoiSearch.inputTips('空'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.details,
            'native code',
            1002,
          ),
        ),
      );
      messenger.setMockMethodCallHandler(amapSdkChannel, null);
      await expectLater(
        AMapPoiSearch.inputTips('空'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'unsupported_feature',
          ),
        ),
      );
    },
  );

  test(
    'distinguishes missing data, native errors and unsupported platform',
    () async {
      Future<void> expectCode(String code) => expectLater(
        AMapPoiSearch.searchNearby(center),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
      );
      messenger.setMockMethodCallHandler(amapSdkChannel, (_) async => null);
      await expectCode('poi_search_failed');

      for (final code in ['sdk_not_initialized', 'poi_search_failed']) {
        messenger.setMockMethodCallHandler(amapSdkChannel, (_) async {
          throw PlatformException(code: code, details: 1002);
        });
        await expectCode(code);
      }
      messenger.setMockMethodCallHandler(amapSdkChannel, null);
      await expectCode('unsupported_feature');
    },
  );

  testWidgets('times out when native search never replies', (tester) async {
    final reply = Completer<List<Object?>>();
    messenger.setMockMethodCallHandler(amapSdkChannel, (_) => reply.future);
    final lookup = expectLater(
      AMapPoiSearch.searchNearby(center),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'poi_search_timeout',
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 16));
    reply.complete([]);
    await tester.pump();
    await lookup;
  });
}
