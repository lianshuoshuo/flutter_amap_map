import 'dart:async';

import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const place = {
    'id': 'B-test',
    'name': '市民中心',
    'latitude': 22.5431,
    'longitude': 114.0579,
    'address': '福中三路',
    'category': '政府机构',
    'categoryCode': '130100',
    'province': '广东省',
    'city': '深圳市',
    'district': '福田区',
    'adCode': '440304',
    'telephone': ' 服务电话 ',
  };
  Matcher code(String expected) =>
      isA<PlatformException>().having((e) => e.code, 'code', expected);
  void mock(Future<Object?> Function(MethodCall) handler) =>
      messenger.setMockMethodCallHandler(amapSdkChannel, handler);
  tearDown(() => messenger.setMockMethodCallHandler(amapSdkChannel, null));

  test('requests exactly one POI ID and decodes the matching detail', () async {
    mock((call) async {
      expect(call.method, 'poiById');
      expect(call.arguments, {'id': 'B-test'});
      return [place];
    });
    final poi = (await AMapPoiSearch.getById(' B-test '))!;
    expect(
      [poi.id, poi.name, poi.address, poi.category, poi.categoryCode],
      ['B-test', '市民中心', '福中三路', '政府机构', '130100'],
    );
    expect(
      [poi.province, poi.city, poi.district, poi.adCode, poi.telephone],
      ['广东省', '深圳市', '福田区', '440304', '服务电话'],
    );
    expect(
      (poi.coordinate.latitude, poi.coordinate.longitude),
      (22.5431, 114.0579),
    );
  });

  test(
    'separates a missing POI from a corrupt detail or service error',
    () async {
      mock((_) async => []);
      expect(await AMapPoiSearch.getById('B-test'), isNull);
      mock(
        (_) async =>
            throw PlatformException(code: 'poi_search_failed', details: 2001),
      );
      expect(await AMapPoiSearch.getById('B-test'), isNull);
      for (final bad in [
        null,
        {},
        [null],
        [place, place],
        [
          {...place, 'id': 'another'},
        ],
        [
          {...place, 'id': null},
        ],
        [
          {...place, 'name': ' '},
        ],
        [
          {...place, 'longitude': 181},
        ],
      ]) {
        mock((_) async => bad);
        await expectLater(
          AMapPoiSearch.getById('B-test'),
          throwsA(code('poi_search_failed')),
        );
      }
      mock(
        (_) async =>
            throw PlatformException(code: 'poi_search_failed', details: 1002),
      );
      await expectLater(
        AMapPoiSearch.getById('B-test'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.details,
            'native code',
            1002,
          ),
        ),
      );
    },
  );

  test(
    'returns geocoding candidates in native order with their original GCJ-02 and match level',
    () async {
      mock((call) async {
        expect(call.method, 'forwardGeocode');
        expect(call.arguments, {'address': '福中三路2010号', 'city': '深圳'});
        return [
          {
            'latitude': 22.54,
            'longitude': 114.06,
            'formattedAddress': ' 深圳市福田区福中三路2010号 ',
            'level': '门牌号',
            'city': '深圳市',
            'district': '福田区',
            'adCode': '440304',
          },
          {'latitude': 91, 'longitude': 114},
          {'latitude': 22.55, 'longitude': 114.05},
        ];
      });
      final results = await AMapGeocoder.forwardGeocode(
        ' 福中三路2010号 ',
        city: ' 深圳 ',
      );
      expect(
        results.map((r) => (r.coordinate.latitude, r.coordinate.longitude)),
        [(22.54, 114.06), (22.55, 114.05)],
      );
      expect(results.first.formattedAddress, '深圳市福田区福中三路2010号');
      expect(results.first.level, '门牌号');
      expect(results.first.administrativeArea.adCode, '440304');
      expect(results.first.administrativeArea.district, '福田区');
      expect(results.last.formattedAddress, isNull);
      expect(results.last.level, isNull);
      expect(results.clear, throwsUnsupportedError);
    },
  );

  test(
    'separates an empty geocoding result from missing or invalid native data',
    () async {
      mock((call) async {
        expect(call.arguments, {'address': '福中三路'});
        return [];
      });
      expect(await AMapGeocoder.forwardGeocode('福中三路', city: ' '), isEmpty);
      for (final bad in [
        null,
        {},
        [null],
        [
          {'latitude': 0},
        ],
        [
          {'latitude': double.nan, 'longitude': 0},
        ],
      ]) {
        mock((_) async => bad);
        await expectLater(
          AMapGeocoder.forwardGeocode('福中三路'),
          throwsA(code('geocode_failed')),
        );
      }
      mock(
        (_) async =>
            throw PlatformException(code: 'geocode_failed', details: 2001),
      );
      await expectLater(
        AMapGeocoder.forwardGeocode('福中三路'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.details,
            'native code',
            2001,
          ),
        ),
      );
    },
  );

  test(
    'rejects empty addresses and non-single POI IDs and reports unsupported platforms',
    () async {
      mock((_) async => fail('Unexpected native call'));
      await expectLater(AMapGeocoder.forwardGeocode(' '), throwsArgumentError);
      for (final id in [' ', 'B1|B2']) {
        await expectLater(AMapPoiSearch.getById(id), throwsArgumentError);
      }
      messenger.setMockMethodCallHandler(amapSdkChannel, null);
      await expectLater(
        AMapPoiSearch.getById('B1'),
        throwsA(code('unsupported_feature')),
      );
      await expectLater(
        AMapGeocoder.forwardGeocode('福田'),
        throwsA(code('unsupported_feature')),
      );
    },
  );

  testWidgets('reports independent timeouts for both lookup methods', (
    tester,
  ) async {
    final reply = Completer<Object?>();
    mock((_) => reply.future);
    final detail = expectLater(
      AMapPoiSearch.getById('B1'),
      throwsA(code('poi_search_timeout')),
    );
    final address = expectLater(
      AMapGeocoder.forwardGeocode('福田'),
      throwsA(code('geocode_timeout')),
    );
    await tester.pump(const Duration(seconds: 16));
    await Future.wait([detail, address]);
    reply.complete([]);
    await tester.pump();
  });
}
