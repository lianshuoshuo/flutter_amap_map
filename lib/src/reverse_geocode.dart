import 'dart:async';

import 'package:flutter/services.dart';

import 'amap.dart';

/// Address lookup through the platform's native AMap Search SDK.
abstract final class AMapGeocoder {
  /// Returns GCJ-02 candidates for an [address] in the SDK's result order.
  /// [city] can disambiguate the address. An empty list means no match.
  static Future<List<AMapGeocodeCandidate>> forwardGeocode(
    String address, {
    String? city,
  }) async {
    final query = address.trim();
    if (query.isEmpty) {
      throw ArgumentError.value(
        address,
        'address',
        'Expected a non-blank address',
      );
    }
    final Object? data;
    try {
      data = await amapSdkChannel
          .invokeMethod<Object?>('forwardGeocode', {
            'address': query,
            'city': ?_text(city),
          })
          .timeout(const Duration(seconds: 16));
    } on TimeoutException {
      throw PlatformException(code: 'geocode_timeout');
    } on MissingPluginException {
      throw PlatformException(code: 'unsupported_feature');
    }
    if (data is! List<Object?>) throw PlatformException(code: 'geocode_failed');
    final candidates = <AMapGeocodeCandidate>[];
    for (final item in data.whereType<Map<Object?, Object?>>()) {
      final point = _coordinate(item['latitude'], item['longitude']);
      if (point != null) candidates.add(AMapGeocodeCandidate._(point, item));
    }
    if (data.isNotEmpty && candidates.isEmpty) {
      throw PlatformException(code: 'geocode_failed');
    }
    return List.unmodifiable(candidates);
  }

  /// Looks up a GCJ-02 coordinate after [AMapSdk.initialize] succeeds.
  ///
  /// [radiusMeters] is the SDK search radius (1–3000 m). The returned
  /// candidates and their order are provided by AMap.
  static Future<AMapReverseGeocodeResult> reverseGeocode(
    AMapLatLng coordinate, {
    int radiusMeters = 200,
  }) async {
    if (_coordinate(coordinate.latitude, coordinate.longitude) == null) {
      throw ArgumentError('Invalid GCJ-02 coordinate');
    }
    if (radiusMeters < 1 || radiusMeters > 3000) {
      throw ArgumentError.value(
        radiusMeters,
        'radiusMeters',
        'Expected 1–3000 m',
      );
    }
    final Map<Object?, Object?>? data;
    try {
      data = await amapSdkChannel
          .invokeMapMethod<Object?, Object?>('reverseGeocode', {
            'latitude': coordinate.latitude,
            'longitude': coordinate.longitude,
            'radiusMeters': radiusMeters,
          })
          .timeout(const Duration(seconds: 16));
    } on TimeoutException {
      throw PlatformException(code: 'geocode_timeout');
    } on MissingPluginException {
      throw PlatformException(code: 'unsupported_feature');
    }
    final address = _text(data?['formattedAddress']);
    if (data == null || address == null) {
      throw PlatformException(code: 'geocode_no_result');
    }
    return AMapReverseGeocodeResult._(address, data);
  }
}

/// A forward-geocoded position and the address information returned by AMap.
final class AMapGeocodeCandidate {
  AMapGeocodeCandidate._(this.coordinate, Map<Object?, Object?> data)
    : formattedAddress = _text(data['formattedAddress']),
      level = _text(data['level']),
      administrativeArea = AMapAdministrativeArea._(data);

  final AMapLatLng coordinate;
  final String? formattedAddress;

  /// SDK match level, such as a street number or an administrative area.
  final String? level;
  final AMapAdministrativeArea administrativeArea;
}

/// Structured address and nearby candidates returned by AMap.
final class AMapReverseGeocodeResult {
  AMapReverseGeocodeResult._(this.formattedAddress, Map<Object?, Object?> data)
    : administrativeArea = AMapAdministrativeArea._(data),
      pois = List.unmodifiable(_items(data['pois']).map(AMapNearbyPoi._)),
      aois = List.unmodifiable(_items(data['aois']).map(AMapNearbyAoi._));

  final String formattedAddress;
  final AMapAdministrativeArea administrativeArea;
  final List<AMapNearbyPoi> pois;
  final List<AMapNearbyAoi> aois;
}

/// Administrative names and codes available at the queried coordinate.
final class AMapAdministrativeArea {
  AMapAdministrativeArea._(Map<Object?, Object?> data)
    : country = _text(data['country']),
      province = _text(data['province']),
      city = _text(data['city']),
      cityCode = _text(data['cityCode']),
      district = _text(data['district']),
      adCode = _text(data['adCode']),
      township = _text(data['township']),
      townCode = _text(data['townCode']),
      neighborhood = _text(data['neighborhood']),
      building = _text(data['building']);

  final String? country,
      province,
      city,
      cityCode,
      district,
      adCode,
      township,
      townCode,
      neighborhood,
      building;
}

/// A nearby point of interest returned by a reverse geocode query.
final class AMapNearbyPoi {
  AMapNearbyPoi._(Map<Object?, Object?> data)
    : id = _text(data['id']),
      name = _text(data['name']),
      type = _text(data['type']),
      address = _text(data['address']),
      coordinate = _coordinate(data['latitude'], data['longitude']),
      distanceMeters = _nonnegative(data['distanceMeters']);

  final String? id, name, type, address;
  final AMapLatLng? coordinate;
  final double? distanceMeters;
}

/// A nearby area of interest, with optional GCJ-02 center and area in m².
final class AMapNearbyAoi {
  AMapNearbyAoi._(Map<Object?, Object?> data)
    : id = _text(data['id']),
      name = _text(data['name']),
      type = _text(data['type']),
      adCode = _text(data['adCode']),
      center = _coordinate(data['latitude'], data['longitude']),
      distanceMeters = _nonnegative(data['distanceMeters']),
      areaSquareMeters = _nonnegative(data['areaSquareMeters']);

  final String? id, name, type, adCode;
  final AMapLatLng? center;

  /// The SDK reports zero when the query point is in the AOI.
  final double? distanceMeters;
  final double? areaSquareMeters;
}

Iterable<Map<Object?, Object?>> _items(Object? value) =>
    value is List ? value.whereType<Map<Object?, Object?>>() : const [];

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double? _nonnegative(Object? value) =>
    value is num && value.isFinite && value >= 0 ? value.toDouble() : null;

AMapLatLng? _coordinate(Object? latitude, Object? longitude) {
  if (latitude is! num ||
      longitude is! num ||
      !latitude.isFinite ||
      !longitude.isFinite ||
      latitude.abs() > 90 ||
      longitude.abs() > 180) {
    return null;
  }
  return AMapLatLng(latitude.toDouble(), longitude.toDouble());
}
