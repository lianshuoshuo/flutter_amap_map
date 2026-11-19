import 'dart:async';

import 'package:flutter_amap_map/flutter_amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const demoPetPinAsset = 'packages/amap_example_scenes/assets/pet_pin.png';

class LocatorMapPage extends StatefulWidget {
  const LocatorMapPage({super.key, required this.markerPng});
  final Uint8List markerPng;

  @override
  State<LocatorMapPage> createState() => _LocatorMapPageState();
}

class _LocatorMapPageState extends State<LocatorMapPage> {
  // Public demonstration coordinates near Shenzhen Civic Center.
  static const _route = [
    AMapLatLng(22.54365, 114.05850),
    AMapLatLng(22.54385, 114.05895),
    AMapLatLng(22.54355, 114.05930),
    AMapLatLng(22.54315, 114.05902),
    AMapLatLng(22.54330, 114.05848),
  ];
  static const _interval = Duration(seconds: 2);
  static const _markerHeight = 36.0;
  static const _labelWidth = 92.0;
  static const _labelHeight = 28.0;
  int _step = 0;
  AMapLatLng get _point => _route[_step % _route.length];

  AMapController? _map;
  Timer? _timer;
  Offset? _anchor;
  Size? _viewport;
  bool _projecting = false;
  bool _pendingProjection = false;
  bool _positionUpdate = false;
  AMapCameraReason? _cameraReason;
  String? _error;

  void _onLoaded(AMapStatus status) {
    if (status != AMapStatus.loaded || _timer != null) return;
    _refreshAnchor();
    _timer = Timer.periodic(_interval, (_) {
      if (_positionUpdate || _projecting) return;
      _positionUpdate = true;
      setState(() {
        _step++;
        _anchor = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _positionUpdate = false;
        _refreshAnchor();
      });
    });
  }

  Future<void> _refreshAnchor() async {
    final map = _map;
    if (_positionUpdate || map == null) return;
    _pendingProjection = true;
    if (_projecting) return;

    _projecting = true;
    try {
      while (mounted && _pendingProjection) {
        _pendingProjection = false;
        final step = _step;
        final anchor = await map.projectToScreen(_point);
        if (!mounted || step != _step) return;
        setState(() => _anchor = anchor);
      }
    } on PlatformException catch (error) {
      if (mounted && error.code != 'map_not_ready') {
        setState(() {
          _anchor = null;
          _error = error.code;
        });
      }
    } finally {
      _projecting = false;
    }
  }

  Future<void> _recenter() async {
    final point = _point;
    try {
      await _map?.moveCamera(
        AMapCameraPosition(
          latitude: point.latitude,
          longitude: point.longitude,
          zoom: 16,
        ),
      );
      if (mounted) _refreshAnchor();
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.code);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('定位器地图'),
      actions: [
        TextButton(
          onPressed: _map == null ? null : _recenter,
          child: const Text('回到宠物位置'),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Text(
            '位置更新 #$_step · ${_cameraReason?.name ?? '等待相机'}',
            key: const ValueKey('locator-status'),
          ),
          if (_error != null) Text('地图错误：$_error'),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                if (_viewport != size) {
                  _viewport = size;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _refreshAnchor();
                  });
                }
                final point = _point;
                final anchor = _anchor;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    AMapView(
                      latitude: _route.first.latitude,
                      longitude: _route.first.longitude,
                      zoom: 16,
                      markers: [
                        AMapMarker(
                          id: 'simulated-pet',
                          latitude: point.latitude,
                          longitude: point.longitude,
                          pngBytes: widget.markerPng,
                          width: 27,
                          height: _markerHeight,
                        ),
                      ],
                      onMapCreated: (map) {
                        setState(() => _map = map);
                        _refreshAnchor();
                      },
                      onStatusChanged: _onLoaded,
                      onCameraMove: (_) => _refreshAnchor(),
                      onCameraIdle: (event) {
                        setState(() => _cameraReason = event.reason);
                        _refreshAnchor();
                      },
                      onError: (code) => setState(() => _error = code),
                    ),
                    if (anchor != null && (Offset.zero & size).contains(anchor))
                      Positioned(
                        left: anchor.dx - _labelWidth / 2,
                        top: anchor.dy - _markerHeight - _labelHeight - 2,
                        width: _labelWidth,
                        height: _labelHeight,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xff063a52),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '豆豆 #$_step',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
