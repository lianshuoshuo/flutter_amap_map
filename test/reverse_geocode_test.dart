import 'dart:async';

import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const point = AMapLatLng(22.5431, 114.0579);

  tearDown(() => messenger.setMockMethodCallHandler(amapSdkChannel, null));

  test('sends GCJ-02 and decodes administrative area, POIs and AOIs', () async {
    messenger.setMockMethodCallHandler(amapSdkChannel, (call) async {
      expect(call.method, 'reverseGeocode');
      expect(call.arguments, {
        'latitude': point.latitude,
        'longitude': point.longitude,
        'radiusMeters': 50,
      });
      return {
        'formattedAddress': ' 广东省深圳市福田区福中三路 ',
        'province': '广东省',
        'city': '深圳市',
        'district': '福田区',
        'adCode': '440304',
        'pois': [
          {
            'id': 'poi-1',
            'name': '市民中心',
            'address': '福中三路',
            'latitude': 22.54,
            'longitude': 114.05,
            'distanceMeters': 12,
          },
        ],
        'aois': [
          {
            'id': 'aoi-1',
            'name': '市民中心',
            'adCode': '440304',
            'areaSquareMeters': 800.5,
            'distanceMeters': 0,
          },
        ],
      };
    });
    final result = await AMapGeocoder.reverseGeocode(point, radiusMeters: 50);
    expect(result.formattedAddress, '广东省深圳市福田区福中三路');
    expect(result.administrativeArea.district, '福田区');
    expect(result.administrativeArea.adCode, '440304');
    expect(result.pois.single.id, 'poi-1');
    expect(result.pois.single.coordinate?.latitude, 22.54);
    expect(result.pois.single.coordinate?.longitude, 114.05);
    expect(result.pois.single.distanceMeters, 12);
    expect(result.aois.single.adCode, '440304');
    expect(result.aois.single.areaSquareMeters, 800.5);
    expect(result.aois.single.distanceMeters, 0);
    expect(result.aois.clear, throwsUnsupportedError);
  });

  test(
    'accepts absent administrative fields and optional candidates',
    () async {
      messenger.setMockMethodCallHandler(
        amapSdkChannel,
        (_) async => {
          'formattedAddress': '北京市东城区',
          'city': ' ',
          'pois': [
            {
              'name': '地点',
              'distanceMeters': -1,
              'latitude': 91,
              'longitude': 110,
            },
          ],
        },
      );
      final result = await AMapGeocoder.reverseGeocode(point);
      expect(result.administrativeArea.city, isNull);
      expect(result.pois.single.coordinate, isNull);
      expect(result.pois.single.distanceMeters, isNull);
      expect(result.aois, isEmpty);
    },
  );

  testWidgets('times out if native search never replies', (tester) async {
    final reply = Completer<Map<String, Object>>();
    messenger.setMockMethodCallHandler(amapSdkChannel, (_) => reply.future);
    final lookup = expectLater(
      AMapGeocoder.reverseGeocode(point),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'geocode_timeout',
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 16));
    reply.complete({'formattedAddress': '晚到的结果'});
    await tester.pump();
    await lookup;
  });

  test('rejects invalid input before contacting the SDK', () async {
    messenger.setMockMethodCallHandler(amapSdkChannel, (_) async {
      fail('Invalid input reached the method channel');
    });
    await expectLater(
      AMapGeocoder.reverseGeocode(const AMapLatLng(double.nan, 114)),
      throwsArgumentError,
    );
    await expectLater(
      AMapGeocoder.reverseGeocode(const AMapLatLng(22, 181)),
      throwsArgumentError,
    );
    for (final radius in [0, 3001]) {
      await expectLater(
        AMapGeocoder.reverseGeocode(point, radiusMeters: radius),
        throwsArgumentError,
      );
    }
  });

  test(
    'distinguishes empty result, native errors and missing support',
    () async {
      Future<void> expectCode(String code) => expectLater(
        AMapGeocoder.reverseGeocode(point),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
      );
      messenger.setMockMethodCallHandler(amapSdkChannel, (_) async => {});
      await expectCode('geocode_no_result');

      for (final code in ['sdk_not_initialized', 'geocode_failed']) {
        messenger.setMockMethodCallHandler(amapSdkChannel, (_) async {
          throw PlatformException(code: code);
        });
        await expectCode(code);
      }
      messenger.setMockMethodCallHandler(amapSdkChannel, null);
      await expectCode('unsupported_feature');
    },
  );
}
