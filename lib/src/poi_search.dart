import 'dart:async';

import 'package:flutter/services.dart';

import 'amap.dart';

/// Standalone place search using the native AMap Search SDK.
abstract final class AMapPoiSearch {
  /// Searches places matching [keyword], restricted to [city] when supplied.
  static Future<List<AMapPoi>> searchKeyword(
    String keyword, {
    String? city,
    String? categoryCode,
    int page = 1,
    int pageSize = 20,
  }) async {
    final query = keyword.trim();
    if (query.isEmpty) throw ArgumentError('A POI keyword is required');
    return _search({
      'keyword': query,
      ..._filters(city, categoryCode),
      ..._paging(page, pageSize),
    });
  }

  /// Searches near a GCJ-02 [center]. The optional keyword narrows the results.
  /// The search radius must be in the range 1–50000 meters.
  static Future<List<AMapPoi>> searchNearby(
    AMapLatLng center, {
    int radiusMeters = 1000,
    String? keyword,
    String? categoryCode,
    int page = 1,
    int pageSize = 20,
  }) async {
    if (_coordinate(center.latitude, center.longitude) == null) {
      throw ArgumentError('Invalid GCJ-02 coordinate');
    }
    if (radiusMeters < 1 || radiusMeters > 50000) {
      throw ArgumentError('POI radius must be between 1 and 50000 meters');
    }
    return _search({
      'keyword': keyword?.trim() ?? '',
      'latitude': center.latitude,
      'longitude': center.longitude,
      'radiusMeters': radiusMeters,
      ..._filters(null, categoryCode),
      ..._paging(page, pageSize),
    });
  }

  /// Returns native input suggestions, including names without a map position.
  static Future<List<AMapInputTip>> inputTips(
    String keyword, {
    String? city,
    String? categoryCode,
  }) async {
    final query = keyword.trim();
    if (query.isEmpty) throw ArgumentError('A suggestion keyword is required');
    final data = await _request('inputTips', {
      'keyword': query,
      ..._filters(city, categoryCode),
    });
    final tips = <AMapInputTip>[];
    for (final item in data.whereType<Map<Object?, Object?>>()) {
      final name = _text(item['name']);
      if (name == null) continue;
      tips.add(
        AMapInputTip._(
          name: name,
          id: _text(item['id']),
          district: _text(item['district']),
          adCode: _text(item['adCode']),
          address: _text(item['address']),
          categoryCode: _text(item['categoryCode']),
          coordinate: _coordinate(item['latitude'], item['longitude']),
        ),
      );
    }
    return List.unmodifiable(tips);
  }

  /// Looks up one opaque POI [id]. Returns null when AMap finds no such ID.
  static Future<AMapPoi?> getById(String id) async {
    final query = id.trim();
    if (query.isEmpty || query.contains('|')) {
      throw ArgumentError.value(id, 'id', 'Expected one non-blank POI ID');
    }
    final List<Object?> data;
    try {
      data = await _request('poiById', {'id': query});
    } on PlatformException catch (error) {
      // All three pinned Search SDKs also report "ID does not exist" as 2001.
      if (error.code == 'poi_search_failed' && error.details == 2001) {
        return null;
      }
      rethrow;
    }
    if (data.isEmpty) return null;
    final item = data.length == 1 ? data.single : null;
    final poi = item is Map ? AMapPoi._decode(item) : null;
    if (poi == null || poi.id != query) {
      throw PlatformException(code: 'poi_search_failed');
    }
    return poi;
  }

  static Map<String, Object> _paging(int page, int pageSize) {
    RangeError.checkValueInInterval(page, 1, 100, 'page');
    RangeError.checkValueInInterval(pageSize, 1, 25, 'pageSize');
    return {
      if (page != 1) 'page': page,
      if (pageSize != 20) 'pageSize': pageSize,
    };
  }

  static Map<String, Object> _filters(String? city, String? categoryCode) {
    final code = _text(categoryCode);
    if (code != null && !RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      throw ArgumentError.value(
        categoryCode,
        'categoryCode',
        'Expected six digits',
      );
    }
    return {'city': ?_text(city), 'categoryCode': ?code};
  }

  static Future<List<Object?>> _request(
    String method,
    Map<String, Object> args,
  ) async {
    final Object? data;
    try {
      data = await amapSdkChannel
          .invokeMethod<Object?>(method, args)
          .timeout(const Duration(seconds: 16));
    } on TimeoutException {
      throw PlatformException(code: 'poi_search_timeout');
    } on MissingPluginException {
      throw PlatformException(code: 'unsupported_feature');
    }
    if (data is! List<Object?>) {
      throw PlatformException(code: 'poi_search_failed');
    }
    return data;
  }

  static Future<List<AMapPoi>> _search(Map<String, Object> args) async {
    // Older native bridges ignore unknown options on the first-page method.
    final extended = const [
      'page',
      'pageSize',
      'city',
      'categoryCode',
    ].any(args.containsKey);
    final data = await _request(extended ? 'searchPoiPage' : 'searchPoi', args);
    return List.unmodifiable(
      data.whereType<Map<Object?, Object?>>().map(AMapPoi._decode).nonNulls,
    );
  }
}

/// An input suggestion. Some suggestions contain only text.
final class AMapInputTip {
  const AMapInputTip._({
    required this.name,
    this.id,
    this.district,
    this.adCode,
    this.address,
    this.categoryCode,
    this.coordinate,
  });

  final String name;
  final String? id;
  final String? district;
  final String? adCode;
  final String? address;
  final String? categoryCode;
  final AMapLatLng? coordinate;
}

/// A named, mappable place. Metadata is nullable when omitted by AMap.
final class AMapPoi {
  const AMapPoi._({
    required this.name,
    required this.coordinate,
    this.id,
    this.address,
    this.category,
    this.categoryCode,
    this.province,
    this.city,
    this.district,
    this.adCode,
    this.telephone,
  });

  final String name;
  final AMapLatLng coordinate;
  final String? id;
  final String? address;
  final String? category;
  final String? categoryCode;
  final String? province, city, district, adCode;

  /// Contact information as supplied by the SDK, when available.
  final String? telephone;

  static AMapPoi? _decode(Map<Object?, Object?> item) {
    final name = _text(item['name']);
    final coordinate = _coordinate(item['latitude'], item['longitude']);
    if (name == null || coordinate == null) return null;
    return AMapPoi._(
      name: name,
      coordinate: coordinate,
      id: _text(item['id']),
      address: _text(item['address']),
      category: _text(item['category']),
      categoryCode: _text(item['categoryCode']),
      province: _text(item['province']),
      city: _text(item['city']),
      district: _text(item['district']),
      adCode: _text(item['adCode']),
      telephone: _text(item['telephone']),
    );
  }
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

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
