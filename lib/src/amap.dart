import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Platform-view registration identifier used by platform implementations and tests.
const amapViewType = 'dev.hscw.amap_flutter_bridge/map';

/// Shared method channel used by platform implementations and tests.
const amapSdkChannel = MethodChannel('dev.hscw.amap_flutter_bridge/sdk');

/// Initializes the native AMap SDK using the host application's key and consent.
class AMapSdk {
  /// Returns the platform SDK version after configuration. Map rendering and
  /// search responses are reported separately by the corresponding APIs.
  static Future<String> initialize({
    required String apiKey,
    required bool privacyAgreed,
  }) async {
    if (!privacyAgreed) {
      throw PlatformException(code: 'privacy_not_agreed');
    }
    if (apiKey.trim().isEmpty) {
      throw ArgumentError.value(
        'empty',
        'apiKey',
        'A platform Key is required',
      );
    }
    return (await amapSdkChannel
        .invokeMethod<String>('initialize', {
          'apiKey': apiKey,
          'privacyAgreed': privacyAgreed,
        })
        .timeout(const Duration(seconds: 10)))!;
  }
}

/// GCJ-02 center and zoom shared by all three platforms.
class AMapCameraPosition {
  AMapCameraPosition({
    required this.latitude,
    required this.longitude,
    required this.zoom,
  }) {
    if (!latitude.isFinite ||
        latitude.abs() > 90 ||
        !longitude.isFinite ||
        longitude.abs() > 180 ||
        !zoom.isFinite ||
        zoom < 3 ||
        zoom > 20) {
      throw ArgumentError('Invalid GCJ-02 camera');
    }
  }
  final double latitude;
  final double longitude;
  final double zoom;
  Map<String, Object> toMap() => {
    'latitude': latitude,
    'longitude': longitude,
    'zoom': zoom,
  };
  factory AMapCameraPosition.fromMap(Map<dynamic, dynamic> value) =>
      AMapCameraPosition(
        latitude: (value['latitude'] as num).toDouble(),
        longitude: (value['longitude'] as num).toDouble(),
        zoom: (value['zoom'] as num).toDouble(),
      );
}

/// The cause of a camera change when supported by the available evidence.
enum AMapCameraReason { userDrag, userZoom, programmatic, unknown }

/// Camera position and the best available reason reported for this map instance.
class AMapCameraEvent {
  AMapCameraEvent(this.position, {this.reason = AMapCameraReason.unknown});
  final AMapCameraPosition position;
  final AMapCameraReason reason;

  /// Coarse source retained for callers that only distinguish gesture and API.
  String get source => switch (reason) {
    AMapCameraReason.userDrag || AMapCameraReason.userZoom => 'gesture',
    AMapCameraReason.programmatic => 'api',
    AMapCameraReason.unknown => 'unknown',
  };
}

/// Selects street maps or satellite imagery for one map.
enum AMapType { standard, satellite }

/// Complete runtime configuration applied to one existing native map.
class AMapOptions {
  const AMapOptions({
    this.mapType = AMapType.standard,
    this.minZoom = 3,
    this.maxZoom = 20,
    this.buildingsEnabled = true,
    this.scrollEnabled = true,
    this.zoomEnabled = true,
    this.rotateEnabled = true,
    this.tiltEnabled = true,
    this.inertiaEnabled = true,
    this.compassEnabled = true,
    this.scaleEnabled = true,
    this.zoomControlsEnabled = false,
  });

  final AMapType mapType;

  /// Inclusive zoom limits within 3–20. The SDK can impose a tighter range.
  final double minZoom;
  final double maxZoom;

  /// Shows the SDK's 3D building layer where the basemap provides it.
  final bool buildingsEnabled;
  final bool scrollEnabled;
  final bool zoomEnabled;
  final bool rotateEnabled;
  final bool tiltEnabled;

  /// When false, one finger can pan without camera motion after release.
  final bool inertiaEnabled;
  final bool compassEnabled;
  final bool scaleEnabled;

  /// Native zoom buttons are available on Android and HarmonyOS.
  final bool zoomControlsEnabled;

  Map<String, Object> _toMap() {
    if (!minZoom.isFinite ||
        !maxZoom.isFinite ||
        minZoom < 3 ||
        maxZoom > 20 ||
        minZoom > maxZoom) {
      throw ArgumentError('Expected 3 <= minZoom <= maxZoom <= 20');
    }
    return {
      'mapType': mapType.name,
      'minZoom': minZoom,
      'maxZoom': maxZoom,
      'buildingsEnabled': buildingsEnabled,
      'scrollEnabled': scrollEnabled,
      'zoomEnabled': zoomEnabled,
      'rotateEnabled': rotateEnabled,
      'tiltEnabled': tiltEnabled,
      'inertiaEnabled': inertiaEnabled,
      'compassEnabled': compassEnabled,
      'scaleEnabled': scaleEnabled,
      'zoomControlsEnabled': zoomControlsEnabled,
    };
  }
}

/// Approval numbers returned by the native SDK for the two basemap sources.
/// Either number can be absent when the SDK only supplies the other one.
class AMapApprovalNumbers {
  const AMapApprovalNumbers._(this.mapContent, this.satelliteImage);
  final String? mapContent;
  final String? satelliteImage;
}

/// Bound to one widget instance. Futures acknowledge commands, not animation end.
class AMapController {
  AMapController._(this._channel);
  final MethodChannel _channel;
  final _pending = <Completer<dynamic>>{};
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  /// Whether the widget has released this controller’s native map.
  bool get isDisposed => _disposed;

  Future<T> _invoke<T>(String method, [Object? arguments]) {
    if (_disposed) {
      return Future<T>.error(PlatformException(code: 'map_disposed'));
    }
    final result = Completer<T>();
    _pending.add(result);
    _tail = _tail.then((_) async {
      if (result.isCompleted) return;
      try {
        final value = await _channel
            .invokeMethod<T>(method, arguments)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () =>
                  throw PlatformException(code: 'operation_timeout'),
            );
        if (!result.isCompleted) result.complete(value);
      } catch (error, stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      } finally {
        _pending.remove(result);
      }
    });
    return result.future;
  }

  /// Moves the given GCJ-02 target to [targetScreenPoint], in Flutter logical
  /// pixels from this map's top-left. Omit it to use the viewport center.
  ///
  /// A custom anchor also applies to subsequent gestures until the next
  /// moveCamera without an anchor or a fitBounds command.
  Future<void> moveCamera(
    AMapCameraPosition camera, {
    bool animated = false,
    Offset? targetScreenPoint,
  }) async {
    if (targetScreenPoint != null &&
        (!targetScreenPoint.isFinite ||
            targetScreenPoint.dx < 0 ||
            targetScreenPoint.dy < 0)) {
      throw ArgumentError.value(targetScreenPoint, 'targetScreenPoint');
    }
    await _invoke<void>('moveCamera', {
      ...camera.toMap(),
      'animated': animated,
      if (targetScreenPoint != null)
        'targetScreenPoint': {
          'x': targetScreenPoint.dx,
          'y': targetScreenPoint.dy,
        },
    });
  }

  /// Projects a GCJ-02 point using the current camera. The offset is in
  /// Flutter logical pixels from this map widget's top-left corner.
  ///
  /// An off-screen point can yield an offset outside the widget.
  Future<Offset> projectToScreen(AMapLatLng coordinate) async {
    final latitude = coordinate.latitude;
    final longitude = coordinate.longitude;
    if (!latitude.isFinite ||
        latitude.abs() > 90 ||
        !longitude.isFinite ||
        longitude.abs() > 180) {
      throw ArgumentError('Invalid GCJ-02 coordinate');
    }
    final projected = await _invoke<Map<dynamic, dynamic>?>('projectToScreen', {
      'latitude': latitude,
      'longitude': longitude,
    });
    final x = projected?['x'];
    final y = projected?['y'];
    if (x is! num || y is! num || !x.isFinite || !y.isFinite) {
      throw PlatformException(code: 'projection_failed');
    }
    return Offset(x.toDouble(), y.toDouble());
  }

  /// Returns the GCJ-02 coordinate under a point inside this map widget.
  /// [point] uses Flutter logical pixels measured from its top-left corner.
  Future<AMapLatLng> unprojectFromScreen(Offset point) async {
    if (!point.isFinite || point.dx < 0 || point.dy < 0) {
      throw ArgumentError.value(point, 'point');
    }
    final coordinate = await _invoke<Map<dynamic, dynamic>?>(
      'unprojectFromScreen',
      {'x': point.dx, 'y': point.dy},
    );
    final lat = coordinate?['latitude'];
    final lng = coordinate?['longitude'];
    if (lat is! num ||
        lng is! num ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      throw PlatformException(code: 'projection_failed');
    }
    return AMapLatLng(lat.toDouble(), lng.toDouble());
  }

  /// Fits a geographic rectangle with independent logical-pixel edge insets.
  /// Completes when the native SDK accepts the command.
  Future<void> fitBounds(
    AMapBounds bounds, {
    EdgeInsets padding = EdgeInsets.zero,
    bool animated = false,
  }) async {
    final insets = [padding.left, padding.top, padding.right, padding.bottom];
    if (insets.any((edge) => !edge.isFinite || edge < 0)) {
      throw ArgumentError.value(
        padding,
        'padding',
        'Expected finite non-negative insets',
      );
    }
    await _invoke<void>('fitBounds', {
      ...bounds._toMap(),
      'left': padding.left,
      'top': padding.top,
      'right': padding.right,
      'bottom': padding.bottom,
      'animated': animated,
    });
  }

  /// Reconfigures this map without replacing its view or overlays.
  Future<void> setOptions(AMapOptions options) async {
    await _invoke<void>('setOptions', options._toMap());
  }

  /// Reads the zoom limits reported by this map's native SDK.
  Future<({double minZoom, double maxZoom})> getZoomRange() async {
    final data = await _invoke<Map<dynamic, dynamic>?>('getZoomRange');
    final min = data?['minZoom'];
    final max = data?['maxZoom'];
    if (min is! num ||
        max is! num ||
        !min.isFinite ||
        !max.isFinite ||
        min < 3 ||
        max > 20 ||
        min > max) {
      throw PlatformException(code: 'zoom_range_unavailable');
    }
    return (minZoom: min.toDouble(), maxZoom: max.toDouble());
  }

  /// Reads both SDK approval numbers regardless of the selected map type.
  /// Throws `approval_numbers_unavailable` if neither is available yet.
  Future<AMapApprovalNumbers> getMapApprovalNumbers() async {
    final data = await _invoke<Map<dynamic, dynamic>?>('getMapApprovalNumbers');
    String? number(String key) {
      final value = data?[key];
      if (value is! String || value.trim().isEmpty) return null;
      return value.trim();
    }

    final content = number('mapContent');
    final satellite = number('satelliteImage');
    if (content == null && satellite == null) {
      throw PlatformException(code: 'approval_numbers_unavailable');
    }
    return AMapApprovalNumbers._(content, satellite);
  }

  /// Reads the native camera center in GCJ-02 and its current zoom level.
  Future<AMapCameraPosition> getCamera() async => AMapCameraPosition.fromMap(
    await _invoke<Map<dynamic, dynamic>>('getCamera'),
  );

  void _dispose() {
    _disposed = true;
    for (final request in _pending) {
      if (!request.isCompleted) {
        request.completeError(PlatformException(code: 'map_disposed'));
      }
    }
    _pending.clear();
  }
}

/// Immutable PNG marker. Sizes are logical pixels; coordinates are GCJ-02.
class AMapMarker {
  AMapMarker({
    required this.id,
    required this.latitude,
    required this.longitude,
    required Uint8List pngBytes,
    this.width = 36,
    this.height = 48,
    this.anchorU = 0.5,
    this.anchorV = 1,
    this.rotation = 0,
    this.zIndex = 0,
    this.visible = true,
  }) : pngBytes = Uint8List.fromList(pngBytes).asUnmodifiableView() {
    if (id.isEmpty ||
        !latitude.isFinite ||
        latitude.abs() > 90 ||
        !longitude.isFinite ||
        longitude.abs() > 180 ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0 ||
        width > 512 ||
        height > 512 ||
        !anchorU.isFinite ||
        !anchorV.isFinite ||
        anchorU < 0 ||
        anchorU > 1 ||
        anchorV < 0 ||
        anchorV > 1 ||
        !rotation.isFinite ||
        rotation < 0 ||
        rotation >= 360 ||
        zIndex < -1000000 ||
        zIndex > 1000000 ||
        pngBytes.length < 8 ||
        pngBytes.length > 4 * 1024 * 1024 ||
        !listEquals(pngBytes.sublist(0, 8), [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ])) {
      throw ArgumentError('Invalid marker or PNG header');
    }
  }
  final String id;
  final double latitude, longitude, width, height, anchorU, anchorV, rotation;
  final int zIndex;
  final bool visible;
  final Uint8List pngBytes;
  Map<String, Object> toMap() => {
    'id': id,
    'latitude': latitude,
    'longitude': longitude,
    'pngBytes': pngBytes,
    'width': width,
    'height': height,
    'anchorU': anchorU,
    'anchorV': anchorV,
    'rotation': rotation,
    'zIndex': zIndex,
    'visible': visible,
  };
  bool sameAs(AMapMarker other) =>
      id == other.id &&
      latitude == other.latitude &&
      longitude == other.longitude &&
      width == other.width &&
      height == other.height &&
      anchorU == other.anchorU &&
      anchorV == other.anchorV &&
      rotation == other.rotation &&
      zIndex == other.zIndex &&
      visible == other.visible &&
      listEquals(pngBytes, other.pngBytes);
}

/// A point in GCJ-02 coordinates.
class AMapLatLng {
  const AMapLatLng(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

bool _samePoints(List<AMapLatLng> a, List<AMapLatLng> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].latitude != b[i].latitude || a[i].longitude != b[i].longitude) {
      return false;
    }
  }
  return true;
}

/// A GCJ-02 geographic rectangle that does not cross the antimeridian.
class AMapBounds {
  AMapBounds({required this.southWest, required this.northEast}) {
    if (!_valid(southWest) ||
        !_valid(northEast) ||
        southWest.latitude > northEast.latitude ||
        southWest.longitude > northEast.longitude ||
        northEast.longitude - southWest.longitude > 180) {
      throw ArgumentError(
        'Bounds must be ordered, within the map projection and not cross the antimeridian',
      );
    }
  }

  static const _maxLatitude = 85.05112878;
  final AMapLatLng southWest;
  final AMapLatLng northEast;

  /// Encloses each point. A single point is also valid.
  factory AMapBounds.fromPoints(Iterable<AMapLatLng> points) {
    final iterator = points.iterator;
    if (!iterator.moveNext()) {
      throw ArgumentError('Bounds require at least one point');
    }
    var south = iterator.current.latitude;
    var north = south;
    var west = iterator.current.longitude;
    var east = west;
    while (iterator.moveNext()) {
      final point = iterator.current;
      south = math.min(south, point.latitude);
      north = math.max(north, point.latitude);
      west = math.min(west, point.longitude);
      east = math.max(east, point.longitude);
    }
    return AMapBounds(
      southWest: AMapLatLng(south, west),
      northEast: AMapLatLng(north, east),
    );
  }

  /// Encloses a geographic circle on a sphere with mean Earth radius.
  /// Include the circle's screen-space stroke separately in [EdgeInsets].
  factory AMapBounds.fromCircle(AMapCircle circle) {
    final angular = circle.radiusMeters / 6371008.8;
    final lat = circle.center.latitude * math.pi / 180;
    if (lat.abs() + angular > _maxLatitude * math.pi / 180) {
      throw ArgumentError('Circle extends beyond the map projection');
    }
    final latDelta = angular * 180 / math.pi;
    final lngDelta =
        math.asin(math.sin(angular) / math.cos(lat)) * 180 / math.pi;
    return AMapBounds(
      southWest: AMapLatLng(
        circle.center.latitude - latDelta,
        circle.center.longitude - lngDelta,
      ),
      northEast: AMapLatLng(
        circle.center.latitude + latDelta,
        circle.center.longitude + lngDelta,
      ),
    );
  }

  static bool _valid(AMapLatLng point) =>
      point.latitude.isFinite &&
      point.latitude.abs() <= _maxLatitude &&
      point.longitude.isFinite &&
      point.longitude.abs() <= 180;

  Map<String, double> _toMap() {
    // SDKs need a nonzero extent on both axes, even for a single point.
    (double, double) expand(double low, double high, double limit) {
      const extent = 0.00001;
      if (high - low >= extent) return (low, high);
      final start = ((low + high - extent) / 2).clamp(-limit, limit - extent);
      return (start, start + extent);
    }

    final (south, north) = expand(
      southWest.latitude,
      northEast.latitude,
      _maxLatitude,
    );
    final (west, east) = expand(southWest.longitude, northEast.longitude, 180);
    return {'south': south, 'north': north, 'west': west, 'east': east};
  }
}

/// An immutable solid line connecting [points] in their supplied order.
class AMapPolyline {
  AMapPolyline({
    required this.id,
    required Iterable<AMapLatLng> points,
    this.width = 6,
    this.color = const Color(0xFF1565C0),
  }) : points = List.unmodifiable(points) {
    if (id.isEmpty ||
        this.points.length < 2 ||
        !width.isFinite ||
        width < 1 ||
        width > 128 ||
        this.points.any(
          (point) =>
              !point.latitude.isFinite ||
              point.latitude.abs() > 90 ||
              !point.longitude.isFinite ||
              point.longitude.abs() > 180,
        )) {
      throw ArgumentError('Invalid polyline ID, width or GCJ-02 points');
    }
  }

  final String id;
  final List<AMapLatLng> points;

  /// Stroke width in logical pixels, from 1 to 128.
  final double width;
  final Color color;

  Map<String, Object> _toMap() => {
    'id': id,
    'points': [
      for (final point in points) [point.latitude, point.longitude],
    ],
    'width': width,
    'color': color.toARGB32().toSigned(32),
  };

  bool _sameAs(AMapPolyline other) =>
      width == other.width &&
      color.toARGB32() == other.color.toARGB32() &&
      _samePoints(points, other.points);
}

/// A filled polygon with one automatically closed ring of GCJ-02 vertices.
class AMapPolygon {
  AMapPolygon({
    required this.id,
    required Iterable<AMapLatLng> points,
    this.fillColor = const Color(0x331565C0),
    this.strokeColor = const Color(0xFF1565C0),
    this.strokeWidth = 3,
  }) : points = List.unmodifiable(points) {
    if (id.isEmpty ||
        !strokeWidth.isFinite ||
        strokeWidth < 1 ||
        strokeWidth > 128 ||
        this.points.any(
          (p) =>
              !p.latitude.isFinite ||
              p.latitude.abs() > 90 ||
              !p.longitude.isFinite ||
              p.longitude.abs() > 180,
        ) ||
        this.points.map((p) => (p.latitude, p.longitude)).toSet().length < 3) {
      throw ArgumentError(
        'Expected a polygon ID, valid stroke width and at least three distinct GCJ-02 vertices',
      );
    }
  }

  final String id;
  final List<AMapLatLng> points;
  final Color fillColor;
  final Color strokeColor;

  /// Stroke width in Flutter logical pixels, from 1 to 128.
  final double strokeWidth;

  Map<String, Object> _toMap() => {
    'id': id,
    'points': [
      for (final p in points) [p.latitude, p.longitude],
    ],
    'fillColor': fillColor.toARGB32().toSigned(32),
    'strokeColor': strokeColor.toARGB32().toSigned(32),
    'strokeWidth': strokeWidth,
  };

  bool _sameAs(AMapPolygon other) =>
      strokeWidth == other.strokeWidth &&
      strokeColor.toARGB32() == other.strokeColor.toARGB32() &&
      fillColor.toARGB32() == other.fillColor.toARGB32() &&
      _samePoints(points, other.points);
}

/// A geographic circle centered on a GCJ-02 coordinate.
class AMapCircle {
  AMapCircle({
    required this.id,
    required this.center,
    required this.radiusMeters,
    this.fillColor = const Color(0x331565C0),
    this.strokeColor = const Color(0xFF1565C0),
    this.strokeWidth = 3,
  }) {
    if (id.isEmpty ||
        !center.latitude.isFinite ||
        center.latitude.abs() > 90 ||
        !center.longitude.isFinite ||
        center.longitude.abs() > 180 ||
        !radiusMeters.isFinite ||
        radiusMeters <= 0 ||
        !strokeWidth.isFinite ||
        strokeWidth < 1 ||
        strokeWidth > 128) {
      throw ArgumentError(
        'Invalid circle ID, GCJ-02 center, radius or stroke width',
      );
    }
  }

  final String id;
  final AMapLatLng center;
  final double radiusMeters;
  final Color fillColor;
  final Color strokeColor;

  /// Stroke width in logical pixels, from 1 to 128.
  final double strokeWidth;

  Map<String, Object> _toMap() => {
    'id': id,
    'latitude': center.latitude,
    'longitude': center.longitude,
    'radiusMeters': radiusMeters,
    'fillColor': fillColor.toARGB32().toSigned(32),
    'strokeColor': strokeColor.toARGB32().toSigned(32),
    'strokeWidth': strokeWidth,
  };

  bool _sameAs(AMapCircle other) =>
      center.latitude == other.center.latitude &&
      center.longitude == other.center.longitude &&
      radiusMeters == other.radiusMeters &&
      fillColor.toARGB32() == other.fillColor.toARGB32() &&
      strokeColor.toARGB32() == other.strokeColor.toARGB32() &&
      strokeWidth == other.strokeWidth;
}

/// Native SDK status, not a guarantee that all visible tiles have loaded.
enum AMapStatus { creating, ready, loaded, failed }

/// Factory used by the platform-specific view registration and widget tests.
typedef AMapViewFactory =
    Widget Function(
      Map<String, Object> parameters,
      ValueChanged<int> onCreated,
    );

/// Set once by an OHOS-only entry point before creating map widgets.
AMapViewFactory amapViewFactory = _mobileView;

final _gestures = <Factory<OneSequenceGestureRecognizer>>{
  Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
};

Widget _mobileView(
  Map<String, Object> parameters,
  ValueChanged<int> onCreated,
) {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return AndroidView(
        viewType: amapViewType,
        creationParams: parameters,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: onCreated,
        gestureRecognizers: _gestures,
      );
    case TargetPlatform.iOS:
      return UiKitView(
        viewType: amapViewType,
        creationParams: parameters,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: onCreated,
        gestureRecognizers: _gestures,
      );
    default:
      throw UnsupportedError('Use the OHOS entry point on HarmonyOS.');
  }
}

/// A native map with a per-instance controller and declarative overlays.
///
/// The widget owns and releases its native map. [latitude] and [longitude]
/// use GCJ-02. These coordinates and [zoom] set the initial camera. Use the
/// controller from [onMapCreated] for later moves. A stable overlay ID updates
/// the existing overlay on this map. Removing the ID removes the overlay.
class AMapView extends StatefulWidget {
  const AMapView({
    super.key,
    this.latitude = 39.90923,
    this.longitude = 116.397428,
    this.zoom = 12,
    this.markers = const [],
    this.polylines = const [],
    this.circles = const [],
    this.polygons = const [],
    this.onMarkerTap,
    this.onMapTap,
    this.onMapCreated,
    this.onCameraMove,
    this.onCameraIdle,
    this.onStatusChanged,
    this.onError,
  });

  final double latitude;
  final double longitude;
  final double zoom;
  final List<AMapMarker> markers;
  final List<AMapPolyline> polylines;
  final List<AMapCircle> circles;
  final List<AMapPolygon> polygons;

  /// Receives the stable ID of a tapped marker on this map.
  final ValueChanged<String>? onMarkerTap;

  /// A native basemap single tap with its GCJ-02 coordinate.
  final ValueChanged<AMapLatLng>? onMapTap;

  /// Supplies the controller once this widget has a native map view.
  final ValueChanged<AMapController>? onMapCreated;

  /// Receives camera positions while the viewport is changing.
  final ValueChanged<AMapCameraEvent>? onCameraMove;

  /// Receives the final position and attributed reason after camera motion.
  final ValueChanged<AMapCameraEvent>? onCameraIdle;

  /// Observes native map creation, readiness, loading and failure.
  final ValueChanged<AMapStatus>? onStatusChanged;

  /// Receives an error code for this map instance.
  final ValueChanged<String>? onError;

  @override
  State<AMapView> createState() => _AMapViewState();
}

class _AMapViewState extends State<AMapView> with WidgetsBindingObserver {
  MethodChannel? _channel;
  AMapController? _controller;
  late final _cameraAttribution = _CameraAttribution(
    (event) => widget.onCameraMove?.call(event),
    (event) => widget.onCameraIdle?.call(event),
  );
  Timer? _loadTimer;
  Map<String, AMapMarker> _confirmedMarkers = {};
  final _possiblyAppliedIds = <String>{};
  Map<String, AMapMarker> _desiredMarkers = {};
  bool _syncingMarkers = false;
  int _markerRevision = 0;

  Map<String, AMapMarker> _markerSnapshot() {
    final result = <String, AMapMarker>{};
    for (final marker in widget.markers) {
      if (result.containsKey(marker.id)) {
        throw ArgumentError('Duplicate marker ID');
      }
      result[marker.id] = marker;
    }
    return result;
  }

  @override
  void didUpdateWidget(covariant AMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _polylines.update(widget.polylines);
    _circles.update(widget.circles);
    _polygons.update(widget.polygons);
    final desired = _markerSnapshot();
    if (desired.length == _desiredMarkers.length &&
        desired.values.every(
          (marker) => _desiredMarkers[marker.id]?.sameAs(marker) == true,
        )) {
      return;
    }
    _desiredMarkers = desired;
    _markerRevision++;
    unawaited(_syncMarkers());
  }

  Future<void> _syncMarkers() async {
    final controller = _controller;
    if (controller == null || _syncingMarkers) return;
    _syncingMarkers = true;
    var attemptedRevision = _markerRevision;
    try {
      while (mounted && !controller.isDisposed) {
        final revision = _markerRevision;
        attemptedRevision = revision;
        final desired = Map<String, AMapMarker>.of(_desiredMarkers);
        final upsert = desired.values
            .where(
              (m) =>
                  !_confirmedMarkers.containsKey(m.id) ||
                  !m.sameAs(_confirmedMarkers[m.id]!),
            )
            .map((m) => m.toMap())
            .toList();
        final remove = {
          ..._confirmedMarkers.keys,
          ..._possiblyAppliedIds,
        }.where((id) => !desired.containsKey(id)).toList();
        if (upsert.isNotEmpty || remove.isNotEmpty) {
          _possiblyAppliedIds.addAll(desired.keys);
          await controller._invoke<void>('updateMarkers', {
            'upsert': upsert,
            'remove': remove,
          });
          if (!mounted || controller.isDisposed) return;
          _confirmedMarkers = desired;
          _possiblyAppliedIds.clear();
        }
        if (revision == _markerRevision) break;
      }
    } catch (error) {
      if (mounted) {
        widget.onError?.call(
          error is PlatformException ? error.code : 'invalid_argument',
        );
      }
    } finally {
      _syncingMarkers = false;
      if (mounted && attemptedRevision != _markerRevision) {
        unawaited(_syncMarkers());
      }
    }
  }

  late final _polylines = _ShapeUpdates<AMapPolyline>(
    this,
    'polyline',
    'updatePolylines',
    (line) => line.id,
    (line) => line._toMap(),
    (a, b) => a._sameAs(b),
  );
  late final _circles = _ShapeUpdates<AMapCircle>(
    this,
    'circle',
    'updateCircles',
    (circle) => circle.id,
    (circle) => circle._toMap(),
    (a, b) => a._sameAs(b),
  );
  late final _polygons = _ShapeUpdates<AMapPolygon>(
    this,
    'polygon',
    'updatePolygons',
    (polygon) => polygon.id,
    (polygon) => polygon._toMap(),
    (a, b) => a._sameAs(b),
  );

  AMapStatus _status = AMapStatus.creating;

  @override
  void initState() {
    super.initState();
    _desiredMarkers = _markerSnapshot();
    _polylines.update(widget.polylines);
    _circles.update(widget.circles);
    _polygons.update(widget.polygons);
    WidgetsBinding.instance.addObserver(this);
  }

  bool get _active =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cameraAttribution.reset();
    final channel = _channel;
    if (channel != null) {
      unawaited(
        channel
            .invokeMethod<void>('setActive', _active)
            .timeout(const Duration(seconds: 5))
            .catchError((Object _) {
              if (mounted) widget.onError?.call('lifecycle_update_failed');
            }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _markerSnapshot();
    if (!widget.latitude.isFinite ||
        widget.latitude.abs() > 90 ||
        !widget.longitude.isFinite ||
        widget.longitude.abs() > 180 ||
        !widget.zoom.isFinite ||
        widget.zoom < 3 ||
        widget.zoom > 20) {
      throw ArgumentError('Invalid initial GCJ-02 camera');
    }
    return amapViewFactory({
      'protocolVersion': 1,
      'active': _active,
      'latitude': widget.latitude,
      'longitude': widget.longitude,
      'zoom': widget.zoom,
    }, _created);
  }

  Future<void> _created(int id) async {
    if (!mounted) return;
    final channel = MethodChannel('$amapViewType/$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'mapTap' &&
          _active &&
          _controller != null &&
          _status != AMapStatus.failed) {
        final data = call.arguments;
        if (data is Map) {
          final latitude = data['latitude'];
          final longitude = data['longitude'];
          if (latitude is num &&
              longitude is num &&
              latitude.isFinite &&
              latitude.abs() <= 90 &&
              longitude.isFinite &&
              longitude.abs() <= 180) {
            widget.onMapTap?.call(
              AMapLatLng(latitude.toDouble(), longitude.toDouble()),
            );
          }
        }
      }
      if (call.method == 'markerTap') {
        final id = call.arguments as String;
        if (_markerSnapshot()[id]?.visible == true) {
          widget.onMarkerTap?.call(id);
        }
      }
      if (call.method == 'status') _apply(call.arguments);
      if (call.method == 'cameraEvidence') {
        _cameraAttribution.evidence(call.arguments as Map);
      } else if (call.method == 'cameraMove' || call.method == 'cameraIdle') {
        _cameraAttribution.camera(
          call.arguments as Map,
          idle: call.method == 'cameraIdle',
        );
      }
    });
    _loadTimer = Timer(const Duration(seconds: 30), () {
      if (mounted &&
          _status != AMapStatus.loaded &&
          _status != AMapStatus.failed) {
        widget.onError?.call('map_load_timeout');
      }
    });
    try {
      await channel
          .invokeMethod<void>('setActive', _active)
          .timeout(const Duration(seconds: 5));
      // Snapshot closes the race between native creation and Dart subscription.
      final status = await channel
          .invokeMethod<String>('getStatus')
          .timeout(const Duration(seconds: 10));
      if (mounted) _apply(status);
    } catch (_) {
      if (mounted) _apply('failed');
    }
  }

  void _apply(Object? value) {
    final next = switch (value) {
      'ready' => AMapStatus.ready,
      'loaded' => AMapStatus.loaded,
      'failed' => AMapStatus.failed,
      _ => AMapStatus.creating,
    };
    // Ignore a stale snapshot after a more recent loaded/error event.
    if (_status == AMapStatus.failed) return;
    if (next.index <= _status.index) return;
    _status = next;
    if ((next == AMapStatus.ready || next == AMapStatus.loaded) &&
        _controller == null) {
      final controller = AMapController._(_channel!);
      _controller = controller;
      widget.onMapCreated?.call(controller);
      unawaited(_syncMarkers());
      unawaited(_polylines.sync());
      unawaited(_circles.sync());
      unawaited(_polygons.sync());
    }
    if (next == AMapStatus.loaded || next == AMapStatus.failed) {
      _loadTimer?.cancel();
    }
    widget.onStatusChanged?.call(next);
    if (next == AMapStatus.failed) widget.onError?.call('native_map_error');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadTimer?.cancel();
    _cameraAttribution.reset();
    _controller?._dispose();
    final channel = _channel;
    channel?.setMethodCallHandler(null);
    if (channel != null) {
      // Explicit release supplements the platform-view disposal callback.
      unawaited(
        channel
            .invokeMethod<void>('dispose')
            .timeout(const Duration(seconds: 5))
            .catchError((Object _) {}),
      );
    }
    super.dispose();
  }
}

// Correlates native input/command evidence with the camera snapshots for one map.
class _CameraAttribution {
  _CameraAttribution(this._onMove, this._onIdle);
  final ValueChanged<AMapCameraEvent> _onMove;
  final ValueChanged<AMapCameraEvent> _onIdle;
  final _clock = Stopwatch()..start();
  _CameraSample? _origin;
  _CameraSample? _pendingIdle;
  Timer? _idleTimer;
  bool _down = false;
  bool _drag = false;
  bool _multiple = false;
  bool _conflict = false;
  bool _zoomChanged = false;
  bool _orientationChanged = false;
  int _inputUntil = 0;
  int _commandUntil = 0;

  bool get _hasCommand => _clock.elapsedMilliseconds < _commandUntil;
  bool get _hasInput =>
      _origin != null && (_down || _clock.elapsedMilliseconds < _inputUntil);

  void evidence(Map data) {
    switch (data['kind']) {
      case 'start':
        final overlap =
            _hasCommand || _down || (_hasInput && _pendingIdle != null);
        _clearInput();
        _commandUntil = 0;
        _origin = _CameraSample(data);
        _down = true;
        _conflict = overlap;
      case 'drag':
        if (_down) _drag = true;
      case 'multi':
      case 'zoom':
        if (_down) _multiple = true;
      case 'end':
        if (!_down) return;
        _down = false;
        _inputUntil = _clock.elapsedMilliseconds + 1200;
        _scheduleIdle();
      case 'program':
        if (_down) {
          _conflict = true;
          _pendingIdle = null;
          _commandUntil = 0;
        } else {
          _clearInput();
          _commandUntil = _clock.elapsedMilliseconds + 2000;
        }
      case 'reset':
      case 'cancel':
        reset();
    }
  }

  void camera(Map data, {required bool idle}) {
    final sample = _CameraSample(data);
    if (!_hasInput) {
      _clearInput();
      final reason = _hasCommand
          ? AMapCameraReason.programmatic
          : AMapCameraReason.unknown;
      if (idle) {
        _commandUntil = 0;
        _onIdle(AMapCameraEvent(sample.position, reason: reason));
      } else {
        _onMove(AMapCameraEvent(sample.position, reason: reason));
      }
      return;
    }

    final origin = _origin!;
    _zoomChanged |= (sample.position.zoom - origin.position.zoom).abs() > .001;
    _orientationChanged |= sample.orientationDiffersFrom(origin);
    if (idle) {
      _pendingIdle = sample;
      if (!_down) _scheduleIdle();
    } else {
      _pendingIdle = null;
      _idleTimer?.cancel();
      _onMove(AMapCameraEvent(sample.position, reason: _reason(sample)));
    }
  }

  AMapCameraReason _reason(_CameraSample sample) {
    if (_conflict) return AMapCameraReason.unknown;
    if (_zoomChanged) {
      return _multiple ? AMapCameraReason.userZoom : AMapCameraReason.unknown;
    }
    final position = sample.position;
    final origin = _origin!.position;
    if (_drag &&
        !_multiple &&
        !_orientationChanged &&
        (position.latitude != origin.latitude ||
            position.longitude != origin.longitude)) {
      return AMapCameraReason.userDrag;
    }
    return AMapCameraReason.unknown;
  }

  void _scheduleIdle() {
    _idleTimer?.cancel();
    if (_pendingIdle == null) return;
    // A native idle may arrive before release or before an inertia animation.
    _idleTimer = Timer(const Duration(milliseconds: 120), () {
      final sample = _pendingIdle!;
      final reason = _hasInput ? _reason(sample) : AMapCameraReason.unknown;
      _clearInput();
      _onIdle(AMapCameraEvent(sample.position, reason: reason));
    });
  }

  void _clearInput() {
    _idleTimer?.cancel();
    _pendingIdle = null;
    _origin = null;
    _down = _drag = _multiple = _conflict = _zoomChanged = _orientationChanged =
        false;
    _inputUntil = 0;
  }

  void reset() {
    _clearInput();
    _commandUntil = 0;
  }
}

class _CameraSample {
  _CameraSample(Map data)
    : position = AMapCameraPosition.fromMap(data),
      bearing = (data['bearing'] as num?)?.toDouble(),
      tilt = (data['tilt'] as num?)?.toDouble();

  final AMapCameraPosition position;
  final double? bearing;
  final double? tilt;

  bool orientationDiffersFrom(_CameraSample origin) {
    bool changed(double? current, double? initial) =>
        current == null || initial == null || (current - initial).abs() > .01;
    return changed(bearing, origin.bearing) || changed(tilt, origin.tilt);
  }
}

// Each shape type has its own confirmed state on each map. Sharing the update
// loop keeps failure and disposal behavior consistent across shape types.
class _ShapeUpdates<T> {
  _ShapeUpdates(
    this._owner,
    this._name,
    this._method,
    this._id,
    this._encode,
    this._same,
  );
  final _AMapViewState _owner;
  final String _name;
  final String _method;
  final String Function(T) _id;
  final Map<String, Object> Function(T) _encode;
  final bool Function(T, T) _same;

  Map<String, T> _desired = {};
  Map<String, T> _confirmed = {};
  final _uncertain = <String>{};
  bool _syncing = false;

  void update(List<T> values) {
    final desired = <String, T>{};
    for (final value in values) {
      final id = _id(value);
      if (desired.containsKey(id)) throw ArgumentError('Duplicate $_name ID');
      desired[id] = value;
    }
    if (desired.length == _desired.length &&
        desired.entries.every((entry) {
          final previous = _desired[entry.key];
          return previous != null && _same(previous, entry.value);
        })) {
      return;
    }
    _desired = desired;
    unawaited(sync());
  }

  Future<void> sync() async {
    final controller = _owner._controller;
    if (controller == null || _syncing) return;
    _syncing = true;
    var desired = _desired;
    try {
      do {
        desired = _desired;
        final upsert = desired.entries.where((entry) {
          final previous = _confirmed[entry.key];
          return _uncertain.contains(entry.key) ||
              previous == null ||
              !_same(previous, entry.value);
        }).toList();
        final remove = {
          ..._confirmed.keys,
          ..._uncertain,
        }.where((id) => !desired.containsKey(id)).toList();
        if (upsert.isEmpty && remove.isEmpty) return;
        _uncertain.addAll(upsert.map((entry) => entry.key));
        _uncertain.addAll(remove);
        await controller._invoke<void>(_method, {
          'upsert': upsert.map((entry) => _encode(entry.value)).toList(),
          'remove': remove,
        });
        if (!_owner.mounted || controller.isDisposed) return;
        _confirmed = desired;
        _uncertain.clear();
      } while (!identical(desired, _desired));
    } catch (error) {
      if (_owner.mounted) {
        _owner.widget.onError?.call(
          error is PlatformException ? error.code : 'native_error',
        );
      }
    } finally {
      _syncing = false;
      if (_owner.mounted && !identical(desired, _desired)) unawaited(sync());
    }
  }
}
